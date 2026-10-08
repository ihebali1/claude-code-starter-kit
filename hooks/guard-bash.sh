#!/usr/bin/env bash
# PreToolUse / Bash — refuse destructive shell commands before they run.
#
# Wire it up:
#   "PreToolUse": [{ "matcher": "Bash",
#     "hooks": [{ "type": "command", "command": "~/.claude/hooks/guard-bash.sh" }] }]
#
# Contract: the hook payload arrives as JSON on stdin.
#   exit 0  -> allow (print nothing)
#   exit 2  -> BLOCK. stderr is fed back to Claude so it can choose another path.
#   other   -> non-blocking error; the tool still runs. Never rely on it to deny.
#
# ZERO DEPENDENCIES. No jq, no sed, no grep, no /dev/stdin, no cat. Everything here
# is a bash builtin. A guard that silently stops guarding because a binary is missing
# from the hook's PATH is worse than no guard, because you think you are covered.
# Requires bash 3.2+ (the version macOS ships).
#
# Design note: this denies a short list of genuinely unrecoverable actions, loudly,
# with a reason the model can act on. A guard that blocks everything gets switched
# off within a week, which is the real failure mode.

set -uo pipefail

# --- read stdin using only builtins -----------------------------------------
payload=""
IFS= read -r -d '' payload || true   # reads to EOF; non-zero at EOF is expected

# Fail-open vs fail-closed. If the payload cannot be read we allow by default,
# because a guard that bricks every session gets uninstalled the same day.
# Set CLAUDE_GUARD_STRICT=1 to invert that on a high-risk machine.
if [ -z "$payload" ]; then
  if [ "${CLAUDE_GUARD_STRICT:-0}" = "1" ]; then
    echo "guard-bash: could not read hook input and CLAUDE_GUARD_STRICT=1 — denying." >&2
    exit 2
  fi
  echo "guard-bash: could not read hook input; allowing (set CLAUDE_GUARD_STRICT=1 to deny)" >&2
  exit 0
fi

# --- pull .tool_input.command out of the JSON, with builtins only ------------
cmd=""
if [[ "$payload" =~ \"command\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
  cmd="${BASH_REMATCH[1]}"
fi
[ -z "$cmd" ] && exit 0

# Unescape the JSON string so patterns match what will actually run.
cmd="${cmd//\\n/ }"
cmd="${cmd//\\t/ }"
cmd="${cmd//\\\"/\"}"
cmd="${cmd//\\\\/\\}"

deny() {
  # stderr + exit 2 is the documented way to block and explain.
  echo "BLOCKED by guard-bash: $1" >&2
  echo "Command: $cmd" >&2
  echo "If this is genuinely required, ask the user to run it themselves." >&2
  exit 2
}

# Some rules must be case-insensitive (SQL is conventionally uppercase). `shopt -s
# nocasematch` does it inside bash — `${cmd,,}` would be shorter but needs bash 4,
# and macOS still ships bash 3.2. Scoped tightly and restored below.

# --- 1. Recursive deletion of a root-ish path -------------------------------
# rm with an -r flag (any flag ordering) targeting /, ~, $HOME or ..
if [[ "$cmd" =~ (^|[\;\&\|[:space:]])rm[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-?[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+(/|~|\$HOME|\.\.)([[:space:]]|$) ]] \
   || [[ "$cmd" =~ (^|[\;\&\|[:space:]])rm[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-?[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+(/\*|~/\*)([[:space:]]|$) ]]; then
  deny "recursive delete of a root, home or parent directory"
fi

# --- 2. Git history destruction ----------------------------------------------
if [[ "$cmd" =~ git[[:space:]]+push[[:space:]].*(--force|[[:space:]]-f)([[:space:]]|$) ]] \
   && [[ ! "$cmd" =~ --force-with-lease ]]; then
  deny "git push --force without --force-with-lease (can erase a teammate's commits)"
fi

if [[ "$cmd" =~ git[[:space:]]+reset[[:space:]]+--hard ]]; then
  deny "git reset --hard discards uncommitted work irreversibly; stash or commit first"
fi

if [[ "$cmd" =~ git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[fdx] ]]; then
  deny "git clean deletes untracked files permanently"
fi

if [[ "$cmd" =~ git[[:space:]]+branch[[:space:]]+-D ]] \
   || [[ "$cmd" =~ git[[:space:]]+push[[:space:]].*--delete ]]; then
  deny "branch deletion"
fi

# --- 3. Destructive and production database operations ------------------------
shopt -s nocasematch

if [[ "$cmd" =~ drop[[:space:]]+(database|table|schema) ]] \
   || [[ "$cmd" =~ truncate[[:space:]]+table ]]; then
  shopt -u nocasematch
  deny "destructive SQL (DROP/TRUNCATE). Run it as a reviewed migration instead"
fi

if [[ "$cmd" =~ (psql|mysql|mongo|sqlcmd|redis-cli) ]] && [[ "$cmd" =~ (prod|production) ]]; then
  shopt -u nocasematch
  deny "direct client connection to something named production"
fi

shopt -u nocasematch

# --- 4. Credential and key exposure -------------------------------------------
if [[ "$cmd" =~ (cat|less|more|head|tail|strings|type)[[:space:]]+[^\|\;\&]*(\.env($|[^.])|id_rsa|id_ed25519|\.pem|\.p12|\.pfx|credentials\.json|\.aws/credentials|\.ssh/) ]]; then
  deny "reading a credential file into the transcript"
fi

if [[ "$cmd" =~ curl[[:space:]].*\|[[:space:]]*(ba)?sh ]] \
   || [[ "$cmd" =~ wget[[:space:]].*\|[[:space:]]*(ba)?sh ]]; then
  deny "piping a downloaded script straight into a shell executes unreviewed remote code"
fi

# --- 5. Infrastructure ---------------------------------------------------------
if [[ "$cmd" =~ terraform[[:space:]]+(destroy|apply)([[:space:]]|$) ]]; then
  deny "terraform apply/destroy — run infrastructure changes through CI, not the agent"
fi

if [[ "$cmd" =~ kubectl[[:space:]]+delete ]] \
   || [[ "$cmd" =~ aws[[:space:]]+s3[[:space:]]+rb ]] \
   || [[ "$cmd" =~ aws[[:space:]]+ec2[[:space:]]+terminate-instances ]] \
   || [[ "$cmd" =~ aws[[:space:]]+rds[[:space:]]+delete ]]; then
  deny "cloud resource deletion"
fi

# --- 6. Turning off your own safety net ----------------------------------------
if [[ "$cmd" =~ (--no-verify|--no-gpg-sign|HUSKY=0|SKIP_HOOKS) ]]; then
  deny "bypassing commit hooks. Fix the failing check instead of skipping it"
fi

if [[ "$cmd" =~ chmod[[:space:]]+(-[a-zA-Z]+[[:space:]]+)?777 ]]; then
  deny "chmod 777 grants world-write permission"
fi

exit 0

#!/usr/bin/env bash
# PreToolUse / Write|Edit — refuse writes to files that must never be agent-authored,
# and refuse content that looks like a live credential.
#
# Wire it up:
#   "PreToolUse": [{ "matcher": "Write|Edit",
#     "hooks": [{ "type": "command", "command": "~/.claude/hooks/guard-write.sh" }] }]
#
# exit 0 allow · exit 2 block (stderr is fed back to Claude).
#
# ZERO DEPENDENCIES — bash builtins only. See guard-bash.sh for the reasoning.
#
# Why a hook rather than just a permissions deny rule? A deny rule stops the write
# but explains nothing, so the agent retries variations of the same thing. This
# gives a reason, so it routes around the problem. Use both: the permission rule is
# the wall, this is the sign on it.

set -uo pipefail

payload=""
IFS= read -r -d '' payload || true

if [ -z "$payload" ]; then
  if [ "${CLAUDE_GUARD_STRICT:-0}" = "1" ]; then
    echo "guard-write: could not read hook input and CLAUDE_GUARD_STRICT=1 — denying." >&2
    exit 2
  fi
  echo "guard-write: could not read hook input; allowing (set CLAUDE_GUARD_STRICT=1 to deny)" >&2
  exit 0
fi

# --- extract file_path and the content being written -------------------------
path=""
if [[ "$payload" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
  path="${BASH_REMATCH[1]}"
fi
[ -z "$path" ] && exit 0
path="${path//\\\\/\\}"
path="${path//\\\"/\"}"

content=""
if [[ "$payload" =~ \"content\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
  content="${BASH_REMATCH[1]}"
elif [[ "$payload" =~ \"new_string\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
  content="${BASH_REMATCH[1]}"
fi
content="${content//\\n/ }"
content="${content//\\\"/\"}"

deny() {
  echo "BLOCKED by guard-write: $1" >&2
  echo "Path: $path" >&2
  exit 2
}

base="${path##*/}"

# --- 1. Files an agent should never author ------------------------------------
case "$base" in
  .env|.env.?*|*.pem|*.key|*.p12|*.pfx|id_rsa|id_ed25519|credentials|credentials.json)
    # .env.example and friends are templates, not secrets — let those through.
    case "$base" in
      .env.example|.env.sample|.env.template|.env.dist) ;;
      *) deny "credential file. Ask the user to edit it by hand; never generate secrets" ;;
    esac ;;
  package-lock.json|yarn.lock|pnpm-lock.yaml|poetry.lock|Cargo.lock|Gemfile.lock|composer.lock|*.lock)
    deny "lockfile. Regenerate it with the package manager so the integrity hashes are real" ;;
esac

# --- 2. Protected directories --------------------------------------------------
case "$path" in
  */.git/*)          deny "inside .git/ — use git commands, not file edits" ;;
  */node_modules/*)  deny "inside node_modules/ — patch via the package manager or patch-package" ;;
  */vendor/*)        deny "inside vendor/ — vendored dependencies are regenerated, not edited" ;;
  */.venv/*|*/venv/*|*/site-packages/*) deny "inside a virtualenv" ;;
  */dist/*|*/build/*|*/.next/*|*/target/*|*/__pycache__/*|*/coverage/*)
    deny "build output — edit the source and rebuild" ;;
  */migrations/*)
    # New migrations are fine; already-applied ones are immutable.
    if [ -f "$path" ]; then
      deny "an existing migration file. Applied migrations are immutable — add a new one"
    fi ;;
esac

# --- 3. Content that looks like a live secret -----------------------------------
if [ -n "$content" ]; then
  if [[ "$content" =~ sk-[A-Za-z0-9_-]{20,} ]] \
     || [[ "$content" =~ (ghp|gho|ghs|ghu)_[A-Za-z0-9]{30,} ]] \
     || [[ "$content" =~ AKIA[0-9A-Z]{16} ]] \
     || [[ "$content" =~ -----BEGIN[[:space:]][A-Z\ ]*PRIVATE[[:space:]]KEY----- ]] \
     || [[ "$content" =~ xox[baprs]-[A-Za-z0-9-]{10,} ]] \
     || [[ "$content" =~ AIza[A-Za-z0-9_-]{30,} ]]; then
    deny "the content contains something shaped like a live API key or private key. Use an environment variable"
  fi

  # A quoted literal assigned to a secret-ish name, unless it is clearly a placeholder.
  if [[ "$content" =~ [Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][[:space:]]*[:=][[:space:]]*[\"\'][^\"\'$\{]{8,}[\"\'] ]] \
     || [[ "$content" =~ [Ss][Ee][Cc][Rr][Ee][Tt][[:space:]]*[:=][[:space:]]*[\"\'][^\"\'$\{]{8,}[\"\'] ]] \
     || [[ "$content" =~ [Aa][Pp][Ii]_?[Kk][Ee][Yy][[:space:]]*[:=][[:space:]]*[\"\'][^\"\'$\{]{8,}[\"\'] ]]; then
    if [[ ! "$content" =~ (example|EXAMPLE|changeme|CHANGEME|placeholder|PLACEHOLDER|your[-_]|YOUR[-_]|xxx|XXX|\<|\*\*\*|dummy|DUMMY|test123|redacted|REDACTED) ]]; then
      deny "a hardcoded credential literal. Read it from the environment instead"
    fi
  fi
fi

exit 0

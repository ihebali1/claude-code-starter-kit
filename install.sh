#!/usr/bin/env bash
# Install the starter kit into ~/.claude (default) or ./.claude (--project).
#
#   ./install.sh              # personal: every project on this machine
#   ./install.sh --project    # this repo only, committable, shared with the team
#   ./install.sh --dry-run    # print what would happen and change nothing
#
# This script copies files and makes the hooks executable. It will NOT edit your
# settings.json — hooks only run once they are wired up there, and silently
# rewriting that file is exactly the kind of thing this kit exists to prevent.
# The exact block to paste is printed at the end.

set -euo pipefail

# Path manipulation via bash parameter expansion rather than dirname/basename, so
# this works in a minimal container that ships bash and little else. The copying
# itself still needs mkdir/cp/chmod; nothing portable avoids those.
self="${BASH_SOURCE[0]}"
self_dir="${self%/*}"
[ "$self_dir" = "$self" ] && self_dir="."
SRC="$(cd "$self_dir" && pwd)"
TARGET="$HOME/.claude"
SCOPE="personal"
DRY_RUN=0

say() { printf '%s\n' "$1"; }
run() { if [ "$DRY_RUN" = "1" ]; then say "  would: $*"; else "$@"; fi; }

for arg in "$@"; do
  case "$arg" in
    --project) TARGET="$PWD/.claude"; SCOPE="project" ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      say "Usage: install.sh [--project] [--dry-run]"
      say "  --project   install into ./.claude instead of ~/.claude"
      say "  --dry-run   print what would happen and change nothing"
      exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
  esac
done

say "Installing claude-code-starter-kit"
say "  scope:  $SCOPE"
say "  target: $TARGET"
[ "$DRY_RUN" = "1" ] && say "  (dry run — nothing will be written)"
say ""

# --- hooks -------------------------------------------------------------------
say "hooks/"
run mkdir -p "$TARGET/hooks"
for f in "$SRC"/hooks/*.sh; do
  name="${f##*/}"
  # Never clobber a hook the user has edited without leaving them a copy.
  if [ -e "$TARGET/hooks/$name" ]; then
    say "  ! $name already exists — backing it up to $name.bak"
    run cp "$TARGET/hooks/$name" "$TARGET/hooks/$name.bak"
  fi
  run cp "$f" "$TARGET/hooks/$name"
  run chmod +x "$TARGET/hooks/$name"
  say "  + $name"
done

# --- skills ------------------------------------------------------------------
say "skills/"
run mkdir -p "$TARGET/skills"
for d in "$SRC"/skills/*/; do
  trimmed="${d%/}"
  name="${trimmed##*/}"
  run mkdir -p "$TARGET/skills/$name"
  run cp "$trimmed/SKILL.md" "$TARGET/skills/$name/SKILL.md"
  say "  + $name"
done

# --- agents ------------------------------------------------------------------
say "agents/"
run mkdir -p "$TARGET/agents"
for f in "$SRC"/agents/*.md; do
  name="${f##*/}"
  run cp "$f" "$TARGET/agents/$name"
  say "  + ${name%.md}"
done

# In project scope the hooks live inside the repo, so reference them through
# $CLAUDE_PROJECT_DIR — that resolves correctly for every teammate who clones it.
if [ "$SCOPE" = "project" ]; then
  HOOK_PREFIX='$CLAUDE_PROJECT_DIR/.claude/hooks'
else
  HOOK_PREFIX='~/.claude/hooks'
fi

say ""
say "Done. Two things left, both manual:"
say ""
say "1. Wire up the hooks. Merge this into $TARGET/settings.json"
say "   (see settings.example.json for a copy you can paste):"
say ""
say '   {'
say '     "hooks": {'
say '       "PreToolUse": ['
say '         { "matcher": "Bash",'
say "           \"hooks\": [{ \"type\": \"command\", \"command\": \"$HOOK_PREFIX/guard-bash.sh\" }] },"
say '         { "matcher": "Write|Edit",'
say "           \"hooks\": [{ \"type\": \"command\", \"command\": \"$HOOK_PREFIX/guard-write.sh\" }] }"
say '       ]'
say '     }'
say '   }'
say ""
say "2. Restart Claude Code, then verify:"
say "     /skills                       -> lists debug-systematically, write-tests"
say "     /agents                       -> lists code-reviewer"
say "     ask it to run:  git reset --hard HEAD~1"
say "                                   -> must be refused by guard-bash"
say ""
say "Prove the hooks work without involving Claude at all:  node tests/test-guards.mjs"

# Claude Code Starter Kit

[![tests](https://github.com/ihebali1/claude-code-starter-kit/actions/workflows/test.yml/badge.svg)](https://github.com/ihebali1/claude-code-starter-kit/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Five things worth installing before you let Claude Code near a repository you care
about: two hooks that stop it doing damage, two skills that make it work like an
engineer instead of a guesser, and a reviewer subagent that checks its output.

No dependencies. No build step. No telemetry. Plain bash and Markdown you can read
in ten minutes and edit to taste.

```
hooks/guard-bash.sh      refuse destructive shell commands before they run
hooks/guard-write.sh     refuse writes to credential files and protected paths
skills/debug-systematically   kill hypotheses with evidence instead of guess-and-patch
skills/write-tests       tests that fail when the code breaks
agents/code-reviewer     a read-only reviewer that reports defects, not opinions
```

---

## 30-second install

```bash
git clone https://github.com/ihebali1/claude-code-starter-kit.git
cd claude-code-starter-kit
./install.sh                    # into ~/.claude  (every project on this machine)
```

```powershell
# Windows
.\install.ps1
```

Then merge this into `~/.claude/settings.json` — the installer prints it too, and
`settings.example.json` has a fuller version with matching permission rules:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "~/.claude/hooks/guard-bash.sh" }] },
      { "matcher": "Write|Edit",
        "hooks": [{ "type": "command", "command": "~/.claude/hooks/guard-write.sh" }] }
    ]
  }
}
```

Restart Claude Code. Other options: `./install.sh --project` installs into
`./.claude` so you can commit it and your whole team gets it on next pull;
`./install.sh --dry-run` shows you what it would do and writes nothing.

---

## Worked example: the hook earning its keep

Ask Claude to clean up a branch and it reaches for the obvious command:

```
> my rebase went wrong, reset the branch back three commits

● Bash(git reset --hard HEAD~3)
  ⎿  Error: BLOCKED by guard-bash: git reset --hard discards uncommitted work
     irreversibly; stash or commit first
     Command: git reset --hard HEAD~3
     If this is genuinely required, ask the user to run it themselves.

● The guard blocked that, and it is right — you have uncommitted changes in
  src/. Let me stash them first, then reset:

● Bash(git stash push -m "wip before reset")
  ⎿  Saved working directory and index state
```

That is the whole design. The hook exits 2 and writes a *reason* to stderr; Claude
reads the reason and routes around the problem. A plain permission denial would
have stopped the command and told it nothing, so it would have tried three
variations of the same thing.

The same applies to writes:

```
● Write(.env)
  ⎿  Error: BLOCKED by guard-write: credential file. Ask the user to edit it by
     hand; never generate secrets
```

---

## Prove it actually works

The hooks ship with a test suite that pipes real hook payloads into them and
asserts the exit codes. No Claude Code installation required:

```bash
node tests/test-guards.mjs
```

```
--- guard-bash.sh (39 cases) ---
  ok    [2] recursive root delete
  ok    [2] force push
  ok    [2] hard reset
  ...
  ok    [0] force-with-lease is fine
  ok    [0] delete build dir
  ok    [0] terraform plan
--- guard-write.sh (23 cases) ---
  ok    [2] dotenv file
  ok    [2] aws key in content
  ...
  ok    [0] env example template
  ok    [0] env var read

=== 62 passed, 0 failed ===
```

`npm test` runs all three suites: frontmatter validation, the 62 guard cases, and
an install smoke test that installs into a throwaway `HOME` and checks every file
landed. CI runs them on Ubuntu, macOS and Windows.

Roughly a third of the guard cases assert that something is **allowed**. That is
deliberate: a guard that blocks `terraform plan` along with `terraform destroy`
gets switched off within a week, and then you have no guard at all.

---

## What each piece does

### `hooks/guard-bash.sh` — PreToolUse / Bash

Blocks, with a reason the model can act on:

- recursive deletes of `/`, `~`, `$HOME`, `..`
- `git push --force` (but **not** `--force-with-lease`), `reset --hard`,
  `clean -fdx`, branch deletion
- `DROP TABLE` / `TRUNCATE`, and any db client pointed at something named `prod`
- reading `.env`, `id_rsa`, `.pem`, `~/.aws/credentials` into the transcript
- `curl … | sh`
- `terraform apply/destroy`, `kubectl delete`, `aws ec2 terminate-instances`
- `--no-verify` and friends — bypassing the checks you installed on purpose
- `chmod 777`

### `hooks/guard-write.sh` — PreToolUse / Write|Edit

Blocks writes to credential files, lockfiles, `.git/`, `node_modules/`, `vendor/`,
build output and already-applied migrations — and blocks *content* matching live
credential shapes (`sk-…`, `ghp_…`, `AKIA…`, `xoxb-…`, `AIza…`, PEM private key
headers, hardcoded password literals). Obvious placeholders are allowed through.

Both hooks are **zero-dependency**: bash builtins only, no `jq`, no `grep`, no
`sed`. A guard that silently stops guarding because a binary is missing from the
hook's PATH is worse than no guard, because you think you are covered. (This was
not theoretical — these hooks ran correctly in a locked-down sandbox that had bash
and nothing else.) Requires bash 3.2+, the version macOS ships.

They **fail open** by default: if the payload cannot be read, the command is
allowed and a warning goes to stderr. Set `CLAUDE_GUARD_STRICT=1` to fail closed.

### `skills/debug-systematically` and `skills/write-tests`

Markdown procedures Claude loads when the task matches the `description` line.
`debug-systematically` forces reproduce → evidence → three ranked hypotheses →
cheapest elimination test → confirm mechanism → fix → check for siblings.
`write-tests` is built around one rule: a test that does not fail when you break
the code tests nothing.

### `agents/code-reviewer`

A subagent with `tools: Read, Grep, Glob, Bash` — no write access, deliberately,
because a reviewer that fixes things stops reviewing. Every finding must come with
a concrete failure scenario (specific inputs → specific wrong output) or it gets
deleted. Invoke with `/agents` or just ask for a review.

---

## What this does not do

Being straight about the limits, because the gap between "security tool" and what
this actually is matters:

- **It is not a sandbox and not a security boundary.** These are heuristic pattern
  matches on command strings. A determined or sufficiently creative agent can get
  around them — base64 a command, write a script and run it, use a path spelling
  the regex does not cover. This raises the floor on accidents; it does not contain
  an adversary. If you need real containment, use a container with no credentials
  in it.
- **The blocklist is not exhaustive.** It covers the destructive things we have
  actually watched agents do. Your stack has others. Read the scripts and add them —
  that is the intended use, and they are short enough to read in one sitting.
- **There will be false positives.** A guard tuned to zero false positives blocks
  nothing useful. When one gets in your way, edit the rule.
- **Hooks do not run until you wire them into `settings.json`.** Copying the files
  does nothing on its own. Run the verification step.
- **The skills are prompts, not enforcement.** Claude follows them well, not
  perfectly. For critical workflows, ask it to output the checklist explicitly.
- **Windows needs Git Bash.** The hooks are bash scripts. Claude Code's Bash tool
  uses Git Bash on Windows, so they work — but `bash` must be on your PATH.
- **No Claude Code version pinning.** Hook payload shapes are stable in practice
  but not contractual. If a future version changes them, the tests here are how
  you will find out.

---

## Contributing

Issues and PRs welcome, especially: destructive commands we missed, false
positives that annoyed you, and bash-3.2 portability bugs. Every PR needs a test
case in `tests/test-guards.mjs` — add the case, watch it fail, then fix the guard.

---

## If you want the complete set

This kit is five of the pieces we use. They are MIT licensed, complete, and not
crippled — use them forever without paying us anything.

The full collections are on Gumroad, from [RevampIT LLC](https://revampit.net):

| | |
|---|---|
| [**Claude Code Skills Pack**](https://revampitllc.gumroad.com/l/fricn) — 20 production skills | $39 |
| [**AI Coding Agent Guardrails**](https://revampitllc.gumroad.com/l/qwjgux) — the full hook set, settings recipes and 45 tests | $29 |
| [**Subagents & Commands Pack**](https://revampitllc.gumroad.com/l/nffwn) — 10 subagents, 11 slash commands | $49 |

If the two hooks above are earning their keep, the Guardrails pack is the same
thing with the rest of the hooks — audit logging, post-edit test verification —
and the settings recipes to wire them together.

No hard feelings if you just take the free five. That is what it is for.

---

MIT licensed. Copyright (c) 2026 RevampIT LLC.

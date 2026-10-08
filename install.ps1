<#
Install the starter kit into $HOME\.claude (default) or .\.claude (-Project).

  .\install.ps1              # personal: every project on this machine
  .\install.ps1 -Project     # this repo only, committable, shared with the team
  .\install.ps1 -DryRun      # print what would happen and change nothing

This script copies files only. It will NOT edit your settings.json — hooks run
only once they are wired up there, and silently rewriting that file is exactly
the kind of thing this kit exists to prevent. The block to paste is printed at
the end.

Note: the hooks are bash scripts. On Windows they run under Git Bash, which
Claude Code uses for its Bash tool. If `bash` is not on your PATH, install
Git for Windows first.
#>
[CmdletBinding()]
param(
  [switch]$Project,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$src = $PSScriptRoot
if ($Project) { $target = Join-Path (Get-Location) '.claude'; $scope = 'project' }
else          { $target = Join-Path $HOME '.claude';          $scope = 'personal' }

Write-Output "Installing claude-code-starter-kit"
Write-Output "  scope:  $scope"
Write-Output "  target: $target"
if ($DryRun) { Write-Output "  (dry run - nothing will be written)" }
Write-Output ""

function Ensure-Dir($path) {
  if ($DryRun) { Write-Output "  would: create $path"; return }
  if (-not (Test-Path $path)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
}

function Copy-One($from, $to) {
  if ($DryRun) { Write-Output "  would: copy -> $to"; return }
  Copy-Item -Path $from -Destination $to -Force
}

# --- hooks -------------------------------------------------------------------
Write-Output "hooks/"
Ensure-Dir (Join-Path $target 'hooks')
foreach ($f in Get-ChildItem (Join-Path $src 'hooks') -Filter *.sh) {
  $dest = Join-Path $target "hooks\$($f.Name)"
  if ((Test-Path $dest) -and -not $DryRun) {
    $same = (Get-FileHash $f.FullName).Hash -eq (Get-FileHash $dest).Hash
    if (-not $same) {
      Write-Output "  ! $($f.Name) already exists and differs - backing it up to $($f.Name).bak"
      Copy-Item $dest "$dest.bak" -Force
    }
  }
  Copy-One $f.FullName $dest
  Write-Output "  + $($f.Name)"
}

# --- skills ------------------------------------------------------------------
Write-Output "skills/"
Ensure-Dir (Join-Path $target 'skills')
foreach ($d in Get-ChildItem (Join-Path $src 'skills') -Directory) {
  Ensure-Dir (Join-Path $target "skills\$($d.Name)")
  Copy-One (Join-Path $d.FullName 'SKILL.md') (Join-Path $target "skills\$($d.Name)\SKILL.md")
  Write-Output "  + $($d.Name)"
}

# --- agents ------------------------------------------------------------------
Write-Output "agents/"
Ensure-Dir (Join-Path $target 'agents')
foreach ($f in Get-ChildItem (Join-Path $src 'agents') -Filter *.md) {
  Copy-One $f.FullName (Join-Path $target "agents\$($f.Name)")
  Write-Output "  + $($f.BaseName)"
}

# In project scope the hooks live inside the repo, so reference them through
# $CLAUDE_PROJECT_DIR - that resolves correctly for everyone who clones it.
if ($Project) { $prefix = '$CLAUDE_PROJECT_DIR/.claude/hooks' } else { $prefix = '~/.claude/hooks' }

Write-Output ""
Write-Output "Done. Two things left, both manual:"
Write-Output ""
Write-Output "1. Wire up the hooks. Merge this into $target\settings.json"
Write-Output "   (see settings.example.json for a copy you can paste):"
Write-Output ""
Write-Output @"
   {
     "hooks": {
       "PreToolUse": [
         { "matcher": "Bash",
           "hooks": [{ "type": "command", "command": "$prefix/guard-bash.sh" }] },
         { "matcher": "Write|Edit",
           "hooks": [{ "type": "command", "command": "$prefix/guard-write.sh" }] }
       ]
     }
   }
"@
Write-Output ""
Write-Output "2. Restart Claude Code, then verify:"
Write-Output "     /skills                       -> lists debug-systematically, write-tests"
Write-Output "     /agents                       -> lists code-reviewer"
Write-Output "     ask it to run:  git reset --hard HEAD~1"
Write-Output "                                   -> must be refused by guard-bash"
Write-Output ""
Write-Output "Prove the hooks work without involving Claude at all:  node tests\test-guards.mjs"

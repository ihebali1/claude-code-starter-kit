// Proves install.sh actually puts the files where it says it does.
// Run: node tests/test-install.mjs
//
// Installs into a throwaway HOME, then asserts every artifact landed, the hooks
// are executable, and a second run backs up rather than silently clobbering.
// Requires mkdir/cp/chmod on PATH — i.e. any real shell.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');
const BASH = process.env.BASH_PATH || 'bash';

const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'cck-install-'));
const claude = path.join(tmpHome, '.claude');

const failures = [];
let pass = 0;

function check(name, cond) {
  if (cond) {
    pass++;
    console.log(`  ok    ${name}`);
  } else {
    failures.push(name);
    console.log(`  FAIL  ${name}`);
  }
}

function install() {
  const r = spawnSync(BASH, [path.join(root, 'install.sh')], {
    encoding: 'utf8',
    cwd: root,
    env: { ...process.env, HOME: tmpHome },
  });
  if (r.error) {
    console.error(`\nCannot run ${BASH}: ${r.error.message}`);
    process.exit(1);
  }
  return r;
}

console.log(`--- install.sh into ${tmpHome} ---`);
const first = install();

// install.sh needs mkdir/cp/chmod. Some locked-down sandboxes expose bash but no
// external binaries at all; that is an unrunnable environment, not a failed test.
if (first.status !== 0 && /\b(mkdir|cp|chmod): command not found/.test(first.stderr || '')) {
  console.log('  SKIP  this environment has bash but no mkdir/cp/chmod — cannot exercise install.sh');
  console.log(`        ${(first.stderr || '').trim().split('\n')[0]}`);
  fs.rmSync(tmpHome, { recursive: true, force: true });
  process.exit(0);
}

check('exits 0', first.status === 0);
if (first.status !== 0) console.log(first.stderr || first.stdout);

check('hooks/guard-bash.sh installed', fs.existsSync(path.join(claude, 'hooks/guard-bash.sh')));
check('hooks/guard-write.sh installed', fs.existsSync(path.join(claude, 'hooks/guard-write.sh')));
check('skills/debug-systematically/SKILL.md installed', fs.existsSync(path.join(claude, 'skills/debug-systematically/SKILL.md')));
check('skills/write-tests/SKILL.md installed', fs.existsSync(path.join(claude, 'skills/write-tests/SKILL.md')));
check('agents/code-reviewer.md installed', fs.existsSync(path.join(claude, 'agents/code-reviewer.md')));

// If the copy did not happen, the remaining assertions cannot say anything useful.
// Report what we have and stop, rather than crashing on a missing file.
if (!fs.existsSync(path.join(claude, 'hooks/guard-bash.sh'))) {
  console.log('\nguard-bash.sh was not installed; skipping the remaining checks.');
  console.log(first.stderr || first.stdout);
  console.log(`\n=== ${pass} passed, ${failures.length} failed ===`);
  process.exit(1);
}

// Content must survive the copy intact, not arrive truncated.
const installed = fs.readFileSync(path.join(claude, 'hooks/guard-bash.sh'), 'utf8');
const source = fs.readFileSync(path.join(root, 'hooks/guard-bash.sh'), 'utf8');
check('guard-bash.sh copied byte-for-byte', installed === source);

// An installed hook that is not executable never runs, and Claude Code reports
// nothing — the session just silently has no guard.
if (process.platform === 'win32') {
  console.log('  skip  executable bit (not meaningful on Windows)');
} else {
  const mode = fs.statSync(path.join(claude, 'hooks/guard-bash.sh')).mode;
  check('guard-bash.sh is executable', (mode & 0o111) !== 0);
}

// The installed copy must still pass the guard tests from its new location.
const guardRun = spawnSync(BASH, [path.join(claude, 'hooks/guard-bash.sh')], {
  input: JSON.stringify({ tool_name: 'Bash', tool_input: { command: 'git reset --hard HEAD~1' } }),
  encoding: 'utf8',
});
check('installed guard-bash.sh still blocks a hard reset', guardRun.status === 2);

console.log('--- second run must not clobber silently ---');
fs.writeFileSync(path.join(claude, 'hooks/guard-bash.sh'), '#!/usr/bin/env bash\n# user edit\nexit 0\n');
const second = install();
check('second run exits 0', second.status === 0);
check('previous version backed up to .bak', fs.existsSync(path.join(claude, 'hooks/guard-bash.sh.bak')));
check('backup holds the user edit', fs.readFileSync(path.join(claude, 'hooks/guard-bash.sh.bak'), 'utf8').includes('user edit'));

fs.rmSync(tmpHome, { recursive: true, force: true });

console.log(`\n=== ${pass} passed, ${failures.length} failed ===`);
if (failures.length) {
  console.log(failures.join('\n'));
  process.exit(1);
}

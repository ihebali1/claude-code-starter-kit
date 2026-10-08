// Proves the plugin packaging is valid and that it did not displace the
// copy-based installers.
// Run: node tests/test-plugin.mjs
//
// There are now two ways to install this kit: `claude plugin install`, which
// reads .claude-plugin/, and install.sh / install.ps1, which copy files into
// ~/.claude. Both read the SAME hooks/, skills/ and agents/ directories. That is
// the whole reason nothing had to move, and it is the thing most likely to be
// broken by a future edit — so assert it rather than trust it.
//
// This file deliberately duplicates a few rules that `claude plugin validate`
// also enforces. That command is the authority, but it is not installed on most
// contributors' machines, and the directory's portal applies extra rules that it
// does not check at all. The ones repeated here are the ones that silently cost
// you a listing.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');

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

function readJson(rel) {
  try {
    return JSON.parse(fs.readFileSync(path.join(root, rel), 'utf8'));
  } catch (e) {
    failures.push(`${rel}: ${e.message}`);
    console.log(`  FAIL  ${rel} is not readable JSON — ${e.message}`);
    return null;
  }
}

console.log('--- manifests parse ---');
const marketplace = readJson('.claude-plugin/marketplace.json');
const plugin = readJson('.claude-plugin/plugin.json');
const hooks = readJson('hooks/hooks.json');
if (!marketplace || !plugin || !hooks) {
  console.log(`\n=== ${pass} passed, ${failures.length} failed ===`);
  process.exit(1);
}

console.log('--- marketplace entry ---');
check('marketplace has a name', typeof marketplace.name === 'string' && marketplace.name.length > 0);
check('marketplace has owner.name', !!marketplace.owner && typeof marketplace.owner.name === 'string' && marketplace.owner.name.length > 0);
check('marketplace has exactly one plugin entry', Array.isArray(marketplace.plugins) && marketplace.plugins.length === 1);

const entry = (marketplace.plugins || [])[0] || {};
check('entry has a description', typeof entry.description === 'string' && entry.description.length > 0);

// The docs name this as the single most common cause of a failed install: users
// type the ENTRY name, but components are namespaced under the MANIFEST name, so
// a mismatch installs something whose skills all appear under a different prefix.
check('entry name === plugin.json name', entry.name === plugin.name);

// "." means the marketplace root is itself the plugin. Keeping the plugin at the
// repository root is not cosmetic: the directory's pre-submission checks apply
// several extra rules — about shell variables and command substitution inside
// hook scripts — only when the plugin folder is a SUBfolder of the repository.
// guard-bash.sh uses both, so moving it into a subdirectory would trade a clean
// report for a reviewer hold.
check('entry source is the marketplace root (".")', entry.source === '.');

// The entry must not re-declare components. With the default "strict": true they
// are APPENDED to plugin.json rather than replacing it, which silently doubles
// every skill and agent in the inventory.
for (const key of ['commands', 'agents', 'skills', 'hooks', 'outputStyles', 'themes']) {
  check(`entry does not re-declare "${key}"`, !(key in entry));
}

// plugin.json wins on version, and the validator warns when both are set.
check('entry does not set version (plugin.json owns it)', !('version' in entry));

console.log('--- plugin name rules ---');
const name = plugin.name;
// Anthropic's directory: lowercase letters, digits and hyphens, starting and
// ending alphanumeric, max 64 chars. Anything else is a warning at best.
check('name is lowercase alphanumeric + hyphens', /^[a-z0-9][a-z0-9-]*[a-z0-9]$/.test(name));
check('name is at most 64 characters', name.length <= 64);
// `claude plugin validate` hard-FAILS a name that passes as one of Anthropic's
// own. This is why the plugin is not called "claude-code-starter-kit".
check('name does not use a reserved vendor prefix', !/^(claude-|anthropic-|anthropics-|cc-plugin-)/.test(name));
check('name is not a reserved vendor word', !['claude', 'anthropic', 'anthropics', 'claude-code', 'claude-mods'].includes(name));

console.log('--- plugin metadata the directory requires ---');
check('version is set', typeof plugin.version === 'string' && plugin.version.length > 0);
check('description is set', typeof plugin.description === 'string' && plugin.description.length > 0);
check('author.name is set', !!plugin.author && typeof plugin.author.name === 'string' && plugin.author.name.length > 0);
check('license is set', typeof plugin.license === 'string' && plugin.license.length > 0);

// People who install the plugin receive the PLUGIN FOLDER only. The directory
// blocks a listing whose plugin folder has no README of at least 40 words or no
// license — so both have to be in this directory, not just somewhere in the repo.
check('LICENSE is in the plugin folder', fs.existsSync(path.join(root, 'LICENSE')));
const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8');
const prose = readme.replace(/```[\s\S]*?```/g, ' '); // words inside code fences do not count
check('README has more than 40 words outside code blocks', prose.split(/\s+/).filter(Boolean).length > 40);

console.log('--- hooks are wired to the files that exist ---');
const hookDirFiles = fs.readdirSync(path.join(root, 'hooks')).filter((f) => f.endsWith('.sh')).sort();
const commands = [];
for (const matchers of Object.values(hooks.hooks || {})) {
  for (const m of matchers) for (const h of m.hooks || []) commands.push(h.command);
}
check('hooks.json wraps its event map in a top-level "hooks" key', !!hooks.hooks);
check('every hook script in hooks/ is referenced by hooks.json',
  hookDirFiles.every((f) => commands.some((c) => c.endsWith(`/hooks/${f}`))));
check('every command hooks.json references exists on disk',
  commands.every((c) => fs.existsSync(path.join(root, c.replace('"${CLAUDE_PLUGIN_ROOT}"/', '')))));
// An unquoted ${CLAUDE_PLUGIN_ROOT} breaks on any install path containing a
// space, which on Windows is the common case.
check('every command quotes ${CLAUDE_PLUGIN_ROOT}',
  commands.every((c) => c.startsWith('"${CLAUDE_PLUGIN_ROOT}"/')));
// The checklist warns on this: Claude Code loads hooks/hooks.json automatically,
// so naming it again in plugin.json is a redundant declaration.
check('plugin.json does not re-declare hooks/hooks.json', !('hooks' in plugin));

console.log('--- the copy installers still own the same directories ---');
// This is the no-regression claim. The plugin reads these three directories
// through Claude Code's standard layout; install.sh and install.ps1 read the
// very same ones. Nothing moved, so nothing had to be symlinked or wrapped.
for (const dir of ['hooks', 'skills', 'agents']) {
  check(`${dir}/ is at the repository root`, fs.statSync(path.join(root, dir)).isDirectory());
}
const sh = fs.readFileSync(path.join(root, 'install.sh'), 'utf8');
const ps1 = fs.readFileSync(path.join(root, 'install.ps1'), 'utf8');
check('install.sh still copies from hooks/, skills/ and agents/',
  sh.includes('/hooks/*.sh') && sh.includes('/skills/*/') && sh.includes('/agents/*.md'));
check('install.ps1 still copies from hooks/, skills/ and agents/',
  ps1.includes("'hooks'") && ps1.includes("'skills'") && ps1.includes("'agents'"));

// hooks/hooks.json is new, and it lives inside a directory install.sh iterates.
// Both installers glob *.sh, so they ignore it. If someone ever widens that glob
// to *, this test fails and tells them why: hooks.json is plugin configuration,
// not a hook, and copying it into ~/.claude/hooks/ does nothing.
check('install.sh copies only *.sh out of hooks/', /hooks\/\*\.sh/.test(sh));
check('install.ps1 copies only *.sh out of hooks/', /-Filter\s+\*\.sh/.test(ps1));

// The plugin folder must not contain OS junk; the directory blocks on these.
const junk = ['.DS_Store', 'Thumbs.db', 'desktop.ini', '__MACOSX'];
check('no macOS/Windows system files in the plugin folder',
  !junk.some((j) => fs.existsSync(path.join(root, j))));

console.log(`\n=== ${pass} passed, ${failures.length} failed ===`);
if (failures.length) {
  console.log(failures.join('\n'));
  process.exit(1);
}

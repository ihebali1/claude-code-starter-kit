// Validates the skill and subagent files against Claude Code's frontmatter rules.
// Run: node tests/validate-frontmatter.mjs
//
// A skill with broken frontmatter does not error — it silently fails to load and
// never appears in /skills. That failure mode is why this check exists.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');

// Subagent frontmatter is camelCase; skill frontmatter is a much smaller set.
// Mixing the two conventions is the most common authoring mistake.
const AGENT_KEYS = new Set([
  'name', 'description', 'tools', 'disallowedTools', 'model', 'permissionMode',
  'maxTurns', 'skills', 'mcpServers', 'hooks', 'memory', 'background',
  'omitClaudeMd', 'effort', 'isolation', 'color', 'initialPrompt', 'experimental',
]);
const SKILL_KEYS = new Set(['name', 'description', 'allowed-tools', 'license']);

const MODELS = new Set(['sonnet', 'opus', 'haiku', 'fable', 'inherit']);
const EFFORT = new Set(['low', 'medium', 'high', 'xhigh', 'max']);
const PERM = new Set(['default', 'acceptEdits', 'auto', 'dontAsk', 'bypassPermissions', 'plan', 'manual']);
const COLOR = new Set(['red', 'blue', 'green', 'yellow', 'purple', 'orange', 'pink', 'cyan']);

const errors = [];
const warnings = [];

function parse(file, id) {
  const raw = fs.readFileSync(file, 'utf8');
  if (!raw.startsWith('---\n')) {
    errors.push(`${id}: frontmatter must start on line 1 with '---'`);
    return null;
  }
  const end = raw.indexOf('\n---', 4);
  if (end === -1) {
    errors.push(`${id}: frontmatter never closes`);
    return null;
  }
  const fm = {};
  for (const line of raw.slice(4, end).split('\n')) {
    const m = line.match(/^([A-Za-z_][\w-]*):\s*(.*)$/);
    if (!m) {
      if (line.trim()) errors.push(`${id}: unparsed frontmatter line: ${line}`);
      continue;
    }
    fm[m[1]] = m[2].trim();
  }
  return { fm, body: raw.slice(end + 4).trim() };
}

function checkCommon(fm, body, id, expectedName, allowed, kind) {
  for (const k of Object.keys(fm)) {
    if (!allowed.has(k)) errors.push(`${id}: unknown ${kind} frontmatter key "${k}"`);
  }
  if (!fm.name) errors.push(`${id}: missing name`);
  if (!fm.description) errors.push(`${id}: missing description`);
  if (fm.name && fm.name !== expectedName) {
    errors.push(`${id}: name "${fm.name}" does not match "${expectedName}"`);
  }
  if (fm.name && !/^[a-z0-9][a-z0-9-]*$/.test(fm.name)) {
    errors.push(`${id}: name must be lowercase letters, digits and hyphens`);
  }
  // Claude matches on the description to decide when to use the thing, so a
  // one-word title here means it never gets picked automatically.
  if (fm.description && fm.description.length < 30) {
    warnings.push(`${id}: description is short (${fm.description.length} chars) — it is the trigger text`);
  }
  if (fm.description && fm.description.length > 1200) {
    warnings.push(`${id}: description is long; it is truncated around 1536 chars`);
  }
  if (body.length < 200) warnings.push(`${id}: body is very short (${body.length} chars)`);
}

let nSkills = 0;
const skillsDir = path.join(root, 'skills');
for (const dir of fs.readdirSync(skillsDir)) {
  const file = path.join(skillsDir, dir, 'SKILL.md');
  const id = `skills/${dir}/SKILL.md`;
  if (!fs.existsSync(file)) {
    errors.push(`skills/${dir}: must contain a file named exactly SKILL.md`);
    continue;
  }
  nSkills++;
  const parsed = parse(file, id);
  if (parsed) checkCommon(parsed.fm, parsed.body, id, dir, SKILL_KEYS, 'skill');
}

let nAgents = 0;
const agentsDir = path.join(root, 'agents');
for (const f of fs.readdirSync(agentsDir).filter((x) => x.endsWith('.md'))) {
  const id = `agents/${f}`;
  nAgents++;
  const parsed = parse(path.join(agentsDir, f), id);
  if (!parsed) continue;
  const { fm, body } = parsed;
  checkCommon(fm, body, id, f.replace(/\.md$/, ''), AGENT_KEYS, 'agent');
  if (fm.model && !MODELS.has(fm.model) && !/^claude-/.test(fm.model)) {
    errors.push(`${id}: model "${fm.model}" is not a known alias or model id`);
  }
  if (fm.effort && !EFFORT.has(fm.effort)) errors.push(`${id}: bad effort "${fm.effort}"`);
  if (fm.permissionMode && !PERM.has(fm.permissionMode)) errors.push(`${id}: bad permissionMode "${fm.permissionMode}"`);
  if (fm.color && !COLOR.has(fm.color)) errors.push(`${id}: bad color "${fm.color}"`);
  if (fm.maxTurns && !/^\d+$/.test(String(fm.maxTurns))) errors.push(`${id}: maxTurns must be a positive integer`);
}

// The hooks are useless if they are not executable text files with a shebang.
let nHooks = 0;
const hooksDir = path.join(root, 'hooks');
for (const f of fs.readdirSync(hooksDir).filter((x) => x.endsWith('.sh'))) {
  nHooks++;
  const raw = fs.readFileSync(path.join(hooksDir, f), 'utf8');
  // A UTF-8 BOM sits in front of the shebang and bash reports
  // "#!/usr/bin/env: No such file or directory" — a confusing way to find out
  // your guard is not running. Editors on Windows add one silently.
  if (raw.charCodeAt(0) === 0xfeff) errors.push(`hooks/${f}: starts with a UTF-8 BOM — bash cannot read the shebang`);
  else if (!raw.startsWith('#!')) errors.push(`hooks/${f}: missing shebang on line 1`);
  // CRLF line endings make a bash script fail with a confusing "\r: command not
  // found". .gitattributes pins these to LF; this check proves it held.
  if (raw.includes('\r\n')) errors.push(`hooks/${f}: has CRLF line endings — bash will not run it`);
}

console.log(`${nSkills} skills, ${nAgents} agents, ${nHooks} hooks checked`);
if (warnings.length) {
  console.log('\nWarnings:');
  warnings.forEach((w) => console.log('  ! ' + w));
}
if (errors.length) {
  console.log('\nErrors:');
  errors.forEach((e) => console.log('  x ' + e));
  process.exit(1);
}
console.log('\nAll valid.');

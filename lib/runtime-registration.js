'use strict';

const fs = require('fs');
const path = require('path');

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) { return fallback; }
}
function readUserJson(file, fallback) {
  if (!fs.existsSync(file)) return fallback;
  let value;
  try { value = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) { throw new Error(`invalid user JSON: ${file}`); }
  if (!value || Array.isArray(value) || typeof value !== 'object') throw new Error(`user JSON must be an object: ${file}`);
  return value;
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(temp, `${JSON.stringify(value, null, 2)}\n`);
  fs.renameSync(temp, file);
}
function writeText(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(temp, value);
  fs.renameSync(temp, file);
}

function addUnique(list, value) {
  if (!list.some(item => JSON.stringify(item) === JSON.stringify(value))) list.push(value);
}

function filterClaudeHooks(entries, removeHook) {
  return entries.flatMap(entry => {
    if (!entry || !Array.isArray(entry.hooks)) return [entry];
    const hooks = entry.hooks.filter(hook => !removeHook(hook));
    return hooks.length ? [{ ...entry, hooks }] : [];
  });
}

const CODEX_MANAGED_BLOCKS = [
  ['# >>> BA-kit managed agents >>>', '# <<< BA-kit managed agents <<<'],
  ['# BEGIN BA-kit managed agents', '# END BA-kit managed agents'],
];

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function stripManagedCodexBlocks(config) {
  let cleaned = config;
  for (const [begin, end] of CODEX_MANAGED_BLOCKS) {
    cleaned = cleaned.replace(
      new RegExp(`\\n?${escapeRegex(begin)}[\\s\\S]*?${escapeRegex(end)}\\n?`, 'gi'),
      '\n',
    );
  }
  return cleaned.replace(/^\n+/, '');
}

function hasManagedCodexBlock(config) {
  return CODEX_MANAGED_BLOCKS.some(([begin, end]) =>
    new RegExp(`${escapeRegex(begin)}[\\s\\S]*?${escapeRegex(end)}`, 'i').test(config)
  );
}

function registerClaude(root, descriptor) {
  if (!descriptor || typeof descriptor !== 'object') throw new Error('verified Claude registration descriptor required');
  const settingsFile = path.join(root, 'settings.json');
  const settings = readUserJson(settingsFile, {});
  if (settings.hooks != null && (Array.isArray(settings.hooks) || typeof settings.hooks !== 'object')) throw new Error(`user hooks must be an object: ${settingsFile}`);
  settings.hooks = settings.hooks || {};
  for (const [event, files] of Object.entries(descriptor.managed_events || {})) {
    settings.hooks[event] = Array.isArray(settings.hooks[event]) ? settings.hooks[event] : [];
    settings.hooks[event] = filterClaudeHooks(settings.hooks[event], hook =>
      files.some(file => String(hook && hook.command || '').includes(path.join(root, 'hooks', file)))
    );
    for (const file of files) {
      const command = `bash "${path.join(root, 'hooks', file)}"`;
      addUnique(settings.hooks[event], {
        matcher: '',
        hooks: [{ type: 'command', command, ba_kit_managed: true }],
      });
    }
  }
  writeJson(settingsFile, settings);
  return [settingsFile];
}

function registerCodex(root, agentRegistration, hookRegistration, allowLegacy = false) {
  if (!agentRegistration || !hookRegistration) throw new Error('verified Codex registration descriptors required');
  const configFile = path.join(root, 'config.toml');
  const registration = agentRegistration;
  const begin = '# >>> BA-kit managed agents >>>';
  const end = '# <<< BA-kit managed agents <<<';
  let config = fs.existsSync(configFile) ? fs.readFileSync(configFile, 'utf8') : '';
  config = stripManagedCodexBlocks(config);
  const managedNames = [...(registration.canonical_agents || []), ...Object.keys(registration.compatibility_aliases || {})];
  for (const name of managedNames) {
    const section = new RegExp(`(^|\\n)\\[agents\\.${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\][\\s\\S]*?(?=\\n\\[|$)`, 'g');
    if (allowLegacy) config = config.replace(section, '\n');
    else if (section.test(config)) throw new Error(`user-owned Codex agent registration conflicts with ${name}`);
  }
  const lines = [begin];
  for (const name of registration.canonical_agents || []) {
    lines.push(`[agents.${name}]`);
    lines.push(`description = "BA-kit managed ${name}"`);
    lines.push(`config_file = "agents/${name}.toml"`);
    lines.push('');
  }
  lines.push(end, '');
  fs.mkdirSync(path.dirname(configFile), { recursive: true });
  writeText(configFile, `${config}${config && !config.endsWith('\n') ? '\n' : ''}${lines.join('\n')}`);

  const hooksFile = path.join(root, 'hooks.json');
  const hooks = readUserJson(hooksFile, {});
  const descriptor = hookRegistration;
  if (hooks.hooks != null && (Array.isArray(hooks.hooks) || typeof hooks.hooks !== 'object')) throw new Error(`user hooks must be an object: ${hooksFile}`);
  hooks.hooks = hooks.hooks || {};
  for (const [event, entries] of Object.entries(descriptor.hooks || {})) {
    hooks.hooks[event] = Array.isArray(hooks.hooks[event]) ? hooks.hooks[event] : [];
    const commands = entries.map(entry => String(entry.command || '').replace('{hooks_root}', path.join(root, 'ba-kit', 'hooks')));
    hooks.hooks[event] = hooks.hooks[event].filter(entry => !commands.some(name => String(entry && entry.command || '') === name));
    for (const entry of entries) {
      const copy = { ...entry, ba_kit_managed: true };
      if (copy.command) copy.command = copy.command.replace('{hooks_root}', path.join(root, 'ba-kit', 'hooks'));
      addUnique(hooks.hooks[event], copy);
    }
  }
  writeJson(hooksFile, hooks);
  return [configFile, hooksFile];
}

function unregisterClaude(root) {
  const file = path.join(root, 'settings.json');
  const settings = readUserJson(file, null);
  if (!settings || !settings.hooks) return [];
  if (Array.isArray(settings.hooks) || typeof settings.hooks !== 'object') throw new Error(`user hooks must be an object: ${file}`);
  for (const [event, entries] of Object.entries(settings.hooks)) {
    if (!Array.isArray(entries)) continue;
    settings.hooks[event] = filterClaudeHooks(entries, hook => hook && (
      hook.ba_kit_managed === true ||
      (String(hook.command || '').includes(path.join(root, 'hooks')) && /guardrail-|postwrite-guardrail/.test(String(hook.command || '')))
    ));
  }
  writeJson(file, settings);
  return [file];
}

function unregisterCodex(root) {
  const configFile = path.join(root, 'config.toml');
  if (fs.existsSync(configFile)) {
    const config = stripManagedCodexBlocks(fs.readFileSync(configFile, 'utf8'));
    writeText(configFile, config);
  }
  const hooksFile = path.join(root, 'hooks.json');
  const hooks = readUserJson(hooksFile, null);
  if (hooks && hooks.hooks) {
    if (Array.isArray(hooks.hooks) || typeof hooks.hooks !== 'object') throw new Error(`user hooks must be an object: ${hooksFile}`);
    for (const [event, entries] of Object.entries(hooks.hooks)) {
      if (Array.isArray(entries)) hooks.hooks[event] = entries.filter(entry => !entry || (entry.ba_kit_managed !== true && !(String(entry.command || '').includes(path.join(root, 'ba-kit', 'hooks')) && /guardrail-|postwrite-guardrail/.test(String(entry.command || '')))));
    }
    writeJson(hooksFile, hooks);
  }
  return [configFile, hooksFile];
}

function registrationHealthy(runtime, root) {
  if (runtime === 'claude') {
    const settings = readJson(path.join(root, 'settings.json'), {});
    const descriptor = readJson(path.join(root, 'hooks', 'registration.json'), { managed_events: {} });
    return Object.entries(descriptor.managed_events || {}).every(([event, files]) => files.every(file =>
      (settings.hooks[event] || []).some(entry => (entry.hooks || []).some(h => h.ba_kit_managed === true && String(h.command || '').includes(path.join(root, 'hooks', file))))
    ));
  }
  if (runtime === 'codex') {
    const configFile = path.join(root, 'config.toml');
    const hooks = readJson(path.join(root, 'hooks.json'), {});
    const agents = readJson(path.join(root, 'agents', 'registration.json'), { canonical_agents: [] });
    const config = fs.existsSync(configFile) ? fs.readFileSync(configFile, 'utf8') : '';
    const hasAgents = hasManagedCodexBlock(config) && (agents.canonical_agents || []).every(name => config.includes(`[agents.${name}]`));
    const descriptor = readJson(path.join(root, 'ba-kit', 'hooks', 'registration.json'), { hooks: {} });
    const hasHooks = Object.entries(descriptor.hooks || {}).every(([event, entries]) => entries.every(expected => {
      const command = String(expected.command || '').replace('{hooks_root}', path.join(root, 'ba-kit', 'hooks'));
      return (hooks.hooks[event] || []).some(entry => entry.ba_kit_managed === true && entry.command === command);
    }));
    return hasAgents && hasHooks;
  }
  return fs.existsSync(path.join(root, 'knowledge', 'ba-kit-workflow', 'metadata.json'));
}

module.exports = { readJson, writeJson, registerClaude, registerCodex, unregisterClaude, unregisterCodex, registrationHealthy };

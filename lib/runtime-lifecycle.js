'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const {
  readJson, writeJson, registerClaude, registerCodex,
  unregisterClaude, unregisterCodex, registrationHealthy,
} = require('./runtime-registration');

const BARRIER = 'RECOVERY_REQUIRED.json';
const INTERACTION_LANGUAGES = new Set(['vi', 'en']);

function sha256(file) { return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'); }
function exists(file) { try { fs.accessSync(file); return true; } catch (_) { return false; } }
function ensureDir(dir) { fs.mkdirSync(dir, { recursive: true }); }
function rm(file) { fs.rmSync(file, { recursive: true, force: true }); }
function within(root, file) {
  const relative = path.relative(path.resolve(root), path.resolve(file));
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}
function securelyWithin(root, file) {
  if (!exists(root)) return within(root, file);
  const rootPath = exists(root) ? fs.realpathSync(root) : path.resolve(root);
  let cursor = path.resolve(file);
  while (!exists(cursor) && path.dirname(cursor) !== cursor) cursor = path.dirname(cursor);
  const cursorPath = exists(cursor) ? fs.realpathSync(cursor) : cursor;
  return within(rootPath, cursorPath);
}
function assertManagedDestination(home, runtime, file) {
  if (!supportedRuntimeRoots(runtime, home).some(root => within(root, file) && securelyWithin(root, file))) throw new Error(`state destination escapes runtime target: ${file}`);
}
function atomicCopy(source, dest) {
  ensureDir(path.dirname(dest));
  const temp = `${dest}.tmp-${process.pid}`;
  fs.copyFileSync(source, temp);
  fs.renameSync(temp, dest);
}
function atomicWriteText(dest, value) {
  ensureDir(path.dirname(dest));
  const temp = `${dest}.tmp-${process.pid}`;
  fs.writeFileSync(temp, value);
  fs.renameSync(temp, dest);
}
function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i].startsWith('--')) out[argv[i].slice(2)] = argv[++i]; else out._.push(argv[i]);
  }
  return out;
}
function runtimeTargets(runtime, home) {
  if (runtime === 'claude') return [path.join(home, '.claude')];
  if (runtime === 'codex') return [path.join(home, '.codex')];
  const base = path.join(home, '.gemini');
  const canonical = path.join(base, 'antigravity');
  const detected = ['antigravity-cli', 'antigravity-ide']
    .map(name => path.join(base, name)).filter(exists);
  return [canonical, ...detected];
}
function supportedRuntimeRoots(runtime, home) {
  if (runtime === 'agy') return ['antigravity', 'antigravity-cli', 'antigravity-ide'].map(name => path.join(home, '.gemini', name));
  return runtimeTargets(runtime, home);
}

function loadContext(args) {
  const extract = path.resolve(args.extract);
  const manifest = readJson(path.join(extract, 'manifest.json'), null);
  const release = readJson(path.join(extract, 'release-manifest.json'), null);
  if (!manifest || !release) throw new Error('archive manifests are missing');
  const interactionLanguage = args.interaction_language || 'vi';
  if (!INTERACTION_LANGUAGES.has(interactionLanguage)) throw new Error(`invalid interaction language: ${interactionLanguage}`);
  return { extract, manifest, release, home: path.resolve(args.home || process.env.HOME), interactionLanguage };
}
function validV3State(state, runtime) {
  return Boolean(state && state.schema_version === 3 && state.runtime_key === runtime
    && Number.isInteger(state.payload_schema) && typeof state.product_id === 'string' && state.product_id
    && typeof state.product_name === 'string' && state.product_name && typeof state.profile === 'string'
    && typeof state.version === 'string' && typeof state.status === 'string'
    && Array.isArray(state.targets) && state.targets.length > 0
    && (!state.preferences || (INTERACTION_LANGUAGES.has(state.preferences.interaction_language)
      && Array.isArray(state.preferences.projections)))
    && state.files && !Array.isArray(state.files) && typeof state.files === 'object');
}

function preferenceFile(target) { return path.join(target, 'ba-kit', 'preferences.json'); }

function writeRuntimePreference(ctx) {
  const file = preferenceFile(ctx.target);
  assertManagedDestination(ctx.home, ctx.runtime, file);
  writeJson(file, {
    schema_version: 1,
    interaction_language: ctx.interactionLanguage,
    updated_at: new Date().toISOString(),
  });
  return file;
}

function componentDestination(runtime, key, target) {
  const root = target;
  if (key === 'skills_root') return path.join(root, 'skills');
  if (key === 'agents_root') return path.join(root, 'agents');
  if (key === 'rules_root') return path.join(root, 'rules');
  if (key === 'templates_root') return runtime === 'agy' ? path.join(root, 'ba-kit', 'templates') : path.join(root, 'templates');
  if (key === 'hooks_root') return runtime === 'claude' ? path.join(root, 'hooks') : path.join(root, 'ba-kit', 'hooks');
  if (key === 'core_root') return runtime === 'codex' ? path.join(root, 'ba-kit') : path.join(root, 'ba-kit', 'core');
  if (key === 'guardrails_root') return path.join(root, 'ba-kit', 'scripts');
  if (key === 'knowledge_root') return path.join(root, 'knowledge', 'ba-kit-workflow');
  if (key === 'shared_root') return path.join(root, 'ba-kit');
  throw new Error(`unsupported destination key: ${key}`);
}

function componentPlan(ctx, runtime) {
  const components = Array.isArray(ctx.manifest.runtime_components) ? ctx.manifest.runtime_components : [];
  if (ctx.profile === 'solo-basic' || components.length === 0) {
    const specs = [
      ['.claude/skills/', path.join(ctx.target, 'skills'), 'legacy-skills'],
      ['.claude/templates/', path.join(ctx.target, 'templates'), 'legacy-templates'],
      ['ba-kit/core/', path.join(ctx.target, 'core'), 'legacy-core'],
    ];
    const ops = [];
    for (const [prefix, destination, component] of specs) for (const key of Object.keys(ctx.release).sort()) {
      const manifestPrefix = `./${prefix}`;
      if (!key.startsWith(manifestPrefix)) continue;
      const rel = key.slice(manifestPrefix.length);
      const source = path.join(ctx.extract, prefix, rel);
      if (!exists(source) || sha256(source) !== ctx.release[key]) throw new Error(`extracted source hash mismatch: ${key}`);
      ops.push({ key, component, source, dest: path.join(destination, rel), desired: ctx.release[key] });
    }
    return ops;
  }
  const componentRuntime = runtime === 'agy' ? 'antigravity' : runtime;
  const allowed = components.filter(c => c.runtime === componentRuntime || c.runtime === 'shared');
  const ops = [];
  for (const component of allowed) {
    const prefix = component.source_prefix.replace(/^\.\//, '');
    const manifestPrefix = `./${prefix}`;
    const destination = componentDestination(runtime, component.destination_key, ctx.target);
    for (const key of Object.keys(ctx.release).sort()) {
      if (!key.startsWith(manifestPrefix)) continue;
      const rel = key.slice(manifestPrefix.length);
      const source = path.join(ctx.extract, prefix, rel);
      if (!exists(source)) throw new Error(`archive manifest source missing: ${key}`);
      if (sha256(source) !== ctx.release[key]) throw new Error(`extracted source hash mismatch: ${key}`);
      ops.push({ key, component: component.id, source, dest: path.join(destination, rel), desired: ctx.release[key] });
    }
  }
  if (runtime === 'claude') {
    const cliKey = './.local/bin/ba-kit';
    if (ctx.release[cliKey]) {
      const source = path.join(ctx.extract, '.local/bin/ba-kit');
      if (!exists(source) || sha256(source) !== ctx.release[cliKey]) throw new Error(`extracted source hash mismatch: ${cliKey}`);
      ops.push({ key: cliKey, component: 'claude-cli', source, dest: path.join(ctx.target, 'ba-kit', 'ba-kit'), desired: ctx.release[cliKey] });
    }
  }
  const deduped = new Map();
  for (const op of ops) deduped.set(`${op.key}\0${op.dest}`, op);
  return [...deduped.values()];
}

function oldState(ctx) {
  const canonical = path.join(ctx.home, '.local', 'share', 'ba-kit', 'runtime-state', ctx.runtime, 'state.json');
  if (exists(canonical)) return readJson(canonical, {});
  const legacy = readJson(path.join(ctx.target, 'ba-kit', 'state.json'), {});
  if (legacy && legacy.schema_version) return legacy;
  const manifest = readJson(path.join(ctx.target, 'ba-kit', 'release-manifest.json'), {});
  return { schema_version: 1, files: Object.fromEntries(Object.entries(manifest).map(([key, hash]) => [key, { source_sha256: hash, status: 'managed' }])) };
}

function oldHash(state, key, dest) {
  let entry = state.files && state.files[key];
  if (!entry && Number(state.schema_version || 0) < 3) {
    const legacyKey = key.replace(/^\.\/\.(?:codex|antigravity)\/skills\//, './.claude/skills/');
    entry = state.files && state.files[legacyKey];
  }
  if (!entry) return '';
  if (entry.destinations && entry.destinations[dest]) {
    const destination = entry.destinations[dest];
    if (String(destination.status || '').startsWith('preserved-')) return '';
    return destination.managed_sha256 || destination.source_sha256 || destination.installed_sha256 || '';
  }
  return typeof entry === 'string' ? entry : (entry.source_sha256 || entry.installed_sha256 || '');
}

function legacyDestinations(ctx, key) {
  const mappings = [
    ['./.claude/skills/', path.join(ctx.target, 'skills')],
    ['./.claude/templates/', ctx.runtime === 'agy' ? path.join(ctx.target, 'ba-kit', 'templates') : path.join(ctx.target, 'templates')],
    ['./ba-kit/core/', ctx.runtime === 'codex' ? path.join(ctx.target, 'ba-kit') : path.join(ctx.target, 'core')],
  ];
  for (const [prefix, root] of mappings) if (key.startsWith(prefix)) {
    const rel = key.slice(prefix.length);
    if (!rel || rel.split('/').includes('..')) throw new Error(`unsafe legacy state key: ${key}`);
    return [path.join(root, rel)];
  }
  return [];
}

function snapshotPath(file, snapshot) {
  const record = { file, kind: 'absent' };
  if (fs.lstatSync(file, { throwIfNoEntry: false })) {
    const stat = fs.lstatSync(file);
    record.kind = stat.isSymbolicLink() ? 'symlink' : (stat.isDirectory() ? 'directory' : 'file');
    if (record.kind === 'symlink') record.target = fs.readlinkSync(file);
    else if (record.kind === 'file') { record.snapshot = path.join(snapshot, 'files', crypto.createHash('sha256').update(file).digest('hex')); ensureDir(path.dirname(record.snapshot)); fs.copyFileSync(file, record.snapshot); }
  }
  return record;
}
function restoreRecord(record, home, transactionRoot, allowedRoots = null) {
  if (!within(home, record.file) || !securelyWithin(home, record.file)) throw new Error(`transaction path escapes HOME: ${record.file}`);
  if (allowedRoots && !allowedRoots.some(root => within(root, record.file) && securelyWithin(root, record.file))) throw new Error(`transaction path escapes managed roots: ${record.file}`);
  if (record.snapshot && !within(transactionRoot, record.snapshot)) throw new Error(`transaction snapshot escapes journal: ${record.snapshot}`);
  if (record.kind === 'directory') return;
  rm(record.file);
  if (record.kind === 'file') { ensureDir(path.dirname(record.file)); fs.copyFileSync(record.snapshot, record.file); }
  if (record.kind === 'symlink') { ensureDir(path.dirname(record.file)); fs.symlinkSync(record.target, record.file); }
}

function recover(home) {
  const root = path.join(home, '.local', 'share', 'ba-kit', 'transactions');
  if (!exists(root)) return;
  const ids = fs.readdirSync(root).sort((a, b) => Number(a.startsWith('multi-')) - Number(b.startsWith('multi-')) || a.localeCompare(b));
  for (const id of ids) {
    const journalFile = path.join(root, id, 'journal.json');
    if (!exists(journalFile)) continue;
    const journal = readJson(journalFile, null);
    if (!journal || Array.isArray(journal) || typeof journal !== 'object') throw new Error(`invalid transaction journal: ${id}`);
    if (journal.status !== 'in-progress') continue;
    const runtimes = journal.runtimes || (journal.runtime ? [journal.runtime] : []);
    if (!runtimes.length) throw new Error(`transaction journal missing runtime scope: ${id}`);
    const allowedRoots = runtimes.flatMap(runtime => [
      ...supportedRuntimeRoots(runtime, home),
      path.join(home, '.local', 'share', 'ba-kit', 'runtime-state', runtime),
    ]);
    for (const record of [...(journal.records || [])].reverse()) restoreRecord(record, home, path.join(root, id), allowedRoots);
    rm(path.join(root, id));
  }
}

function writeBarrier(target, runtime) {
  const file = path.join(target, 'ba-kit', BARRIER);
  ensureDir(path.dirname(file));
  writeJson(file, { status: 'cli-upgrade-required', runtime, min_cli_version: '2.0.0', managed_by: 'ba-kit-cli-v3' });
}

function buildState(ctx, ops, statuses, retired) {
  const files = Number(ctx.previousState && ctx.previousState.schema_version) === 3
    ? JSON.parse(JSON.stringify(ctx.previousState.files || {})) : {};
  for (const op of ops) {
    const status = statuses.get(op.dest) || 'managed';
    const installed = exists(op.dest) ? sha256(op.dest) : op.desired;
    files[op.key] = files[op.key] || { source_sha256: op.desired, component_id: op.component, destinations: {} };
    files[op.key].destinations[op.dest] = { installed_sha256: installed, managed_sha256: status === 'managed' ? op.desired : '', status, registration_ownership: 'ba-kit' };
  }
  for (const item of retired) {
    files[item.key] = files[item.key] || { source_sha256: item.hash, component_id: item.component, destinations: {} };
    files[item.key].destinations[item.dest] = { installed_sha256: item.hash, status: item.status, registration_ownership: 'ba-kit' };
  }
  const priorTargets = (ctx.previousState && ctx.previousState.targets) || [];
  const priorRegistrations = (ctx.previousState && ctx.previousState.registrations) || [];
  const priorProjections = (ctx.previousState && ctx.previousState.preferences && ctx.previousState.preferences.projections) || [];
  return { schema_version: 3, runtime_key: ctx.runtime, payload_schema: ctx.manifest.runtime_payload_schema || 1, product_id: ctx.productId, product_name: ctx.productName, profile: ctx.profile, version: ctx.version, status: 'installed', targets: [...new Set([...priorTargets, ctx.target])], files, registrations: [...new Set([...priorRegistrations, ...(ctx.registrationPaths || [])])], preferences: { interaction_language: ctx.interactionLanguage, projections: [...new Set([...priorProjections, preferenceFile(ctx.target)])] }, updated_at: new Date().toISOString() };
}

function installOne(ctx) {
  const ops = componentPlan(ctx, ctx.runtime);
  for (const op of ops) assertManagedDestination(ctx.home, ctx.runtime, op.dest);
  const state = oldState(ctx);
  const retired = [];
  const planned = new Set(ops.map(op => op.dest));
  for (const [key, entry] of Object.entries(state.files || {})) {
    const recorded = Object.entries(entry.destinations || {});
    const destinations = recorded.length ? recorded : legacyDestinations(ctx, key).map(dest => [dest, { installed_sha256: typeof entry === 'string' ? entry : entry.source_sha256 }]);
    for (const [dest, data] of destinations) {
      assertManagedDestination(ctx.home, ctx.runtime, dest);
      if (ctx.runtime === 'agy' && !within(ctx.target, dest)) continue;
      if (planned.has(dest) || !exists(dest)) continue;
      if (String(data.status || '').startsWith('preserved-')) {
        retired.push({ key, dest, hash: sha256(dest), component: entry.component_id || 'retired', status: 'preserved-retired' });
        continue;
      }
      const hash = data.managed_sha256 || data.source_sha256 || entry.source_sha256;
      const current = sha256(dest);
      if (current === hash) { rm(dest); retired.push({ key, dest, hash, component: entry.component_id || 'retired', status: 'retired' }); }
      else retired.push({ key, dest, hash: current, component: entry.component_id || 'retired', status: 'preserved-retired' });
    }
  }
  const registrationFiles = ctx.profile !== 'standard' ? [] : (ctx.runtime === 'claude' ? [path.join(ctx.target, 'settings.json')] : (ctx.runtime === 'codex' ? [path.join(ctx.target, 'config.toml'), path.join(ctx.target, 'hooks.json')] : [path.join(ctx.target, 'knowledge', 'ba-kit-workflow', 'metadata.json')]));
  const stateFile = path.join(ctx.home, '.local', 'share', 'ba-kit', 'runtime-state', ctx.runtime, 'state.json');
  const projection = path.join(ctx.target, 'ba-kit', 'state.json');
  const barrier = path.join(ctx.target, 'ba-kit', BARRIER);
  const manifestFile = path.join(ctx.target, 'ba-kit', 'release-manifest.json');
  const preferencesFile = preferenceFile(ctx.target);
  const metadataFiles = ['VERSION', 'PRODUCT', 'PRODUCT_ID'].map(name => path.join(ctx.target, 'ba-kit', name));
  const coreLink = path.join(ctx.target, 'core');
  const transactionRoot = path.join(ctx.home, '.local', 'share', 'ba-kit', 'transactions', `${Date.now()}-${process.pid}-${crypto.randomBytes(4).toString('hex')}`);
  const snapshot = path.join(transactionRoot, 'snapshot');
  ensureDir(transactionRoot);
  const records = [];
  for (const file of [projection, barrier, manifestFile, ...metadataFiles]) assertManagedDestination(ctx.home, ctx.runtime, file);
  const paths = [...ops.map(op => op.dest), ...registrationFiles, stateFile, projection, barrier, manifestFile, preferencesFile, ...metadataFiles];
  if (ctx.runtime === 'claude' && (!exists(coreLink) || fs.lstatSync(coreLink).isSymbolicLink())) paths.push(coreLink);
  for (const file of [...new Set(paths)]) if (exists(file)) records.push(snapshotPath(file, snapshot)); else records.push({ file, kind: 'absent' });
  const journal = { schema_version: 1, status: 'in-progress', runtime: ctx.runtime, records };
  writeJson(path.join(transactionRoot, 'journal.json'), journal);
  const statuses = new Map();
  try {
    for (const op of ops) {
      if (exists(op.dest)) {
        const current = sha256(op.dest);
        if (current === op.desired) statuses.set(op.dest, 'managed');
        else if (oldHash(state, op.key, op.dest) && current === oldHash(state, op.key, op.dest)) { atomicCopy(op.source, op.dest); statuses.set(op.dest, 'managed'); }
        else statuses.set(op.dest, 'preserved-modified');
      } else { atomicCopy(op.source, op.dest); statuses.set(op.dest, 'managed'); }
    }
    for (const file of registrationFiles) ensureDir(path.dirname(file));
    if (ctx.profile === 'standard') {
      if (process.env.BA_KIT_TEST_FAIL_REGISTRATION === ctx.runtime) throw new Error(`forced registration failure: ${ctx.runtime}`);
      if (ctx.runtime === 'claude') {
        const descriptor = readJson(path.join(ctx.extract, '.claude', 'hooks', 'registration.json'), null);
        if (!descriptor) throw new Error('verified Claude registration descriptor missing');
        ctx.registrationPaths = registerClaude(ctx.target, descriptor);
      }
      if (ctx.runtime === 'codex') {
        const agents = readJson(path.join(ctx.extract, '.codex', 'agents', 'registration.json'), null);
        const hooks = readJson(path.join(ctx.extract, '.codex', 'hooks', 'registration.json'), null);
        if (!agents || !hooks) throw new Error('verified Codex registration descriptor missing');
        ctx.registrationPaths = registerCodex(ctx.target, agents, hooks, false);
      }
      if (ctx.runtime === 'agy') ctx.registrationPaths = [path.join(ctx.target, 'knowledge', 'ba-kit-workflow', 'metadata.json')];
    }
    writeRuntimePreference(ctx);
    const nextState = buildState(ctx, ops, statuses, retired);
    ensureDir(path.dirname(stateFile)); writeJson(stateFile, nextState);
    ensureDir(path.dirname(projection)); writeJson(projection, nextState); writeBarrier(ctx.target, ctx.runtime);
    ensureDir(path.join(ctx.target, 'ba-kit'));
    writeJson(manifestFile, ctx.release);
    atomicWriteText(metadataFiles[0], `${ctx.version}\n`);
    atomicWriteText(metadataFiles[1], `${ctx.productName}\n`);
    atomicWriteText(metadataFiles[2], `${ctx.productId}\n`);
    if (ctx.runtime === 'claude' && !exists(coreLink)) fs.symlinkSync(path.join(ctx.target, 'ba-kit', 'core'), coreLink);
    journal.status = 'committed'; writeJson(path.join(transactionRoot, 'journal.json'), journal); rm(transactionRoot);
  } catch (error) {
    for (const record of [...records].reverse()) restoreRecord(record, ctx.home, transactionRoot);
    rm(transactionRoot);
    throw error;
  }
}

function install(args) {
  const base = loadContext(args);
  recover(base.home);
  const runtimes = String(args.runtimes || '').split(',').filter(Boolean);
  const contexts = [];
  for (const runtime of runtimes) {
    let previousState = readJson(path.join(base.home, '.local', 'share', 'ba-kit', 'runtime-state', runtime, 'state.json'), {});
    for (const target of runtimeTargets(runtime, base.home)) {
      const productFile = path.join(target, 'ba-kit', 'PRODUCT');
      if (exists(productFile) && fs.readFileSync(productFile, 'utf8').trim() !== args.product_name) throw new Error(`different product already installed at ${target}`);
      const barrier = path.join(target, 'ba-kit', BARRIER);
      if (exists(barrier) && !validV3State(previousState, runtime)) throw new Error(`incomplete or invalid schema-v3 state requires recovery at ${target}`);
      contexts.push({ ...base, runtime, target, previousState, profile: args.profile || 'standard', productId: args.product_id, productName: args.product_name, version: args.version });
    }
  }
  const transactionRoot = path.join(base.home, '.local', 'share', 'ba-kit', 'transactions', `multi-${Date.now()}-${process.pid}-${crypto.randomBytes(4).toString('hex')}`);
  const snapshot = path.join(transactionRoot, 'snapshot');
  ensureDir(transactionRoot);
  const paths = [];
  for (const ctx of contexts) {
    paths.push(...componentPlan(ctx, ctx.runtime).map(op => op.dest));
    const existing = oldState(ctx);
    for (const [key, entry] of Object.entries(existing.files || {})) {
      const destinations = Object.keys(entry.destinations || {});
      const candidates = destinations.length ? destinations : legacyDestinations(ctx, key);
      for (const dest of candidates) { assertManagedDestination(ctx.home, ctx.runtime, dest); paths.push(dest); }
    }
    paths.push(
      path.join(ctx.home, '.local', 'share', 'ba-kit', 'runtime-state', ctx.runtime, 'state.json'),
      path.join(ctx.target, 'ba-kit', 'state.json'), path.join(ctx.target, 'ba-kit', BARRIER),
      path.join(ctx.target, 'ba-kit', 'release-manifest.json'), path.join(ctx.target, 'ba-kit', 'VERSION'),
      path.join(ctx.target, 'ba-kit', 'PRODUCT'), path.join(ctx.target, 'ba-kit', 'PRODUCT_ID'), preferenceFile(ctx.target),
    );
    if (ctx.runtime === 'claude') {
      paths.push(path.join(ctx.target, 'settings.json'));
      const core = path.join(ctx.target, 'core');
      if (!exists(core) || fs.lstatSync(core).isSymbolicLink()) paths.push(core);
    }
    if (ctx.runtime === 'codex') paths.push(path.join(ctx.target, 'config.toml'), path.join(ctx.target, 'hooks.json'));
  }
  const records = [...new Set(paths)].map(file => exists(file) ? snapshotPath(file, snapshot) : ({ file, kind: 'absent' }));
  const journal = { schema_version: 1, status: 'in-progress', runtimes, records };
  writeJson(path.join(transactionRoot, 'journal.json'), journal);
  try {
    for (const ctx of contexts) {
      ctx.previousState = readJson(path.join(base.home, '.local', 'share', 'ba-kit', 'runtime-state', ctx.runtime, 'state.json'), ctx.previousState);
      installOne(ctx);
    }
    for (const runtime of runtimes) {
      const canonical = readJson(path.join(base.home, '.local', 'share', 'ba-kit', 'runtime-state', runtime, 'state.json'), null);
      if (!canonical) continue;
      const activeTargets = runtimeTargets(runtime, base.home);
      if (runtime === 'agy') {
        canonical.targets = activeTargets;
        for (const entry of Object.values(canonical.files || {})) for (const [dest, data] of Object.entries(entry.destinations || {})) {
          if (!activeTargets.some(target => within(target, dest)) && !exists(dest)) data.status = 'retired';
        }
        canonical.registrations = (canonical.registrations || []).filter(file => activeTargets.some(target => within(target, file)));
        if (canonical.preferences) {
          canonical.preferences.projections = (canonical.preferences.projections || [])
            .filter(file => activeTargets.some(target => within(target, file)));
        }
        writeJson(path.join(base.home, '.local', 'share', 'ba-kit', 'runtime-state', runtime, 'state.json'), canonical);
      }
      for (const target of activeTargets) {
        writeJson(path.join(target, 'ba-kit', 'state.json'), canonical);
        writeBarrier(target, runtime);
      }
    }
    journal.status = 'committed'; writeJson(path.join(transactionRoot, 'journal.json'), journal); rm(transactionRoot);
  } catch (error) {
    for (const record of [...records].reverse()) restoreRecord(record, base.home, transactionRoot);
    rm(transactionRoot);
    throw error;
  }
}

function uninstallOne(ctx) {
  const stateFile = path.join(ctx.home, '.local', 'share', 'ba-kit', 'runtime-state', ctx.runtime, 'state.json');
  const state = readJson(stateFile, readJson(path.join(ctx.target, 'ba-kit', 'state.json'), null));
  if (!state || !state.files) return;
  const preserved = [];
  for (const [key, entry] of Object.entries(state.files)) for (const [dest, data] of Object.entries(entry.destinations || {})) {
    assertManagedDestination(ctx.home, ctx.runtime, dest);
    if (!exists(dest)) continue;
    const current = sha256(dest); const expected = data.installed_sha256 || data.source_sha256;
    if (data.status === 'managed' && current === expected) rm(dest); else preserved.push({ key, dest, hash: current, component: entry.component_id, status: 'preserved-modified' });
  }
  if (ctx.runtime === 'claude') unregisterClaude(ctx.target);
  if (ctx.runtime === 'codex') unregisterCodex(ctx.target);
  rm(preferenceFile(ctx.target));
  if (preserved.length) {
    state.status = 'uninstalled-with-preserved-files'; state.files = {}; delete state.preferences;
    for (const item of preserved) {
      state.files[item.key] = state.files[item.key] || { source_sha256: item.hash, component_id: item.component, destinations: {} };
      state.files[item.key].destinations[item.dest] = { installed_sha256: item.hash, status: item.status, registration_ownership: 'ba-kit' };
    }
    writeJson(stateFile, state); writeJson(path.join(ctx.target, 'ba-kit', 'state.json'), state);
  } else {
    rm(stateFile); rm(path.join(ctx.target, 'ba-kit', 'state.json')); rm(path.join(ctx.target, 'ba-kit', 'VERSION')); rm(path.join(ctx.target, 'ba-kit', 'PRODUCT')); rm(path.join(ctx.target, 'ba-kit', 'PRODUCT_ID')); rm(path.join(ctx.target, 'ba-kit', 'release-manifest.json')); rm(path.join(ctx.target, 'ba-kit', BARRIER));
    if (ctx.runtime === 'claude' && fs.lstatSync(path.join(ctx.target, 'core'), { throwIfNoEntry: false })?.isSymbolicLink()) rm(path.join(ctx.target, 'core'));
  }
}

function uninstall(args) {
  const home = path.resolve(args.home || process.env.HOME); recover(home);
  const contexts = [];
  for (const runtime of String(args.runtimes || '').split(',').filter(Boolean)) for (const target of runtimeTargets(runtime, home)) contexts.push({ runtime, target, home });
  const transactionRoot = path.join(home, '.local', 'share', 'ba-kit', 'transactions', `uninstall-${Date.now()}-${process.pid}-${crypto.randomBytes(4).toString('hex')}`);
  const snapshot = path.join(transactionRoot, 'snapshot'); ensureDir(transactionRoot);
  const paths = [];
  for (const ctx of contexts) {
    const state = readJson(path.join(home, '.local', 'share', 'ba-kit', 'runtime-state', ctx.runtime, 'state.json'), readJson(path.join(ctx.target, 'ba-kit', 'state.json'), {}));
    for (const entry of Object.values((state && state.files) || {})) for (const dest of Object.keys(entry.destinations || {})) { assertManagedDestination(home, ctx.runtime, dest); paths.push(dest); }
    paths.push(
      path.join(home, '.local', 'share', 'ba-kit', 'runtime-state', ctx.runtime, 'state.json'),
      path.join(ctx.target, 'ba-kit', 'state.json'), path.join(ctx.target, 'ba-kit', BARRIER),
      path.join(ctx.target, 'ba-kit', 'VERSION'), path.join(ctx.target, 'ba-kit', 'PRODUCT'),
      path.join(ctx.target, 'ba-kit', 'PRODUCT_ID'), path.join(ctx.target, 'ba-kit', 'release-manifest.json'),
      preferenceFile(ctx.target),
      path.join(ctx.target, 'settings.json'), path.join(ctx.target, 'config.toml'), path.join(ctx.target, 'hooks.json'),
    );
    if (ctx.runtime === 'claude') {
      const core = path.join(ctx.target, 'core');
      if (!exists(core) || fs.lstatSync(core).isSymbolicLink()) paths.push(core);
    }
  }
  const records = [...new Set(paths)].map(file => exists(file) ? snapshotPath(file, snapshot) : ({ file, kind: 'absent' }));
  const journal = { schema_version: 1, status: 'in-progress', operation: 'uninstall', runtimes: [...new Set(contexts.map(ctx => ctx.runtime))], records };
  writeJson(path.join(transactionRoot, 'journal.json'), journal);
  try {
    for (const ctx of contexts) uninstallOne(ctx);
    journal.status = 'committed'; writeJson(path.join(transactionRoot, 'journal.json'), journal); rm(transactionRoot);
  } catch (error) {
    for (const record of [...records].reverse()) restoreRecord(record, home, transactionRoot);
    rm(transactionRoot);
    throw error;
  }
}

function doctor(args) {
  const home = path.resolve(args.home || process.env.HOME); let failed = false; let installed = 0;
  const transactions = path.join(home, '.local', 'share', 'ba-kit', 'transactions');
  if (exists(transactions)) for (const id of fs.readdirSync(transactions)) {
    const journal = readJson(path.join(transactions, id, 'journal.json'), null);
    if (!journal || Array.isArray(journal) || typeof journal !== 'object') { console.log(`[RECOVERY] invalid transaction journal: ${id}`); failed = true; installed += 1; }
    else if (journal.status === 'in-progress') { console.log(`[RECOVERY] pending transaction: ${id}`); failed = true; installed += 1; }
  }
  for (const runtime of String(args.runtimes || 'claude,codex,agy').split(',').filter(Boolean)) for (const target of runtimeTargets(runtime, home)) {
    const state = readJson(path.join(home, '.local', 'share', 'ba-kit', 'runtime-state', runtime, 'state.json'), null);
    const legacy = exists(path.join(target, 'ba-kit', 'release-manifest.json')) || exists(path.join(target, 'ba-kit', 'VERSION'));
    if (!state) { if (legacy) { console.log(`[MIGRATE] ${runtime}: schema-v3 state missing at ${target}`); failed = true; installed += 1; } continue; }
    if (!validV3State(state, runtime)) { console.log(`[MIGRATE] ${runtime}: schema-v3 state invalid at ${target}`); failed = true; installed += 1; continue; }
    if (state.status === 'uninstalled-with-preserved-files') {
      console.log(`[UNINSTALLED] ${runtime}: preserved=${Object.keys(state.files || {}).length} target=${target}`);
      continue;
    }
    installed += 1;
    let bad = state.profile === 'solo-basic' ? 0 : (state.payload_schema === 2 ? 0 : 1);
    for (const entry of Object.values(state.files || {})) for (const [dest, data] of Object.entries(entry.destinations || {})) {
      try { assertManagedDestination(home, runtime, dest); } catch (_) { bad += 1; continue; }
      if (data.status === 'managed' && (!exists(dest) || sha256(dest) !== data.installed_sha256)) bad += 1;
    }
    const required = state.profile === 'solo-basic' ? ['skills/ba-start/SKILL.md', 'core/contract.yaml'] : (runtime === 'claude'
      ? ['agents/ba-reviewer.md', 'hooks/registration.json', 'ba-kit/core/contract.yaml']
      : runtime === 'codex'
        ? ['agents/ba-reviewer.toml', 'agents/registration.json', 'skills/ba-review/SKILL.md', 'ba-kit/hooks/registration.json', 'ba-kit/contract.yaml']
        : ['skills/ba-review/SKILL.md', 'knowledge/ba-kit-workflow/metadata.json', 'ba-kit/core/contract.yaml']);
    const destinationState = new Map();
    for (const entry of Object.values(state.files || {})) for (const [dest, data] of Object.entries(entry.destinations || {})) destinationState.set(path.resolve(dest), data);
    for (const relative of required) {
      const requiredPath = path.join(target, relative);
      const data = destinationState.get(path.resolve(requiredPath));
      if (!exists(requiredPath) || !data || data.status !== 'managed' || sha256(requiredPath) !== data.installed_sha256) bad += 1;
    }
    if (state.profile === 'standard' && !registrationHealthy(runtime, target)) bad += 1;
    const preferences = readJson(preferenceFile(target), null);
    if (!preferences || preferences.schema_version !== 1
      || !INTERACTION_LANGUAGES.has(preferences.interaction_language)
      || state.preferences?.interaction_language !== preferences.interaction_language
      || !(state.preferences?.projections || []).includes(preferenceFile(target))) bad += 1;
    console.log(`${bad ? '[FAIL]' : '[OK]'} ${runtime}: schema-v3 payload=${state.payload_schema} target=${target} issues=${bad}${bad ? ' repair=bakit update' : ''}`);
    if (bad) failed = true;
  }
  if (failed && installed > 0) process.exitCode = 1;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args._[0] === 'install') install(args);
  else if (args._[0] === 'uninstall') uninstall(args);
  else if (args._[0] === 'doctor') doctor(args);
  else throw new Error('Usage: runtime-lifecycle.js <install|uninstall|doctor>');
}

try { main(); } catch (error) { console.error(error.message); process.exit(1); }

'use strict';

// Runtime payload contract shared by archive inspection and CLI callers.
// The release manifest is authoritative for component identity; this module
// only validates its shape and the selected runtime coverage in the archive.

const SUPPORTED_RUNTIMES = new Set(['claude', 'codex', 'antigravity']);
const RUNTIME_ALIASES = new Map([
  ['claude', 'claude'],
  ['codex', 'codex'],
  ['agy', 'antigravity'],
  ['antigravity', 'antigravity'],
]);
const SHARED_RUNTIME = 'shared';

const ALLOWED_DESTINATIONS = new Set([
  'skills_root',
  'agents_root',
  'rules_root',
  'templates_root',
  'hooks_root',
  'core_root',
  'guardrails_root',
  'knowledge_root',
  'shared_root',
]);
const ALLOWED_REGISTRATION_HANDLERS = new Set([
  'managed-tree',
  'claude-managed-hook-block',
  'codex-managed-agent-block',
  'codex-managed-hook-block',
  'antigravity-managed-knowledge-entry',
]);
const ALLOWED_RETIREMENT_POLICIES = new Set([
  'remove-if-unmodified',
  'remove-managed-block',
  'remove-managed-entry',
]);
const REQUIRED_FIELDS = [
  'id',
  'runtime',
  'source_prefix',
  'destination_key',
  'registration_handler',
  'required',
  'retirement_policy',
];

function normalizeRuntimeName(value) {
  if (typeof value !== 'string') {
    throw new Error(`Invalid runtime: ${String(value)}`);
  }
  const key = value.trim().toLowerCase();
  const normalized = RUNTIME_ALIASES.get(key);
  if (!normalized) {
    throw new Error(`Unsupported runtime '${value}'. Allowed runtimes: claude, codex, agy`);
  }
  return normalized;
}

function parseRuntimeSelection(value, defaults = ['claude']) {
  const raw = value == null || value === '' ? defaults : value;
  const values = Array.isArray(raw)
    ? raw.flatMap(item => String(item).split(','))
    : String(raw).split(',');
  const runtimes = [];
  for (const item of values) {
    if (!String(item).trim()) continue;
    const runtime = normalizeRuntimeName(item);
    if (!runtimes.includes(runtime)) runtimes.push(runtime);
  }
  if (runtimes.length === 0) {
    throw new Error('At least one runtime must be selected');
  }
  return runtimes;
}

function normalizePrefix(value, field = 'source_prefix') {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`${field} must be a non-empty relative path`);
  }
  let prefix = value.replace(/\\/g, '/');
  while (prefix.startsWith('./')) prefix = prefix.slice(2);
  const parts = prefix.split('/');
  const interiorParts = parts.slice(0, -1);
  if (
    prefix.startsWith('/') ||
    /^[A-Za-z]:\//.test(prefix) ||
    interiorParts.some(part => part === '..' || part === '.' || part === '')
  ) {
    throw new Error(`${field} must be a relative path without traversal: ${value}`);
  }
  if (!prefix.endsWith('/')) {
    throw new Error(`${field} must end with '/': ${value}`);
  }
  return prefix;
}

function regularFilesUnder(members, prefix) {
  const normalizedPrefix = normalizePrefix(prefix);
  return (members || []).filter(member => {
    const memberPath = String(member.path || '').replace(/^\.\//, '');
    return member.type === 'File' && memberPath.startsWith(normalizedPrefix);
  });
}

function validateDescriptor(descriptor, index, seenIds, seenPrefixes) {
  if (!descriptor || typeof descriptor !== 'object' || Array.isArray(descriptor)) {
    throw new Error(`runtime_components[${index}] must be an object`);
  }
  for (const field of REQUIRED_FIELDS) {
    if (!Object.prototype.hasOwnProperty.call(descriptor, field)) {
      throw new Error(`runtime_components[${index}] missing ${field}`);
    }
  }
  if (
    typeof descriptor.id !== 'string' ||
    !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(descriptor.id)
  ) {
    throw new Error(`Invalid runtime component id at index ${index}: ${descriptor.id}`);
  }
  if (seenIds.has(descriptor.id)) {
    throw new Error(`Duplicate runtime component id: ${descriptor.id}`);
  }
  seenIds.add(descriptor.id);

  const runtime = descriptor.runtime;
  if (runtime !== SHARED_RUNTIME && !SUPPORTED_RUNTIMES.has(runtime)) {
    throw new Error(`Invalid runtime component runtime '${runtime}' for ${descriptor.id}`);
  }
  const prefix = normalizePrefix(descriptor.source_prefix);
  if (seenPrefixes.has(prefix)) {
    throw new Error(`Duplicate runtime component source_prefix: ${prefix}`);
  }
  seenPrefixes.add(prefix);

  if (!ALLOWED_DESTINATIONS.has(descriptor.destination_key)) {
    throw new Error(`Invalid destination_key '${descriptor.destination_key}' for ${descriptor.id}`);
  }
  if (!ALLOWED_REGISTRATION_HANDLERS.has(descriptor.registration_handler)) {
    throw new Error(`Invalid registration_handler '${descriptor.registration_handler}' for ${descriptor.id}`);
  }
  if (typeof descriptor.required !== 'boolean') {
    throw new Error(`runtime component required must be boolean for ${descriptor.id}`);
  }
  if (!ALLOWED_RETIREMENT_POLICIES.has(descriptor.retirement_policy)) {
    throw new Error(`Invalid retirement_policy '${descriptor.retirement_policy}' for ${descriptor.id}`);
  }
  return { ...descriptor, source_prefix: prefix };
}

function validateRuntimeComponentContract(manifest, members, options = {}) {
  const profile = options.profile || 'standard';
  if (profile === 'solo-basic') {
    return { native: false, legacy: false, skipped: true, runtimes: [] };
  }

  const runtimes = parseRuntimeSelection(options.runtimes || options.selectedRuntimes);
  const hasSchema = Object.prototype.hasOwnProperty.call(manifest || {}, 'runtime_payload_schema');
  const hasComponents = Object.prototype.hasOwnProperty.call(manifest || {}, 'runtime_components');

  // Older standard archives predate native runtime payloads. They remain
  // installable for the default Claude runtime only; Codex and Antigravity
  // must never silently receive a Claude-shaped archive.
  if (!hasSchema && !hasComponents) {
    const unsupported = runtimes.filter(runtime => runtime !== 'claude');
    if (unsupported.length > 0) {
      throw new Error(`Legacy standard archive supports only claude; requested: ${unsupported.join(', ')}`);
    }
    return { native: false, legacy: true, skipped: false, runtimes };
  }

  if (manifest.runtime_payload_schema !== 2) {
    throw new Error(`Unsupported runtime_payload_schema: expected 2, got ${manifest.runtime_payload_schema}`);
  }
  if (!Array.isArray(manifest.runtime_components) || manifest.runtime_components.length === 0) {
    throw new Error('Standard runtime archive requires a non-empty runtime_components array');
  }

  const seenIds = new Set();
  const seenPrefixes = new Set();
  const components = manifest.runtime_components.map((descriptor, index) =>
    validateDescriptor(descriptor, index, seenIds, seenPrefixes)
  );
  const selected = new Set([...runtimes, SHARED_RUNTIME]);
  const selectedComponents = components.filter(component => selected.has(component.runtime));
  if (!runtimes.some(runtime => components.some(component => component.runtime === runtime))) {
    throw new Error(`Runtime component contract has no descriptor for selected runtime(s): ${runtimes.join(', ')}`);
  }
  if (!components.some(component => component.runtime === SHARED_RUNTIME)) {
    throw new Error('Runtime component contract requires shared components');
  }
  for (const runtime of runtimes) {
    if (!components.some(component => component.runtime === runtime && component.required)) {
      throw new Error(`Runtime component contract has no required component for ${runtime}`);
    }
  }
  if (!components.some(component => component.runtime === SHARED_RUNTIME && component.required)) {
    throw new Error('Runtime component contract requires a required shared component');
  }

  for (const component of selectedComponents) {
    if (!component.required) continue;
    if (regularFilesUnder(members, component.source_prefix).length === 0) {
      throw new Error(`Missing required runtime component files: ${component.id} (${component.source_prefix})`);
    }
  }

  return { native: true, legacy: false, skipped: false, runtimes, components };
}

module.exports = {
  ALLOWED_DESTINATIONS,
  ALLOWED_REGISTRATION_HANDLERS,
  ALLOWED_RETIREMENT_POLICIES,
  SUPPORTED_RUNTIMES,
  normalizePrefix,
  normalizeRuntimeName,
  parseRuntimeSelection,
  regularFilesUnder,
  validateRuntimeComponentContract,
};

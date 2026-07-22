#!/usr/bin/env node
'use strict';

// ============================================================
// BA-kit version-contract check
// ============================================================
// Validates: tag == package.json.version == embedded CLI_VERSION == frozen minimum
//
// Usage:
//   node tests/check-version-contract.js [--tag vX.Y.Z]
//
// Operates in two modes:
//   1. CI (--tag provided):   assert tag == package == embedded, embedded >= frozen
//   2. Local (--tag omitted): assert package == embedded, embedded >= frozen

const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '..');
const PKG = JSON.parse(fs.readFileSync(path.join(REPO, 'package.json'), 'utf8'));
const CLI_SCRIPT = fs.readFileSync(path.join(REPO, 'bakit'), 'utf8');

// Solo frozen minimum (from Phase 01)
const SOLO_REPO = process.env.BA_KIT_SOLO_DIR
  ? path.resolve(process.env.BA_KIT_SOLO_DIR)
  : path.resolve(REPO, '..', 'ba-kit-solo');
const SOLO_FROZEN_PATH = path.join(
  SOLO_REPO, '.github', 'release-min-cli-version'
);
const SOLO_MIN = fs.existsSync(SOLO_FROZEN_PATH)
  ? fs.readFileSync(SOLO_FROZEN_PATH, 'utf8').trim()
  : null;

const tagArg = process.argv.includes('--tag')
  ? process.argv[process.argv.indexOf('--tag') + 1]
  : null;

function fail(msg) {
  console.error(`FAIL: ${msg}`);
  process.exitCode = 1;
}

function pass(msg) {
  console.log(`  PASS: ${msg}`);
}

// --- Parse versions ---
function normalise(v) {
  return (v || '').replace(/^v/, '');
}

const pkgVersion = normalise(PKG.version);

let embeddedVersion = null;
const m = CLI_SCRIPT.match(/CLI_VERSION=["']?v?(\d+\.\d+\.\d+)/);
if (m) embeddedVersion = m[1];

let frozenVersion = null;
if (SOLO_MIN) frozenVersion = normalise(SOLO_MIN);

// --- Checks ---
console.log('=== Version Contract Check ===');
console.log(`  package.json:  ${pkgVersion}`);
console.log(`  embedded:      ${embeddedVersion || 'NOT FOUND'}`);
console.log(`  frozen Solo:   ${frozenVersion || 'NOT FOUND'}`);
if (tagArg) console.log(`  tag:           ${normalise(tagArg)}`);

if (!embeddedVersion) {
  fail('CLI_VERSION not found in bakit script');
} else {
  pass('CLI_VERSION found in bakit script');
}

if (!frozenVersion) {
  fail('Solo frozen minimum version not found');
} else {
  pass(`Solo frozen minimum: ${frozenVersion}`);
}

// Tag must match package version (CI only)
if (tagArg) {
  const tagVersion = normalise(tagArg);
  if (tagVersion !== pkgVersion) {
    fail(`Tag version (${tagVersion}) != package.json version (${pkgVersion})`);
  } else {
    pass('Tag version matches package.json');
  }
}

// Package version must match embedded CLI_VERSION
if (pkgVersion !== embeddedVersion) {
  fail(`package.json version (${pkgVersion}) != embedded CLI_VERSION (${embeddedVersion})`);
} else {
  pass('package.json version matches embedded CLI_VERSION');
}

// Parse semver for comparison
function parseSemver(v) {
  const m = v.match(/^(\d+)\.(\d+)\.(\d+)(-.+)?$/);
  if (!m) return null;
  return { major: parseInt(m[1]), minor: parseInt(m[2]), patch: parseInt(m[3]), pre: m[4] || '' };
}

function compareSemver(a, b) {
  if (a.major !== b.major) return a.major - b.major;
  if (a.minor !== b.minor) return a.minor - b.minor;
  if (a.patch !== b.patch) return a.patch - b.patch;
  if (!a.pre && b.pre) return 1;
  if (a.pre && !b.pre) return -1;
  return 0;
}

// Embedded >= frozen minimum
const emb = parseSemver(embeddedVersion);
const fro = frozenVersion ? parseSemver(frozenVersion) : null;

if (emb && fro) {
  if (compareSemver(emb, fro) < 0) {
    fail(`Embedded CLI_VERSION (${embeddedVersion}) < frozen minimum (${frozenVersion})`);
  } else {
    pass(`Embedded CLI_VERSION (${embeddedVersion}) >= frozen minimum (${frozenVersion})`);
  }
} else if (!emb) {
  fail('Cannot parse embedded CLI_VERSION');
} else if (!fro) {
  fail('Cannot parse frozen minimum version');
}

if (process.exitCode && process.exitCode > 0) {
  console.error('\nVersion contract FAILED');
} else {
  console.log('\nVersion contract PASSED');
}

process.exit(process.exitCode || 0);

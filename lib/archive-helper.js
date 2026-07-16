#!/usr/bin/env node
'use strict';

// ============================================================
// BA-kit archive-helper — safe inspect/extract for release archives
// ============================================================
//
// Usage:
//   node archive-helper.js inspect --archive A --profile P --cli-version V
//         --selected-product ID --selected-version TAG
//   node archive-helper.js extract --archive A --profile P --destination DIR
//
// Bash never extracts unvalidated archives. This helper uses npm `tar`
// strict APIs to inspect members, validate metadata, and safely extract.

const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const {
  parseRuntimeSelection,
  validateRuntimeComponentContract,
} = require('./runtime-component-contract');

// --- Profile quota limits ---
const PROFILES = {
  'solo-basic': {
    compressedLimit: 25 * 1024 * 1024,    // 25 MiB
    memberLimit: 5000,
    fileLimit: 5 * 1024 * 1024,           // 5 MiB
    unpackedLimit: 100 * 1024 * 1024,     // 100 MiB
    pathComponentLimit: 255,
    memberPathLimit: 1024,
  },
  'standard': {
    compressedLimit: 250 * 1024 * 1024,   // 250 MiB
    memberLimit: 50000,
    fileLimit: 100 * 1024 * 1024,         // 100 MiB
    unpackedLimit: 1024 * 1024 * 1024,    // 1 GiB
    pathComponentLimit: 255,
    memberPathLimit: 1024,
  },
};

// Reserved state paths that never come from an archive
const RESERVED_PATHS = new Set([
  'ba-kit/VERSION',
  'ba-kit/PRODUCT',
  'ba-kit/PRODUCT_ID',
  'ba-kit/state.json',
  'ba-kit/release-manifest.json',
  'ba-kit/backups',
  'ba-kit/transaction.json',
  'ba-kit/RECOVERY_REQUIRED.json',
]);

const REJECTED_PATH_PREFIXES = [
  'ba-kit/backups/',
  'ba-kit/VERSION',
  'ba-kit/PRODUCT',
  'ba-kit/PRODUCT_ID',
  'ba-kit/state.json',
  'ba-kit/release-manifest.json',
  'ba-kit/transaction.json',
  'ba-kit/RECOVERY_REQUIRED.json',
];

// --- CLI argument parsing ---
function parseArgs() {
  const args = { profile: null, archive: null, destination: null, cliVersion: null, selectedProduct: null, selectedVersion: null, runtimes: null };
  const argv = process.argv.slice(2);
  let cmd = argv[0];

  for (let i = 1; i < argv.length; i++) {
    switch (argv[i]) {
      case '--archive': args.archive = argv[++i]; break;
      case '--profile': args.profile = argv[++i]; break;
      case '--destination': args.destination = argv[++i]; break;
      case '--cli-version': args.cliVersion = argv[++i]; break;
      case '--selected-product': args.selectedProduct = argv[++i]; break;
      case '--selected-version': args.selectedVersion = argv[++i]; break;
      case '--runtimes': args.runtimes = argv[++i]; break;
      default:
        if (argv[i].startsWith('--runtimes=')) args.runtimes = argv[i].slice('--runtimes='.length);
        break;
    }
  }
  return { cmd, args };
}

// --- Validation helpers ---
function rejectPath(name) {
  // Absolute, drive, UNC, parent-traversal
  if (path.isAbsolute(name)) return `absolute path: ${name}`;
  if (/^[A-Za-z]:[/\\]/.test(name)) return `drive path: ${name}`;
  if (name.startsWith('\\\\') || name.startsWith('//')) return `UNC path: ${name}`;
  // Normalize: strip ./ prefix, strip trailing /
  let clean = name;
  while (clean.startsWith('./')) clean = clean.slice(2);
  while (clean.endsWith('/')) clean = clean.slice(0, -1);
  const parts = clean.split('/').filter(Boolean);
  for (const p of parts) {
    if (p === '..') return `parent traversal: ${name}`;
    if (p === '.') return `invalid component in: ${name}`;
    // Control characters
    if (/[\x00-\x1f\x7f]/.test(p)) return `control character in: ${name}`;
    if (p.length > 255) return `path component too long (${p.length} > 255): ${name}`;
  }
  if (name.length > 1024) return `member path too long (${name.length} > 1024): ${name}`;

  // Reserved state paths
  const normalized = name.replace(/^\.\//, '');
  for (const prefix of REJECTED_PATH_PREFIXES) {
    if (normalized === prefix || normalized.startsWith(prefix + '/')) {
      return `reserved state path: ${name}`;
    }
  }
  return null;
}

async function inspectArchive(archivePath, profileName, opts) {
  const stat = fs.statSync(archivePath);
  const profile = PROFILES[profileName];
  if (!profile) throw new Error(`Unknown profile: ${profileName}`);

  // Compressed size check
  if (stat.size > profile.compressedLimit) {
    throw new Error(`Archive too large: ${stat.size} > ${profile.compressedLimit} (${profileName})`);
  }

  // Use tar to list members
  const tar = await import('tar');
  const members = [];
  let totalUnpacked = 0;
  let manifest = null;

  // First pass: list and validate
  await tar.list({
    file: archivePath,
    onentry(entry) {
      let name = (entry.path || '').replace(/\\/g, '/');

      // Skip root directory entry (tar includes './' or '.')
      if (name === './' || name === '.' || name === '') return;
      // Skip macOS AppleDouble resource fork metadata
      const basename = name.split('/').pop();
      if (basename.startsWith('._')) return;

      const type = entry.type;
      const size = entry.size || 0;

      // Validate path
      const rejection = rejectPath(name);
      if (rejection) throw new Error(rejection);

      // Reject non-regular, non-directory entries
      if (type !== 'File' && type !== 'Directory') {
        throw new Error(`Unsupported entry type '${type}': ${name}`);
      }

      // File size limit
      if (type === 'File' && size > profile.fileLimit) {
        throw new Error(`File too large (${size} > ${profile.fileLimit}): ${name}`);
      }

      // Unpacked bytes tracking
      if (type === 'File') totalUnpacked += size;

      // Duplicate member check
      const normalized = name.replace(/^\.\//, '');
      if (members.some(m => m.path === normalized)) {
        throw new Error(`Duplicate member: ${name}`);
      }

      members.push({ path: normalized, type, size });
    },
  });

  // Quota checks
  if (members.length > profile.memberLimit) {
    throw new Error(`Too many members: ${members.length} > ${profile.memberLimit}`);
  }
  if (totalUnpacked > profile.unpackedLimit) {
    throw new Error(`Unpacked size too large: ${totalUnpacked} > ${profile.unpackedLimit}`);
  }

  // Verify manifest.json and release-manifest.json exist
  const manifestMember = members.find(m => m.path === 'manifest.json' || m.path === './manifest.json');
  if (!manifestMember) throw new Error('Missing manifest.json');

  const releaseManifestMember = members.find(m => m.path === 'release-manifest.json' || m.path === './release-manifest.json');
  if (!releaseManifestMember) throw new Error('Missing release-manifest.json');

  // Extract once into an isolated directory, then validate both manifests
  // against the exact bytes that would be installed.
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ba-kit-helper-'));
  try {
    await tar.extract({ file: archivePath, cwd: tmpDir });
    manifest = JSON.parse(fs.readFileSync(path.join(tmpDir, 'manifest.json'), 'utf8'));
    const releaseManifest = JSON.parse(
      fs.readFileSync(path.join(tmpDir, 'release-manifest.json'), 'utf8')
    );
    validateReleaseManifest(releaseManifest, members, tmpDir);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }

  // --- Metadata validation ---
  if (profileName === 'solo-basic') {
    // Strict Solo identity
    if (manifest.product_id !== 'ba-kit-solo-basic') throw new Error(`Expected product_id=ba-kit-solo-basic, got: ${manifest.product_id}`);
    if (manifest.profile !== 'solo-basic') throw new Error(`Expected profile=solo-basic, got: ${manifest.profile}`);
    if (manifest.name !== 'BA-kit Solo Basic') throw new Error(`Expected name=BA-kit Solo Basic, got: ${manifest.name}`);
    if (manifest.version !== opts.selectedVersion.replace(/^v/, '')) {
      throw new Error(`Version mismatch: manifest=${manifest.version}, selected=${opts.selectedVersion.replace(/^v/, '')}`);
    }
  } else if (profileName === 'standard') {
    // Enriched-or-legacy: prefer exact product_id/profile when present
    if (manifest.product_id && manifest.product_id !== opts.selectedProduct) {
      throw new Error(`Product ID mismatch: ${manifest.product_id} != ${opts.selectedProduct}`);
    }
    if (manifest.profile && manifest.profile !== 'standard') {
      throw new Error(`Profile mismatch: ${manifest.profile} != standard`);
    }
    // Legacy: accept name=ba-kit without product/profile fields
    if (!manifest.product_id && manifest.name !== 'ba-kit') {
      throw new Error(`Legacy standard archive must have name=ba-kit, got: ${manifest.name}`);
    }

    validateRuntimeComponentContract(manifest, members, {
      profile: profileName,
      runtimes: opts.runtimes,
    });
  }

  // Enforce min_cli_version
  if (manifest.min_cli_version) {
    const min = parseSemver(manifest.min_cli_version);
    const current = parseSemver(opts.cliVersion);
    if (!min || !current) throw new Error(`Invalid semver: min=${manifest.min_cli_version}, cli=${opts.cliVersion}`);
    if (compareSemver(current, min) < 0) {
      throw new Error(`CLI version ${opts.cliVersion} < minimum ${manifest.min_cli_version}`);
    }
  }

  // Build checksums from archive (for later verification)
  // Store member list for manifest cross-check
  const fileMembers = members.filter(m => m.type === 'File');

  return {
    ok: true,
    profile: profileName,
    members,
    fileCount: fileMembers.length,
    totalUnpacked,
    manifest,
    roots: extractRoots(members),
  };
}

function validateReleaseManifest(releaseManifest, members, extractDir) {
  if (!releaseManifest || Array.isArray(releaseManifest) || typeof releaseManifest !== 'object') {
    throw new Error('release-manifest.json must be an object');
  }

  const expected = members
    .filter(member => member.type === 'File' && member.path !== 'release-manifest.json')
    .map(member => `./${member.path}`)
    .sort();
  const actual = Object.keys(releaseManifest).sort();
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) {
    throw new Error('release-manifest.json keys do not match archive files');
  }

  for (const key of expected) {
    const expectedHash = releaseManifest[key];
    if (typeof expectedHash !== 'string' || !/^[a-f0-9]{64}$/i.test(expectedHash)) {
      throw new Error(`Invalid SHA-256 for ${key}`);
    }
    const filePath = path.join(extractDir, key.slice(2));
    const actualHash = crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
    if (actualHash !== expectedHash.toLowerCase()) {
      throw new Error(`release-manifest hash mismatch: ${key}`);
    }
  }
}

function extractRoots(members) {
  const roots = new Set();
  for (const m of members) {
    const parts = m.path.split('/');
    if (parts.length > 0) roots.add(parts[0] === '.' ? parts[1] || '' : parts[0]);
  }
  return [...roots].filter(Boolean).sort();
}

async function extractArchive(archivePath, destDir) {
  if (!fs.existsSync(destDir)) {
    fs.mkdirSync(destDir, { recursive: true });
  }

  const resolved = fs.realpathSync(destDir);

  // Verify destination is empty
  if (fs.readdirSync(resolved).length > 0) {
    throw new Error(`Destination directory is not empty: ${resolved}`);
  }

  const tar = await import('tar');
  await tar.extract({
    file: archivePath,
    cwd: resolved,
    // Only extract regular files and directories; no links
    filter: (_path, entry) => entry.type === 'File' || entry.type === 'Directory',
  });

  return { ok: true, destination: resolved };
}

// --- Semver helpers ---
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

// --- Main ---
async function main() {
  const { cmd, args } = parseArgs();

  if (cmd === 'inspect') {
    if (!args.archive || !args.profile || !args.cliVersion) {
      console.error('Usage: archive-helper.js inspect --archive A --profile P --cli-version V [--selected-product ID] [--selected-version TAG] [--runtimes claude,codex,agy]');
      process.exit(1);
    }
    const result = await inspectArchive(args.archive, args.profile, {
      cliVersion: args.cliVersion,
      selectedProduct: args.selectedProduct || '',
      selectedVersion: args.selectedVersion || '',
      runtimes: parseRuntimeSelection(args.runtimes),
    });
    console.log(JSON.stringify(result));
  } else if (cmd === 'extract') {
    if (!args.archive || !args.profile || !args.destination) {
      console.error('Usage: archive-helper.js extract --archive A --profile P --destination DIR');
      process.exit(1);
    }
    const result = await extractArchive(args.archive, args.destination);
    console.log(JSON.stringify(result));
  } else {
    console.error(`Unknown command: ${cmd}`);
    console.error('Commands: inspect, extract');
    process.exit(1);
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.log(JSON.stringify({ ok: false, error: err.message }));
    process.exit(1);
  });
}

module.exports = {
  PROFILES,
  inspectArchive,
  extractArchive,
  parseArgs,
  rejectPath,
  validateReleaseManifest,
};

#!/usr/bin/env node
// Node is the one guaranteed-present runtime (npm requires it), so it's the
// dispatcher that locates bash and execs the real CLI — instead of npm's
// auto-generated Windows shim hardcoding a call to bash.exe and crashing with
// a cryptic CommandNotFoundException when Git for Windows isn't on PATH.
'use strict';

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const SCRIPT = path.join(__dirname, '..', 'ba-kit');

// Git for Windows' default installer only adds its `cmd\` dir to PATH, not
// `bin\` (where bash.exe lives) — so `where bash` misses even a correctly
// installed Git. Custom install locations also miss the hardcoded fixed
// candidates below, so registry lookup covers both: Git's installer writes
// its actual InstallPath to one of these keys regardless of where it landed.
const REGISTRY_KEYS = [
  ['HKLM', 'SOFTWARE\\GitForWindows'],
  ['HKLM', 'SOFTWARE\\WOW6432Node\\GitForWindows'],
  ['HKCU', 'SOFTWARE\\GitForWindows'],
];

function registryBashCandidates() {
  const found = [];
  for (const [hive, key] of REGISTRY_KEYS) {
    const result = spawnSync('reg', ['query', `${hive}\\${key}`, '/v', 'InstallPath'], { encoding: 'utf8' });
    if (result.status === 0 && result.stdout) {
      const match = result.stdout.match(/InstallPath\s+REG_SZ\s+(.+)/);
      if (match) found.push(path.join(match[1].trim(), 'bin', 'bash.exe'));
    }
  }
  return found;
}

function findBash() {
  if (process.platform !== 'win32') return 'bash';

  const where = spawnSync('where', ['bash'], { encoding: 'utf8' });
  if (where.status === 0 && where.stdout.trim()) {
    return where.stdout.trim().split(/\r?\n/)[0];
  }

  const candidates = [
    process.env['ProgramFiles'] && path.join(process.env['ProgramFiles'], 'Git', 'bin', 'bash.exe'),
    process.env['ProgramFiles(x86)'] && path.join(process.env['ProgramFiles(x86)'], 'Git', 'bin', 'bash.exe'),
    process.env['ProgramW6432'] && path.join(process.env['ProgramW6432'], 'Git', 'bin', 'bash.exe'),
    process.env['LocalAppData'] && path.join(process.env['LocalAppData'], 'Programs', 'Git', 'bin', 'bash.exe'),
    ...registryBashCandidates(),
  ].filter(Boolean);

  return candidates.find((p) => fs.existsSync(p)) || null;
}

const bash = findBash();

if (!bash) {
  console.error('');
  console.error('BA-kit requires Git Bash (bash.exe) to run on Windows — none found on PATH');
  console.error('or in the usual Git for Windows install locations.');
  console.error('');
  console.error('Install Git for Windows (includes Git Bash): https://git-scm.com/download/win');
  console.error('Then re-run this command.');
  console.error('');
  process.exit(1);
}

const result = spawnSync(bash, [SCRIPT, ...process.argv.slice(2)], { stdio: 'inherit' });

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status === null ? 1 : result.status);

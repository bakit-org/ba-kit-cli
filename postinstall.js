#!/usr/bin/env node
// Preserve user-owned commands that can shadow the npm-installed manager.
// On Windows, PATHEXT resolves bakit.cmd / bakit.ps1 before the extensionless
// file, so all three names must be checked — checking only "bakit" never
// catches the actual shadowing file on Windows and users need an actionable
// warning for every filename that can win PATH resolution.
const fs = require('fs');
const path = require('path');

const localBinDir = path.join(
  process.env.HOME || process.env.USERPROFILE || '~',
  '.local', 'bin'
);

for (const name of ['bakit', 'bakit.cmd', 'bakit.ps1']) {
  const candidate = path.join(localBinDir, name);

  if (!fs.existsSync(candidate)) continue;

  console.log('');
  console.log('\x1b[33m⚠  PATH CONFLICT DETECTED\x1b[0m');
  console.log('');
  console.log(`  Preserved existing user-owned file: ${candidate}`);
  console.log('  It may shadow the npm-installed bakit manager.');
  console.log('  Move or remove it manually, then run `bakit` from your npm bin directory.');
  console.log('');
}

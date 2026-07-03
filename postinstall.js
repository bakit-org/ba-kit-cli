#!/usr/bin/env node
// ponytail: remove stale pre-npm framework binaries that shadow the npm install.
// On Windows, PATHEXT resolves ba-kit.cmd / ba-kit.ps1 before the extensionless
// file, so all three names must be checked — checking only "ba-kit" never
// catches the actual shadowing file on Windows and the warning silently never
// fires, leaving users with a broken "No such file or directory" on first run.
const fs = require('fs');
const path = require('path');

const localBinDir = path.join(
  process.env.HOME || process.env.USERPROFILE || '~',
  '.local', 'bin'
);

for (const name of ['ba-kit', 'ba-kit.cmd', 'ba-kit.ps1']) {
  const candidate = path.join(localBinDir, name);

  if (!fs.existsSync(candidate)) continue;

  const stat = fs.lstatSync(candidate);
  // Symlink is fine — npm will manage it
  if (stat.isSymbolicLink()) continue;

  // Regular file will shadow npm's own shim when ~/.local/bin comes before
  // npm's bin dir in PATH. Same convention as the bash CLI's own guard: remove
  // and log, don't just warn (a warning gets missed and users hit the crash).
  try {
    fs.unlinkSync(candidate);
    console.log(`  Removed stale BA-kit framework binary at ${candidate} (was shadowing npm CLI)`);
  } catch (err) {
    console.log('');
    console.log('\x1b[33m⚠  PATH CONFLICT DETECTED\x1b[0m');
    console.log('');
    console.log(`  A stale BA-kit framework binary exists at ${candidate}`);
    console.log('  and could not be removed automatically:', err.message);
    console.log('  This will shadow the npm-installed CLI.');
    console.log('');
    console.log('  Fix manually, then use any ba-kit command normally.');
    console.log('');
  }
}

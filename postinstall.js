#!/usr/bin/env node
// ponytail: detect stale framework binary shadowing npm install, warn user to fix
const fs = require('fs');
const path = require('path');

const npmBin = process.env.npm_execpath
  ? path.dirname(process.env.npm_execpath)
  : null;
const localBin = path.join(
  process.env.HOME || process.env.USERPROFILE || '~',
  '.local', 'bin', 'ba-kit'
);

// Only relevant when npm prefix differs from ~/.local
if (!fs.existsSync(localBin)) return;

const stat = fs.lstatSync(localBin);
// Symlink is fine — npm will manage it
if (stat.isSymbolicLink()) return;

// Regular file at ~/.local/bin/ba-kit will shadow npm's symlink
// when ~/.local/bin comes before npm's bin in PATH
console.log('');
console.log('\x1b[33m⚠  PATH CONFLICT DETECTED\x1b[0m');
console.log('');
console.log('  A stale BA-kit framework binary exists at:');
console.log('    ~/.local/bin/ba-kit');
console.log('  This will shadow the npm-installed CLI.');
console.log('');
console.log('  Fix:');
console.log('    rm ~/.local/bin/ba-kit');
console.log('    npm install -g @bakit-org/cli   # re-create symlink if needed');
console.log('');
console.log('  Then run: ba-kit install');
console.log('');

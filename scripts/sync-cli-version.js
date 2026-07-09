#!/usr/bin/env node
// Runs as npm's "version" lifecycle script (see package.json) so
// `npm version <bump>` is the one command that keeps ba-kit's CLI_VERSION
// in lockstep with package.json's version — no manual second edit to forget.
'use strict';

const fs = require('fs');
const path = require('path');

const { version } = require('../package.json');
const file = path.join(__dirname, '..', 'ba-kit');

const src = fs.readFileSync(file, 'utf8');
const updated = src.replace(/CLI_VERSION="[^"]*"/, `CLI_VERSION="${version}"`);

if (updated === src && !src.includes(`CLI_VERSION="${version}"`)) {
  throw new Error('CLI_VERSION pattern not found in ba-kit — sync failed');
}

fs.writeFileSync(file, updated);

#!/usr/bin/env node
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const VALID_LANGUAGES = new Set(['vi', 'en']);

function configPath(env = process.env, home = env.HOME || env.USERPROFILE || os.homedir()) {
  const configHome = env.XDG_CONFIG_HOME || path.join(home, '.config');
  return path.join(configHome, 'ba-kit', 'config.json');
}

function readPreference(options = {}) {
  const env = options.env || process.env;
  const file = options.file || configPath(env, options.home || env.HOME || env.USERPROFILE || os.homedir());
  if (!fs.existsSync(file)) return { language: 'vi', status: 'missing', file };

  let config;
  try {
    config = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_) {
    return { language: 'vi', status: 'invalid', file };
  }
  if (!config || Array.isArray(config) || typeof config !== 'object') {
    return { language: 'vi', status: 'invalid', file };
  }

  if (config.schema_version === 1 && VALID_LANGUAGES.has(config.interaction_language)) {
    return { language: config.interaction_language, status: 'valid', file };
  }
  if (config.schema_version == null && VALID_LANGUAGES.has(config.language)) {
    return { language: config.language, status: 'legacy', file };
  }
  return { language: 'vi', status: 'invalid', file };
}

function writePreference(language, options = {}) {
  if (!VALID_LANGUAGES.has(language)) throw new Error(`invalid interaction language: ${language}`);
  const env = options.env || process.env;
  const file = options.file || configPath(env, options.home || env.HOME || env.USERPROFILE || os.homedir());
  const directory = path.dirname(file);
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  try { fs.chmodSync(directory, 0o700); } catch (_) { /* best effort on Windows */ }
  const temp = `${file}.tmp-${process.pid}-${crypto.randomBytes(6).toString('hex')}`;
  const payload = { schema_version: 1, interaction_language: language };
  fs.writeFileSync(temp, `${JSON.stringify(payload, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temp, file);
  try { fs.chmodSync(file, 0o600); } catch (_) { /* best effort on Windows */ }
  return file;
}

function main(argv) {
  const command = argv[0];
  let home = process.env.HOME;
  let language = '';
  for (let i = 1; i < argv.length; i += 1) {
    if (argv[i] === '--home') home = argv[++i];
    else if (argv[i] === '--language') language = argv[++i];
    else throw new Error(`unknown argument: ${argv[i]}`);
  }
  if (command === 'read') {
    const result = readPreference({ home });
    process.stdout.write(`${result.language}|${result.status}\n`);
    return;
  }
  if (command === 'write') {
    writePreference(language, { home });
    return;
  }
  throw new Error('Usage: interaction-language-config.js <read|write> [--home PATH] [--language vi|en]');
}

if (require.main === module) {
  try { main(process.argv.slice(2)); } catch (error) { console.error(error.message); process.exit(1); }
}

module.exports = { VALID_LANGUAGES, configPath, readPreference, writePreference };

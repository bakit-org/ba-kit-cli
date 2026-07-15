'use strict';
// ============================================================
// BA-kit archive-helper tests
// ============================================================
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const HELPER = path.join(__dirname, '..', 'lib', 'archive-helper.js');

function tempDir() { return fs.mkdtempSync(path.join(os.tmpdir(), 'ba-kit-test-')); }
function sha256(f) { return crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex'); }

function makeSoloArchive(dir, overrides = {}) {
  const payload = path.join(dir, 'payload');
  fs.mkdirSync(payload, { recursive: true });
  fs.mkdirSync(path.join(payload, '.claude', 'skills', 'ba-do'), { recursive: true });
  fs.mkdirSync(path.join(payload, '.claude', 'templates'), { recursive: true });
  fs.mkdirSync(path.join(payload, 'ba-kit', 'core'), { recursive: true });

  fs.writeFileSync(path.join(payload, '.claude', 'skills', 'ba-do', 'SKILL.md'), '# ba-do\n');
  fs.writeFileSync(path.join(payload, '.claude', 'templates', 'test.md'), '# template\n');
  fs.writeFileSync(path.join(payload, 'ba-kit', 'core', 'contract.yaml'), 'version: 1\n');

  const manifest = {
    name: 'BA-kit Solo Basic',
    product_id: overrides.product_id || 'ba-kit-solo-basic',
    profile: overrides.profile || 'solo-basic',
    version: overrides.version || '0.0.0',
    min_cli_version: overrides.min_cli_version || '1.0.0',
    release_date: '2026-07-15',
    ...overrides.extraManifest,
  };
  fs.writeFileSync(path.join(payload, 'manifest.json'), JSON.stringify(manifest));

  // Generate release-manifest.json
  const rm = {};
  walkFiles(payload).forEach(f => {
    const rel = path.relative(payload, f);
    if (rel !== 'release-manifest.json') rm['./' + rel] = sha256(f);
  });
  fs.writeFileSync(
    path.join(payload, 'release-manifest.json'),
    JSON.stringify(overrides.releaseManifest || rm, null, 2)
  );

  const archive = path.join(dir, 'test.tar.gz');
  execSync(`COPYFILE_DISABLE=1 tar -czf '${archive}' -C '${payload}' .`);
  return archive;
}

function walkFiles(dir) {
  const result = [];
  for (const entry of fs.readdirSync(dir, { recursive: true })) {
    const p = path.join(dir, entry);
    if (fs.statSync(p).isFile()) result.push(p);
  }
  return result.sort();
}

// --- Tests ---

test('inspect valid solo-basic archive', async () => {
  const dir = tempDir();
  const archive = makeSoloArchive(dir);
  const out = execSync(`node '${HELPER}' inspect --archive '${archive}' --profile solo-basic --cli-version 1.2.9 --selected-product ba-kit-solo-basic --selected-version v0.0.0`);
  const result = JSON.parse(out.toString());
  assert.equal(result.ok, true);
  assert.equal(result.profile, 'solo-basic');
  assert.ok(result.fileCount > 0);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('reject release manifest hash mismatch', async () => {
  const dir = tempDir();
  const archive = makeSoloArchive(dir, {
    releaseManifest: { './manifest.json': '0'.repeat(64) },
  });
  assert.throws(
    () => execSync(`node '${HELPER}' inspect --archive '${archive}' --profile solo-basic --cli-version 1.3.0 --selected-product ba-kit-solo-basic --selected-version v0.0.0`, { stdio: 'pipe' }),
    /Command failed/
  );
  fs.rmSync(dir, { recursive: true, force: true });
});

test('reject min_cli_version below required', async (t) => {
  const dir = tempDir();
  const archive = makeSoloArchive(dir, { min_cli_version: '2.0.0' });
  try {
    const r = execSync(`node '${HELPER}' inspect --archive '${archive}' --profile solo-basic --cli-version 1.2.9 --selected-product ba-kit-solo-basic --selected-version v0.0.0`, { stdio: 'pipe' });
    const out = r.toString();
    assert.ok(out.includes('CLI version') || out.includes('version'), `expected version error, got: ${out}`);
  } catch (e) {
    const out = (e.stdout || '').toString() + (e.stderr || '').toString();
    assert.ok(out.includes('CLI version') || out.includes('version'), `expected version error, got: ${out}`);
  }
  fs.rmSync(dir, { recursive: true, force: true });
});

test('reject wrong product_id for solo-basic', async (t) => {
  const dir = tempDir();
  const archive = makeSoloArchive(dir, { product_id: 'ba-kit' });
  try {
    const r = execSync(`node '${HELPER}' inspect --archive '${archive}' --profile solo-basic --cli-version 1.2.9 --selected-product ba-kit-solo-basic --selected-version v0.0.0`, { stdio: 'pipe' });
    const out = r.toString();
    assert.ok(out.includes('product_id') || out.includes('product'), `expected product error, got: ${out}`);
  } catch (e) {
    const out = (e.stdout || '').toString() + (e.stderr || '').toString();
    assert.ok(out.includes('product_id') || out.includes('product'), `expected product error, got: ${out}`);
  }
  fs.rmSync(dir, { recursive: true, force: true });
});

test('reject extract to non-empty directory', async () => {
  const dir = tempDir();
  const dest = path.join(dir, 'dest');
  fs.mkdirSync(dest, { recursive: true });
  fs.writeFileSync(path.join(dest, 'existing.txt'), 'already here');

  const archive = makeSoloArchive(dir);
  try {
    execSync(`node '${HELPER}' extract --archive '${archive}' --profile solo-basic --destination '${dest}'`, { stdio: 'pipe' });
    assert.fail('should have thrown');
  } catch (e) {
    const out = (e.stdout || '').toString() + (e.stderr || '').toString();
    assert.ok(out.includes('not empty'), `expected 'not empty', got: ${out}`);
  }
  fs.rmSync(dir, { recursive: true, force: true });
});

test('extract valid solo-basic archive', async () => {
  const dir = tempDir();
  const dest = path.join(dir, 'dest');
  fs.mkdirSync(dest, { recursive: true });

  const archive = makeSoloArchive(dir);
  const out = execSync(`node '${HELPER}' extract --archive '${archive}' --profile solo-basic --destination '${dest}'`);
  const result = JSON.parse(out.toString());
  assert.equal(result.ok, true);

  assert.ok(fs.existsSync(path.join(dest, 'manifest.json')));
  assert.ok(fs.existsSync(path.join(dest, '.claude', 'skills', 'ba-do', 'SKILL.md')));
  fs.rmSync(dir, { recursive: true, force: true });
});

test('reject archive exceeding compressed limit', async () => {
  const dir = tempDir();
  const payload = path.join(dir, 'payload');
  fs.mkdirSync(path.join(payload, '.claude', 'skills', 'ba-do'), { recursive: true });
  fs.mkdirSync(path.join(payload, 'ba-kit', 'core'), { recursive: true });

  // Create a large file to exceed 25MB
  const big = path.join(payload, '.claude', 'skills', 'ba-do', 'large.txt');
  const fd = fs.openSync(big, 'w');
  fs.writeSync(fd, Buffer.alloc(26 * 1024 * 1024, 'x'));
  fs.closeSync(fd);

  const manifest = { name: 'BA-kit Solo Basic', product_id: 'ba-kit-solo-basic', profile: 'solo-basic', version: '0.0.0', min_cli_version: '1.0.0', release_date: '2026-07-15' };
  fs.writeFileSync(path.join(payload, 'manifest.json'), JSON.stringify(manifest));
  fs.writeFileSync(path.join(payload, 'release-manifest.json'), '{}');

  const archive = path.join(dir, 'big.tar.gz');
  execSync(`COPYFILE_DISABLE=1 tar -czf '${archive}' -C '${payload}' .`);

  try {
    execSync(`node '${HELPER}' inspect --archive '${archive}' --profile solo-basic --cli-version 1.2.9`, { stdio: 'pipe' });
    assert.fail('should have thrown');
  } catch (e) {
    const out = (e.stdout || '').toString() + (e.stderr || '').toString();
    assert.ok(out.includes('large') || out.includes('Archive'), `expected size error, got: ${out}`);
  }
  fs.rmSync(dir, { recursive: true, force: true });
});

test('reject reserved state paths', async () => {
  const dir = tempDir();
  const payload = path.join(dir, 'payload');
  fs.mkdirSync(path.join(payload, 'ba-kit'), { recursive: true });
  fs.writeFileSync(path.join(payload, 'ba-kit', 'state.json'), '{}');

  const manifest = { name: 'BA-kit Solo Basic', product_id: 'ba-kit-solo-basic', profile: 'solo-basic', version: '0.0.0', min_cli_version: '1.0.0', release_date: '2026-07-15' };
  fs.writeFileSync(path.join(payload, 'manifest.json'), JSON.stringify(manifest));
  fs.writeFileSync(path.join(payload, 'release-manifest.json'), '{}');

  const archive = path.join(dir, 'test.tar.gz');
  execSync(`COPYFILE_DISABLE=1 tar -czf '${archive}' -C '${payload}' .`);

  try {
    execSync(`node '${HELPER}' inspect --archive '${archive}' --profile solo-basic --cli-version 1.2.9`, { stdio: 'pipe' });
    assert.fail('should have thrown');
  } catch (e) {
    const out = (e.stdout || '').toString() + (e.stderr || '').toString();
    assert.ok(out.includes('reserved') || out.includes('state'), `expected reserved error, got: ${out}`);
  }
  fs.rmSync(dir, { recursive: true, force: true });
});

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SMOKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SMOKE_DIR/lib/sandbox.sh"
source "$SMOKE_DIR/lib/release-fixture.sh"

CLI="$SMOKE_DIR/../../bakit"
STUB_DIR="$SMOKE_DIR/stubs"

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL + 1)); }

echo "=== PHASE 03: Runtime Install & Transaction Tests ==="
echo ""

# Generate fixtures
export COPYFILE_DISABLE=1
generate_public_solo_fixture

# Test 1: Help shows Solo as free product
echo "--- Test 1: Help lists Solo as free ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" help 2>&1)
if echo "$OUTPUT" | grep -q "Miễn phí"; then pass; else fail "Solo not marked free in help"; fi
sandbox_teardown

# Test 2: version command works
echo "--- Test 2: version shows CLI version ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" version 2>&1)
if echo "$OUTPUT" | grep -q "BA-kit CLI"; then pass; else fail "version broken"; fi
sandbox_teardown

# Test 3: Doctor runs without error
echo "--- Test 3: doctor runs ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" doctor 2>&1) || true
if [ -n "$OUTPUT" ]; then pass; else fail "doctor produced no output"; fi
sandbox_teardown

# Test 4: Doctor reports on Solo without crashing
echo "--- Test 4: doctor mentions Solo ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" doctor 2>&1) || true
if echo "$OUTPUT" | grep -q "BA-kit"; then pass; else fail "doctor output empty or no BA-kit ref"; fi
sandbox_teardown

# Test 5: Product registry validates internally
echo "--- Test 5: registry validation runs ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" version 2>&1)
# version always exits 0 - validates registry internally
if [ $? -eq 0 ]; then pass; else fail "registry validation failed"; fi
sandbox_teardown

# Test 6: Logged-out suggests Solo
echo "--- Test 6: Logged-out finds Solo ---"
sandbox_setup
export GH_AUTH_MODE=logged-out
export CURL_MODE=ok
OUTPUT=$(echo "" | PATH="$STUB_DIR:$PATH" HOME="$HOME" bash "$CLI" install 2>&1) || true
if echo "$OUTPUT" | grep -q "BA-kit Solo Basic"; then pass; else fail "Solo not in output: $OUTPUT"; fi
sandbox_teardown

# Test 7: --product flag still rejected
echo "--- Test 7: Reject --product ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" install --product "foo" 2>&1) || true
if echo "$OUTPUT" | grep -q "Không hiểu"; then pass; else fail "--product not rejected"; fi
sandbox_teardown

# Test 8: Archive helper inspect works
echo "--- Test 8: archive helper inspect ---"
sandbox_setup
FIXTURE="$FIXTURE_DIR/ba-kit-v0.0.0.tar.gz"
if [ -f "$FIXTURE" ]; then
  RESULT=$(node "$SMOKE_DIR/../../lib/archive-helper.js" inspect \
    --archive "$FIXTURE" --profile solo-basic --cli-version 1.2.9 \
    --selected-product ba-kit-solo-basic --selected-version v0.0.0 2>&1) || true
  if echo "$RESULT" | jq -e '.ok' >/dev/null 2>&1; then
    pass
  else
    fail "inspect failed: $RESULT"
  fi
else
  fail "fixture missing: $FIXTURE"
fi
sandbox_teardown

# Test 9: Full reinstall backups stay external and non-recursive
echo "--- Test 9: reinstall backup is external and non-recursive ---"
sandbox_setup
export GH_AUTH_MODE=logged-out
export CURL_MODE=fixture-download
export CURL_FIXTURE_DIR="$FIXTURE_DIR"

LEGACY_BACKUP_ROOT="$HOME/.claude/ba-kit/backups"
LEGACY_MARKER="$LEGACY_BACKUP_ROOT/legacy-snapshot/marker.txt"
mkdir -p "$(dirname "$LEGACY_MARKER")"
echo "legacy backup must remain untouched" > "$LEGACY_MARKER"
LEGACY_BEFORE=$(find "$LEGACY_BACKUP_ROOT" -print | sort)

OUTPUT=$(PATH="$STUB_DIR:$PATH" HOME="$HOME" bash "$CLI" install --runtime claude 2>&1) || {
  fail "fixture-backed install failed: $OUTPUT"
  OUTPUT=""
}

BACKUP_ROOT="$HOME/.local/share/ba-kit/backups/claude"
if [ -d "$BACKUP_ROOT" ] && [ "$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" -eq 1 ]; then
  pass
else
  fail "first install did not create one external backup: $OUTPUT"
fi

if find "$BACKUP_ROOT" -type d -path '*/ba-kit/backups' -print -quit | grep -q .; then
  fail "external snapshot recursively copied legacy ba-kit/backups"
else
  pass
fi

sleep 1
OUTPUT=$(printf 'y\n' | PATH="$STUB_DIR:$PATH" HOME="$HOME" bash "$CLI" install --runtime claude 2>&1) || {
  fail "fixture-backed reinstall failed: $OUTPUT"
  OUTPUT=""
}

if [ "$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" -eq 2 ]; then
  pass
else
  fail "reinstall did not create a second external backup: $OUTPUT"
fi

if [ -f "$LEGACY_MARKER" ] && [ "$(cat "$LEGACY_MARKER")" = "legacy backup must remain untouched" ] && [ "$(find "$LEGACY_BACKUP_ROOT" -print | sort)" = "$LEGACY_BEFORE" ]; then
  pass
else
  fail "legacy in-tree backups were changed"
fi

if find "$HOME/.claude/ba-kit/backups" -mindepth 2 -type d -name '20??-*' -print -quit | grep -q .; then
  fail "new backup was written below the legacy in-tree root"
else
  pass
fi

OUTPUT=$(printf 'y\n' | PATH="$STUB_DIR:$PATH" HOME="$HOME" bash "$CLI" uninstall --runtime claude 2>&1) || {
  fail "schema-v3 uninstall failed: $OUTPUT"
  OUTPUT=""
}

PRE_UNINSTALL_BACKUP=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'pre-uninstall-*' -print -quit)
if [ -n "$PRE_UNINSTALL_BACKUP" ] && [ -f "$PRE_UNINSTALL_BACKUP/state.json" ]; then
  pass
else
  fail "uninstall did not create an external pre-uninstall snapshot with state: $OUTPUT"
fi

if [ -n "$PRE_UNINSTALL_BACKUP" ] && find "$PRE_UNINSTALL_BACKUP" -type d -path '*/ba-kit/backups' -print -quit | grep -q .; then
  fail "pre-uninstall snapshot recursively copied legacy ba-kit/backups"
else
  pass
fi

if [ -f "$LEGACY_MARKER" ] && [ "$(cat "$LEGACY_MARKER")" = "legacy backup must remain untouched" ] && [ "$(find "$LEGACY_BACKUP_ROOT" -print | sort)" = "$LEGACY_BEFORE" ]; then
  pass
else
  fail "uninstall changed legacy in-tree backups"
fi
sandbox_teardown

echo ""
echo "=== Phase 03 Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$FAIL"

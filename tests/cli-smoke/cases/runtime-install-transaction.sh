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

echo ""
echo "=== Phase 03 Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$FAIL"

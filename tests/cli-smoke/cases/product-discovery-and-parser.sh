#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Phase 02 — product discovery, parser, and routing tests
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SMOKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SMOKE_DIR/lib/sandbox.sh"
source "$SMOKE_DIR/lib/assertions.sh"

CLI="$SMOKE_DIR/../../ba-kit"
STUB_DIR="$SMOKE_DIR/stubs"

PASS=0; FAIL=0

pass() { PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL + 1)); }

echo "=== PHASE 02: Product Discovery & Parser Tests ==="
echo ""

# Test 1: Logged-out — Solo only, auto-selected
echo "--- Test 1: Logged-out = Solo only ---"
sandbox_setup
export GH_AUTH_MODE=logged-out
export CURL_MODE=ok
OUTPUT=$(echo "" | PATH="$STUB_DIR:$PATH" HOME="$HOME" bash "$CLI" install 2>&1) || true
if echo "$OUTPUT" | grep -q "BA-kit Solo Basic"; then pass; else fail "Solo not auto-selected: $OUTPUT"; fi
sandbox_teardown

# Test 2: Logged-in, no private access — Solo only
echo "--- Test 2: Logged-in, no private access = Solo only ---"
sandbox_setup
export GH_AUTH_MODE=logged-in
export GH_ACCESS_REPOS=""
export CURL_MODE=ok
OUTPUT=$(echo "" | PATH="$STUB_DIR:$PATH" HOME="$HOME" bash "$CLI" install 2>&1) || true
if echo "$OUTPUT" | grep -q "BA-kit Solo Basic"; then pass; else fail "Solo not auto-selected: $OUTPUT"; fi
sandbox_teardown

# Test 3: Logged-in with BA-kit access — 2 choices
echo "--- Test 3: BA-kit access = numbered menu ---"
sandbox_setup
export GH_AUTH_MODE=logged-in
export GH_ACCESS_REPOS="bakit-org/bakit"
export CURL_MODE=ok
OUTPUT=$(echo "1" | PATH="$STUB_DIR:$PATH" HOME="$HOME" bash "$CLI" install 2>&1) || true
if echo "$OUTPUT" | grep -qE '\[1\]|\[2\]'; then pass; else fail "No numbered prompt: $OUTPUT"; fi
sandbox_teardown

# Test 4: No --product flag accepted
echo "--- Test 4: Reject --product ---"
sandbox_setup
export GH_AUTH_MODE=logged-out
OUTPUT=$(bash "$CLI" install --product "something" 2>&1) || true
if echo "$OUTPUT" | grep -q "Không hiểu tham số"; then pass; else fail "--product not rejected: $OUTPUT"; fi
sandbox_teardown

# Test 5: Version output
echo "--- Test 5: version command ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" version 2>&1)
if echo "$OUTPUT" | grep -q "BA-kit CLI"; then pass; else fail "version not shown: $OUTPUT"; fi
sandbox_teardown

# Test 6: Help output mentions public product
echo "--- Test 6: help shows public product ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" help 2>&1)
if echo "$OUTPUT" | grep -q "Miễn phí"; then pass; else fail "public label not in help: $OUTPUT"; fi
sandbox_teardown

# Test 7: Extra args to doctor rejected
echo "--- Test 7: extra args to doctor ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" doctor extra 2>&1) || true
if [ -n "$OUTPUT" ]; then pass; else fail "extra args silently accepted"; fi
sandbox_teardown

# Test 8: Help runs without gh
echo "--- Test 8: help without gh ---"
sandbox_setup
OUTPUT=$(PATH="$STUB_DIR:$PATH" HOME="$HOME" bash "$CLI" help 2>&1)
if echo "$OUTPUT" | grep -q "install"; then pass; else fail "help failed"; fi
sandbox_teardown

echo ""
echo "=== Phase 02 Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$FAIL"

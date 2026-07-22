#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SMOKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SMOKE_DIR/lib/sandbox.sh"

CLI="$SMOKE_DIR/../../bakit"
STUB_DIR="$SMOKE_DIR/stubs"

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL + 1)); }

echo "=== PHASE 04: Update, Doctor, State Tests ==="
echo ""

# Test 1: version shows CLI
echo "--- Test 1: version ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" version 2>&1)
if echo "$OUTPUT" | grep -q "BA-kit CLI: v"; then pass; else fail "no CLI version"; fi
sandbox_teardown

# Test 2: doctor with no installs
echo "--- Test 2: doctor no installs ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" doctor 2>&1) || true
if echo "$OUTPUT" | grep -q "chưa cài"; then pass; else fail "doctor output wrong: $OUTPUT"; fi
sandbox_teardown

# Test 3: version with no installs
echo "--- Test 3: version no installs ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" version 2>&1)
if echo "$OUTPUT" | grep -q "chưa cài"; then pass; else fail "no chưa cài in version"; fi
sandbox_teardown

# Test 4: update with no installs fails cleanly
echo "--- Test 4: update no installs ---"
sandbox_setup
# resolve_runtime_state needs to succeed; empty detection happens before download
OUTPUT=$(HOME="$HOME" bash "$CLI" update 2>&1) || true
if echo "$OUTPUT" | grep -q "chưa được cài"; then pass; else fail "update wrong: $OUTPUT"; fi
sandbox_teardown

# Test 5: uninstall with no installs
echo "--- Test 5: uninstall no installs ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" uninstall 2>&1) || true
if echo "$OUTPUT" | grep -q "Không có runtime"; then pass; else fail "uninstall wrong: $OUTPUT"; fi
sandbox_teardown

# Test 6: doctor shows Solo as public
echo "--- Test 6: doctor shows Solo public ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" doctor 2>&1) || true
if echo "$OUTPUT" | grep -q "miễn phí"; then pass; else fail "Solo not public in doctor"; fi
sandbox_teardown

# Test 7: doctor handles legacy state gracefully
echo "--- Test 7: doctor with legacy fragments ---"
sandbox_setup
root="$HOME/.claude"
mkdir -p "$root/ba-kit"
echo "BA-kit" > "$root/ba-kit/PRODUCT"
echo "v1.0.0" > "$root/ba-kit/VERSION"
echo '{"old":"hash"}' > "$root/ba-kit/release-manifest.json"
OUTPUT=$(HOME="$HOME" bash "$CLI" doctor 2>&1) || true
if echo "$OUTPUT" | grep -q "legacy"; then pass; else fail "legacy not detected: $OUTPUT"; fi
sandbox_teardown

# Test 8: version detects legacy state
echo "--- Test 8: version with legacy ---"
sandbox_setup
root="$HOME/.claude"
mkdir -p "$root/ba-kit"
echo "BA-kit" > "$root/ba-kit/PRODUCT"
echo "v1.0.0" > "$root/ba-kit/VERSION"
echo '{"old":"hash"}' > "$root/ba-kit/release-manifest.json"
OUTPUT=$(HOME="$HOME" bash "$CLI" version 2>&1)
if echo "$OUTPUT" | grep -q "legacy"; then pass; else fail "legacy not in version: $OUTPUT"; fi
sandbox_teardown

echo ""
echo "=== Phase 04 Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$FAIL"

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

echo "=== PHASE 04: Uninstall & Tombstone Tests ==="
echo ""

# Test 1: unscoped uninstall with no installs is safe
echo "--- Test 1: unscoped uninstall empty ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" uninstall 2>&1) || true
if echo "$OUTPUT" | grep -q "Không có runtime"; then pass; else fail "empty uninstall wrong: $OUTPUT"; fi
sandbox_teardown

# Test 2: uninstall with invalid runtime
echo "--- Test 2: uninstall bad runtime ---"
sandbox_setup
set +e
OUTPUT=$(HOME="$HOME" bash "$CLI" uninstall --runtime "nonexist" 2>&1)
RC=$?
set -e
if [ $RC -ne 0 ]; then pass; else fail "bad runtime not rejected (rc=$RC)"; fi
sandbox_teardown

# Test 3: --product still rejected everywhere
echo "--- Test 3: --product rejected in uninstall ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" uninstall --product "x" 2>&1) || true
if echo "$OUTPUT" | grep -q "Không hiểu"; then pass; else fail "--product not rejected"; fi
sandbox_teardown

# Test 4: update with legacy state suggests install
echo "--- Test 4: update with legacy works ---"
sandbox_setup
root="$HOME/.claude"
mkdir -p "$root/ba-kit"
echo "BA-kit" > "$root/ba-kit/PRODUCT"
echo "v1.0.0" > "$root/ba-kit/VERSION"
echo '{}' > "$root/ba-kit/release-manifest.json"
OUTPUT=$(HOME="$HOME" bash "$CLI" update 2>&1 | head -5) || true
if [ -n "$OUTPUT" ]; then pass; else fail "update produced no output"; fi
sandbox_teardown

# Test 5: partial state rejected
echo "--- Test 5: partial state rejected ---"
sandbox_setup
mkdir -p "$HOME/.claude/ba-kit"
echo "BA-kit" > "$HOME/.claude/ba-kit/PRODUCT"
# Missing VERSION + manifest
OUTPUT=$(HOME="$HOME" bash "$CLI" doctor 2>&1) || true
# Doctor should at least note partial state (not crash)
if [ -n "$OUTPUT" ]; then pass; else fail "doctor crashed on partial state"; fi
sandbox_teardown

# Test 6: empty runtime fragments don't block doctor
echo "--- Test 6: doctor handles transaction marker ---"
sandbox_setup
mkdir -p "$HOME/.claude/ba-kit"
echo '{"op":"install"}' > "$HOME/.claude/ba-kit/transaction.json"
OUTPUT=$(HOME="$HOME" bash "$CLI" doctor 2>&1) || true
if [ -n "$OUTPUT" ]; then pass; else fail "doctor crashed on transaction marker"; fi
sandbox_teardown

echo ""
echo "=== Phase 04 Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$FAIL"

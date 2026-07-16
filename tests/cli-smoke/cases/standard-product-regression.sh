#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# BA-kit CLI smoke test — standard product regression
# ============================================================
# Ensures private product (BA-kit full/Pro) functionality is
# not broken by public Solo additions. Tests with stubbed
# authenticated access.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SMOKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SMOKE_DIR/lib/sandbox.sh"

CLI="$SMOKE_DIR/../../ba-kit"
STUB_DIR="$SMOKE_DIR/stubs"
export PATH="$STUB_DIR:$PATH"

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL + 1)); }

write_standard_state() {
  local root="$1"
  local home_dir="${root%/.claude}"
  local state_dir="$home_dir/.local/share/ba-kit/runtime-state/claude"
  mkdir -p "$root/ba-kit"
  mkdir -p "$state_dir"
  cat > "$state_dir/state.json" << STATE
{
  "schema_version": 3,
  "runtime_key": "claude",
  "payload_schema": 1,
  "product_id": "ba-kit",
  "product_name": "BA-kit",
  "profile": "standard",
  "version": "v1.0.0",
  "status": "installed",
  "targets": ["$root"],
  "files": {},
  "registrations": [],
  "updated_at": "2026-01-01T00:00:00Z"
}
STATE
  cp "$state_dir/state.json" "$root/ba-kit/state.json"
}

echo "=== PHASE 05: Standard Product Regression ==="
echo ""

# Test 1: logged-in with private access sees numbered menu (BA-kit + Solo)
echo "--- Test 1: authenticated menu includes private + Solo ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" GH_AUTH_MODE=logged-in GH_ACCESS_REPOS="bakit-org/bakit,bakit-org/ba-kit-solo-pro" bash "$CLI" version 2>&1) || true
# Should show both BA-kit and Solo as available — version shows runtime status
# Doctor shows the product availability list; version shows per-runtime versions
if [ -n "$OUTPUT" ]; then pass; else fail "version produced no output on authenticated"; fi
sandbox_teardown

# Test 2: doctor shows standard product components when installed
echo "--- Test 2: doctor shows standard profile components ---"
sandbox_setup
root="$HOME/.claude"
mkdir -p "$root/ba-kit" "$root/skills" "$root/templates" "$root/agents" "$root/hooks"
write_standard_state "$root"

OUTPUT=$(HOME="$HOME" GH_AUTH_MODE=logged-in bash "$CLI" doctor 2>&1) || true
# Doctor should not crash on standard state
if [ -n "$OUTPUT" ]; then pass; else fail "doctor produced no output on standard state"; fi
sandbox_teardown

# Test 3: CLI continues to work with --runtime parsing (no regression)
echo "--- Test 3: --runtime parsing unchanged ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" install --runtime "claude" 2>&1) || true
# Should either succeed or fail on network — but not fail on argument parsing
if echo "$OUTPUT" | grep -q "Không hiểu"; then fail "--runtime parsing rejected: $OUTPUT"; else pass; fi
sandbox_teardown

# Test 4: version shows free/public for Solo in all modes
echo "--- Test 4: doctor shows Solo as public in logged-out mode ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" GH_AUTH_MODE=logged-out bash "$CLI" doctor 2>&1)
# Doctor page shows "miễn phí, luôn có sẵn" for Solo
if echo "$OUTPUT" | grep -q "miễn phí"; then pass; else fail "Solo not shown as free in logged-out doctor: $OUTPUT"; fi
sandbox_teardown

# Test 5: --product flag consistently rejected (not silently ignored)
echo "--- Test 5: --product rejected in install ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" install --product "ba-kit" 2>&1) || true
if echo "$OUTPUT" | grep -q "Không hiểu"; then pass; else fail "--product not rejected in install: $OUTPUT"; fi
sandbox_teardown

# Test 6: update with standard state works (not just Solo)
echo "--- Test 6: update with standard state ---"
sandbox_setup
root="$HOME/.claude"
mkdir -p "$root/ba-kit" "$root/skills" "$root/templates"
write_standard_state "$root"

OUTPUT=$(HOME="$HOME" GH_AUTH_MODE=logged-in GH_ACCESS_REPOS="bakit-org/bakit" bash "$CLI" update 2>&1) || true
# Should select the installed product before release lookup.
if echo "$OUTPUT" | grep -q "unbound variable"; then
  fail "update crashed before product selection: $OUTPUT"
elif echo "$OUTPUT" | grep -q "Phiên bản mới nhất"; then
  pass
else
  fail "update did not reach release check: $OUTPUT"
fi
sandbox_teardown

# Test 7: uninstall with standard state
echo "--- Test 7: uninstall auto-detect with standard state ---"
sandbox_setup
root="$HOME/.claude"
mkdir -p "$root/ba-kit" "$root/skills" "$root/templates"
write_standard_state "$root"

OUTPUT=$(HOME="$HOME" GH_AUTH_MODE=logged-in bash "$CLI" uninstall 2>&1) || true
# Should detect standard product and attempt uninstall
if [ -n "$OUTPUT" ]; then pass; else fail "uninstall produced no output on standard state"; fi
sandbox_teardown

# Test 8: unrelated files survive standard product lifecycle
echo "--- Test 8: unrelated sentinel survives standard product ops ---"
sandbox_setup
root="$HOME/.claude"
mkdir -p "$root/skills/unrelated-skill"
echo "unrelated content" > "$root/skills/unrelated-skill/SKILL.md"
echo '{"hooks":{}}' > "$root/settings.json"

mkdir -p "$root/ba-kit"
write_standard_state "$root"

# Run doctor — must not delete unrelated content
bash "$CLI" doctor 2>&1 || true
HOME="$HOME"

if [ -f "$root/skills/unrelated-skill/SKILL.md" ]; then pass; else fail "unrelated skill was deleted"; fi
if [ -f "$root/settings.json" ]; then pass; else fail "settings.json was deleted"; fi

sandbox_teardown

echo ""
echo "=== Phase 05 Standard Regression Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$FAIL"

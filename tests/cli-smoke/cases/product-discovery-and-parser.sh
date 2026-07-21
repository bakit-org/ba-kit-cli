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
if [ "$(jq -r '.interaction_language' "$HOME/.config/ba-kit/config.json")" = vi ]; then pass; else fail "non-TTY install did not persist vi fallback"; fi
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

# Test 9: persisted English preference localizes subsequent commands
echo "--- Test 9: persisted English preference ---"
sandbox_setup
mkdir -p "$HOME/.config/ba-kit"
printf '{"schema_version":1,"interaction_language":"en"}\n' > "$HOME/.config/ba-kit/config.json"
OUTPUT=$(HOME="$HOME" bash "$CLI" help 2>&1)
if echo "$OUTPUT" | grep -q "Supported runtimes" && ! echo "$OUTPUT" | grep -q "Runtime hỗ trợ"; then pass; else fail "English help not localized: $OUTPUT"; fi
sandbox_teardown

# Test 10: invalid config falls back to vi and install repairs it
echo "--- Test 10: invalid config fallback ---"
sandbox_setup
mkdir -p "$HOME/.config/ba-kit"
printf '{"schema_version":1,"interaction_language":"fr"}\n' > "$HOME/.config/ba-kit/config.json"
OUTPUT=$(echo "" | HOME="$HOME" GH_AUTH_MODE=logged-out CURL_MODE=fail PATH="$STUB_DIR:$PATH" bash "$CLI" install 2>&1) || true
if [ "$(jq -r '.interaction_language' "$HOME/.config/ba-kit/config.json")" = vi ]; then pass; else fail "invalid config was not repaired to vi: $OUTPUT"; fi
sandbox_teardown

# Test 11: XDG_CONFIG_HOME overrides ~/.config
echo "--- Test 11: XDG config path ---"
sandbox_setup
export XDG_CONFIG_HOME="$SANDBOX_DIR/xdg"
mkdir -p "$XDG_CONFIG_HOME/ba-kit"
chmod 777 "$XDG_CONFIG_HOME/ba-kit"
node "$SMOKE_DIR/../../lib/interaction-language-config.js" write --home "$HOME" --language en
CONFIG_MODE=$(node -e 'console.log((require("fs").statSync(process.argv[1]).mode & 0o777).toString(8))' "$XDG_CONFIG_HOME/ba-kit/config.json")
CONFIG_DIR_MODE=$(node -e 'console.log((require("fs").statSync(process.argv[1]).mode & 0o777).toString(8))' "$XDG_CONFIG_HOME/ba-kit")
if [ "$(jq -r '.interaction_language' "$XDG_CONFIG_HOME/ba-kit/config.json")" = en ] && [ "$CONFIG_MODE" = 600 ] && [ "$CONFIG_DIR_MODE" = 700 ] && [ ! -e "$HOME/.config/ba-kit/config.json" ]; then pass; else fail "XDG config path or permissions not respected"; fi
sandbox_teardown

# Test 12: no public --language flag
echo "--- Test 12: reject --language ---"
sandbox_setup
OUTPUT=$(HOME="$HOME" bash "$CLI" install --language en 2>&1) || true
if echo "$OUTPUT" | grep -q "Không hiểu tham số" && [ ! -e "$HOME/.config/ba-kit/config.json" ]; then pass; else fail "--language was accepted or mutated config: $OUTPUT"; fi
sandbox_teardown

# Test 13: interactive TTY selection persists English
echo "--- Test 13: interactive language selection ---"
sandbox_setup
if command -v expect >/dev/null 2>&1; then
  EXPECT_OUTPUT=$(TEST_CLI="$CLI" TEST_HOME="$HOME" TEST_PATH="$STUB_DIR:$PATH" expect -c '
    set timeout 10
    spawn env HOME=$env(TEST_HOME) XDG_CONFIG_HOME= GH_AUTH_MODE=logged-out CURL_MODE=api-fail PATH=$env(TEST_PATH) bash $env(TEST_CLI) install
    expect "Choose language"
    send "3\r"
    expect "Invalid selection"
    send "2\r"
    expect eof
  ' 2>&1) || true
  if [ "$(jq -r '.interaction_language' "$HOME/.config/ba-kit/config.json" 2>/dev/null)" = en ] \
    && echo "$EXPECT_OUTPUT" | grep -q "Detected" \
    && ! echo "$EXPECT_OUTPUT" | grep -Eq 'Phát hiện|Đang tìm|Không thể lấy release'; then
    pass
  else
    fail "interactive English selection failed: $EXPECT_OUTPUT"
  fi
else
  echo "  SKIP: expect is unavailable; interactive TTY case not executed" >&2
fi
sandbox_teardown

# Test 14: legacy language key migrates without losing a valid choice
echo "--- Test 14: legacy preference migration ---"
sandbox_setup
mkdir -p "$HOME/.config/ba-kit"
printf '{"language":"en"}\n' > "$HOME/.config/ba-kit/config.json"
OUTPUT=$(echo "" | HOME="$HOME" GH_AUTH_MODE=logged-out CURL_MODE=api-fail PATH="$STUB_DIR:$PATH" bash "$CLI" install 2>&1) || true
if [ "$(jq -r '.interaction_language' "$HOME/.config/ba-kit/config.json")" = en ] && echo "$OUTPUT" | grep -q "Detected"; then pass; else fail "legacy preference was not migrated: $OUTPUT"; fi
sandbox_teardown

# Test 15: representative English commands contain no Vietnamese routing leakage
echo "--- Test 15: complete English command output ---"
sandbox_setup
mkdir -p "$HOME/.config/ba-kit"
printf '{"schema_version":1,"interaction_language":"en"}\n' > "$HOME/.config/ba-kit/config.json"
ENGLISH_OUTPUT=""
for command in help version doctor update uninstall install; do
  CURRENT=$(HOME="$HOME" GH_AUTH_MODE=logged-out CURL_MODE=ok PATH="$STUB_DIR:$PATH" bash "$CLI" "$command" 2>&1) || true
  ENGLISH_OUTPUT="$ENGLISH_OUTPUT\n$CURRENT"
done
if echo "$ENGLISH_OUTPUT" | grep -Eq 'Lỗi|Chưa|CHƯA|Không có runtime|Đang dùng|Quyền truy cập|Cài đặt|Gỡ cài đặt|chưa cài|miễn phí|cần gh'; then
  fail "Vietnamese leaked into representative English commands: $ENGLISH_OUTPUT"
else
  pass
fi
sandbox_teardown

echo ""
echo "=== Phase 02 Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$FAIL"

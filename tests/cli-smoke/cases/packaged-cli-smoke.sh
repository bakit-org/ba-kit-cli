#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# BA-kit CLI smoke test — packaged CLI smoke
# ============================================================
# Installs the npm tarball into a disposable prefix and verifies
# the packaged dispatcher, helper, and basic help/version commands.
# Does NOT require gh auth — uses stubs for network commands.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SMOKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_REPO="$(cd "$SMOKE_DIR/../.." && pwd)"

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL + 1)); }

echo "=== PHASE 05: Packaged CLI Smoke ==="
echo ""

# --- Setup: build the tarball ---
echo "--- Building npm package ---"
TARBALL_JSON=$(cd "$CLI_REPO" && npm pack --json 2>/dev/null)
if [ -z "$TARBALL_JSON" ]; then
  fail "npm pack failed"
  exit 1
fi

TARBALL_FILE=$(echo "$TARBALL_JSON" | jq -r '.[0].filename // empty')
TARBALL_PATH="$CLI_REPO/$TARBALL_FILE"

if [ ! -f "$TARBALL_PATH" ]; then
  fail "tarball not found at $TARBALL_PATH"
  exit 1
fi
echo "  Tarball: $TARBALL_FILE"

# Extract once for all tests
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT
tar -xzf "$TARBALL_PATH" -C "$WORK_DIR" 2>/dev/null
EXTRACTED="$WORK_DIR/package"

# --- Test 1: package contents ---
echo "--- Test 1: package contains required files ---"
PACKED_FILES=$(tar -tzf "$TARBALL_PATH" 2>/dev/null | sed 's|^package/||' | grep -v '^$' | grep -v '^package$' | sort)

for required in \
  "bakit" "bin/bakit.js" "lib/archive-helper.js" \
  "lib/cli-localization.sh" "lib/interaction-language-config.js" \
  "lib/runtime-component-contract.js" "lib/runtime-lifecycle.js" \
  "lib/runtime-registration.js" "README.md" "package.json"; do
  if echo "$PACKED_FILES" | grep -qF "$required"; then
    pass "package contains: $required"
  else
    fail "package missing: $required"
  fi
done

# Must NOT contain .env, node_modules, tests
for forbidden in ".env" "node_modules/" "tests/" "ba-kit" "bin/ba-kit.js"; do
  if echo "$PACKED_FILES" | grep -qF "$forbidden"; then
    fail "package contains forbidden: $forbidden"
  else
    pass "package excludes: $forbidden"
  fi
done

# --- Test 2: extract and verify dispatcher ---
echo "--- Test 2: dispatcher can locate bash ---"
if [ ! -f "$EXTRACTED/bin/bakit.js" ]; then
  fail "dispatcher not found in extracted package"
else
  OUTPUT=$(node -e "require(process.argv[1])" "$EXTRACTED/bin/bakit.js" 2>&1) && RC=0 || RC=$?
  if [ "$RC" -eq 0 ]; then
    pass "dispatcher loads without error"
  else
    fail "dispatcher load error: $OUTPUT"
  fi
fi

# --- Test 3: archive helper loads ---
echo "--- Test 3: archive helper loads without error ---"
if [ ! -f "$EXTRACTED/lib/archive-helper.js" ]; then
  fail "archive-helper.js not found in package"
else
  node -c "$EXTRACTED/lib/archive-helper.js" 2>&1 && RC=0 || RC=$?
  if [ "$RC" -eq 0 ]; then
    pass "archive helper syntax valid"
  else
    fail "archive helper has syntax errors"
  fi

  if grep -q "cmd === 'inspect'" "$EXTRACTED/lib/archive-helper.js" && \
     grep -q "cmd === 'extract'" "$EXTRACTED/lib/archive-helper.js"; then
    pass "archive helper has inspect + extract commands"
  else
    fail "archive helper missing inspect/extract commands"
  fi
fi

# --- Test 4: bash script syntax ---
echo "--- Test 4: bash script syntax valid ---"
if [ ! -f "$EXTRACTED/bakit" ]; then
  fail "bakit script not found in package"
else
  bash -n "$EXTRACTED/bakit" 2>&1 && RC=0 || RC=$?
  if [ "$RC" -eq 0 ]; then
    pass "bakit script syntax valid"
  else
    fail "bakit script has syntax errors"
  fi
fi

# --- Test 5: disposable global npm install exposes only bakit ---
echo "--- Test 5: disposable global npm install exposes only bakit ---"
SANDBOX=$(mktemp -d)
# Keep preference reads inside the sandbox when CI exports XDG_CONFIG_HOME.
export XDG_CONFIG_HOME="$SANDBOX/home/.config"
trap "rm -rf $WORK_DIR $SANDBOX" EXIT

mkdir -p "$SANDBOX/home/.claude/skills"
mkdir -p "$SANDBOX/home/.claude/agents"
mkdir -p "$SANDBOX/home/.claude/hooks"
mkdir -p "$SANDBOX/bin"

cat > "$SANDBOX/bin/curl" << 'STUB'
#!/usr/bin/env bash
echo '[]'
STUB
chmod +x "$SANDBOX/bin/curl"

cat > "$SANDBOX/bin/gh" << 'STUB'
#!/usr/bin/env bash
echo '{"auth":{"status":"logged-out"}}'
STUB
chmod +x "$SANDBOX/bin/gh"

INSTALL_PREFIX="$SANDBOX/npm-prefix"
INSTALL_HOME="$SANDBOX/install-home"
INSTALL_LOG="$SANDBOX/npm-install.log"
mkdir -p "$INSTALL_HOME/.local/bin"
for user_file in bakit bakit.cmd bakit.ps1; do
  printf 'user-owned-%s\n' "$user_file" > "$INSTALL_HOME/.local/bin/$user_file"
done

HOME="$INSTALL_HOME" npm install --foreground-scripts --global --prefix "$INSTALL_PREFIX" "$TARBALL_PATH" >"$INSTALL_LOG" 2>&1 && RC=0 || RC=$?
if [ "$RC" -ne 0 ]; then
  fail "disposable global npm install failed"
elif [ ! -x "$INSTALL_PREFIX/bin/bakit" ]; then
  fail "global npm did not create the bakit executable"
elif [ -e "$INSTALL_PREFIX/bin/ba-kit" ]; then
  fail "global npm created forbidden legacy ba-kit executable"
else
  pass "global npm exposes only the bakit executable"
fi

if grep -q 'PATH CONFLICT DETECTED' "$INSTALL_LOG" && grep -q 'Preserved existing user-owned file' "$INSTALL_LOG"; then
  pass "postinstall warns about user-owned command conflicts"
else
  fail "postinstall did not emit an actionable conflict warning: $(cat "$INSTALL_LOG")"
fi

for user_file in bakit bakit.cmd bakit.ps1; do
  if [ "$(cat "$INSTALL_HOME/.local/bin/$user_file")" = "user-owned-$user_file" ]; then
    pass "postinstall preserves user-owned $user_file"
  else
    fail "postinstall modified user-owned $user_file"
  fi
done

HELP_OUTPUT=$(HOME="$SANDBOX/home" PATH="$SANDBOX/bin:$PATH" BA_KIT_TESTING=1 "$INSTALL_PREFIX/bin/bakit" help 2>&1) || true
if echo "$HELP_OUTPUT" | grep -qE 'install|update|doctor|version|uninstall'; then
  if echo "$HELP_OUTPUT" | grep -q 'ba-kit install'; then
    fail "packaged CLI help still shows legacy ba-kit command: $HELP_OUTPUT"
  else
    pass "packaged bakit help shows manager commands"
  fi
else
  fail "packaged CLI help missing commands: $HELP_OUTPUT"
fi

for stale_command in install update doctor version uninstall; do
  if "$INSTALL_PREFIX/bin/ba-kit" "$stale_command" >/dev/null 2>&1; then
    fail "legacy ba-kit unexpectedly accepted $stale_command"
  else
    pass "legacy ba-kit rejects $stale_command"
  fi
done

# --- Test 6: version command ---
echo "--- Test 6: packaged CLI version ---"
VER_OUTPUT=$(HOME="$SANDBOX/home" PATH="$SANDBOX/bin:$PATH" BA_KIT_TESTING=1 "$INSTALL_PREFIX/bin/bakit" version 2>&1) || true
if echo "$VER_OUTPUT" | grep -q "BA-kit CLI"; then
  pass "packaged CLI version works"
else
  fail "packaged CLI version failed: $VER_OUTPUT"
fi

mkdir -p "$SANDBOX/home/.config/ba-kit"
printf '{"schema_version":1,"interaction_language":"en"}\n' > "$SANDBOX/home/.config/ba-kit/config.json"
HELP_OUTPUT=$(HOME="$SANDBOX/home" PATH="$SANDBOX/bin:$PATH" BA_KIT_TESTING=1 "$INSTALL_PREFIX/bin/bakit" help 2>&1) || true
if echo "$HELP_OUTPUT" | grep -q "Supported runtimes"; then
  pass "packaged CLI loads persisted English preference"
else
  fail "packaged CLI did not load English preference: $HELP_OUTPUT"
fi

rm -rf "$SANDBOX"

# --- Test 7: CLI_VERSION matches package.json ---
echo "--- Test 7: CLI_VERSION matches package.json ---"
CLI_VERSION=$(grep '^CLI_VERSION=' "$EXTRACTED/bakit" | head -1 | sed 's/CLI_VERSION="\([^"]*\)".*/\1/')
PKG_VERSION=$(node -e "console.log(require(process.argv[1]).version)" "$EXTRACTED/package.json")

if [ "$CLI_VERSION" = "$PKG_VERSION" ]; then
  pass "CLI_VERSION ($CLI_VERSION) == package.json ($PKG_VERSION)"
else
  fail "CLI_VERSION ($CLI_VERSION) != package.json ($PKG_VERSION)"
fi

echo ""
echo "=== Phase 05 Packaged CLI Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$FAIL"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SMOKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_REPO="$(cd "$SMOKE_DIR/../.." && pwd)"
LIFECYCLE="$CLI_REPO/lib/runtime-lifecycle.js"
FIXTURE_DIR="$(mktemp -d)"
export FIXTURE_DIR

# shellcheck source=../lib/release-fixture.sh
source "$SMOKE_DIR/lib/release-fixture.sh"

PASS=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $*"; }
die() { echo "  FAIL: $*" >&2; exit 1; }
cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

generate_native_standard_fixture >/dev/null
ARCHIVE="$FIXTURE_DIR/ba-kit-native-v1.4.0.tar.gz"

INSPECT_OUTPUT=$(node "$CLI_REPO/lib/archive-helper.js" inspect \
  --archive "$ARCHIVE" --profile standard --cli-version 1.4.0 \
  --runtimes claude,codex,agy --selected-product ba-kit --selected-version v1.4.0)
[ "$(printf '%s' "$INSPECT_OUTPUT" | jq -r '.ok')" = true ] || die "native fixture failed archive inspection"
[ "$(printf '%s' "$INSPECT_OUTPUT" | jq '.manifest.runtime_components | length')" = 16 ] || die "native fixture does not contain 16 runtime components"

new_case() {
  CASE_DIR="$(mktemp -d "$FIXTURE_DIR/case.XXXXXX")"
  HOME_DIR="$CASE_DIR/home"
  EXTRACT_DIR="$CASE_DIR/extract"
  mkdir -p "$HOME_DIR" "$EXTRACT_DIR"
  tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"
}

install_native() {
  local runtimes="$1"
  node "$LIFECYCLE" install \
    --home "$HOME_DIR" --extract "$EXTRACT_DIR" --runtimes "$runtimes" \
    --profile standard --product_id ba-kit --product_name BA-kit --version 1.4.0
}

state_file() {
  printf '%s/.local/share/ba-kit/runtime-state/%s/state.json' "$HOME_DIR" "$1"
}

refresh_release_manifest() {
  node - "$EXTRACT_DIR" <<'NODE'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = process.argv[2];
const result = {};
function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(file);
    else if (entry.name !== 'release-manifest.json') {
      const key = './' + path.relative(root, file).split(path.sep).join('/');
      result[key] = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
    }
  }
}
walk(root);
fs.writeFileSync(path.join(root, 'release-manifest.json'), JSON.stringify(result, null, 2) + '\n');
NODE
}

echo "=== PHASE 05: Native Runtime Lifecycle ==="

echo "--- Fresh install and idempotent reinstall ---"
new_case
mkdir -p "$HOME_DIR/.claude" "$HOME_DIR/.codex"
cat > "$HOME_DIR/.claude/settings.json" <<'JSON'
{"theme":"dark","hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"echo user"}]}]}}
JSON
printf 'model = "gpt-5"\n' > "$HOME_DIR/.codex/config.toml"
cat > "$HOME_DIR/.codex/hooks.json" <<'JSON'
{"owner":"user","hooks":{"SessionStart":[{"type":"command","command":"echo user"}]}}
JSON
install_native claude,codex,agy
CLAUDE_SETTINGS="$HOME_DIR/.claude/settings.json"
jq '(.hooks.PreToolUse[0].hooks) += [{"type":"command","command":"echo mixed-user-hook"}]' \
  "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp"
mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"
for runtime in claude codex agy; do
  [ "$(jq -r '.schema_version' "$(state_file "$runtime")")" = 3 ] || die "$runtime state is not schema v3"
  [ -f "$(jq -r '.targets[0]' "$(state_file "$runtime")")/ba-kit/RECOVERY_REQUIRED.json" ] || die "$runtime compatibility barrier missing"
done
[ -f "$HOME_DIR/.claude/agents/ba-reviewer.md" ] || die "Claude native agent missing"
[ -f "$HOME_DIR/.codex/agents/ba-reviewer.toml" ] || die "Codex native agent missing"
[ -f "$HOME_DIR/.gemini/antigravity/knowledge/ba-kit-workflow/metadata.json" ] || die "Antigravity Knowledge Item missing"
DOCTOR_OUTPUT=$(node "$LIFECYCLE" doctor --home "$HOME_DIR" --runtimes claude,codex,agy 2>&1) || die "doctor failed after fresh install: $DOCTOR_OUTPUT"
[ "$(printf '%s' "$DOCTOR_OUTPUT" | grep -c '\[OK\]')" -eq 3 ] || die "doctor did not validate all runtimes"
install_native claude,codex,agy
[ "$(jq '[.hooks.PreToolUse[] | select(.hooks[0].ba_kit_managed == true)] | length' "$HOME_DIR/.claude/settings.json")" = 1 ] || die "Claude registration duplicated"
[ "$(jq '[.hooks.PreToolUse[].hooks[] | select(.command == "echo mixed-user-hook")] | length' "$HOME_DIR/.claude/settings.json")" = 1 ] || die "Claude reinstall removed mixed user hook"
[ "$(grep -c '^# >>> BA-kit managed agents >>>$' "$HOME_DIR/.codex/config.toml")" = 1 ] || die "Codex registration duplicated"
[ "$(jq -r '.theme' "$HOME_DIR/.claude/settings.json")" = dark ] || die "Claude user config lost"
[ "$(jq -r '.owner' "$HOME_DIR/.codex/hooks.json")" = user ] || die "Codex user config lost"
pass "fresh/reinstall claude+codex+agy"

echo "--- Antigravity multi-home install ---"
new_case
mkdir -p "$HOME_DIR/.gemini/antigravity-cli"
install_native agy
[ "$(jq '.targets | length' "$(state_file agy)")" = 2 ] || die "canonical and detected Antigravity targets not consolidated"
for target in antigravity antigravity-cli; do
  [ -f "$HOME_DIR/.gemini/$target/skills/ba-review/SKILL.md" ] || die "$target payload missing"
  [ -f "$HOME_DIR/.gemini/$target/ba-kit/state.json" ] || die "$target state projection missing"
done
grep -q '~/.gemini/antigravity/ba-kit/core/contract.yaml' "$HOME_DIR/.gemini/antigravity-cli/skills/ba-start/SKILL.md" || die "Antigravity CLI skill reference changed unexpectedly"
[ -f "$HOME_DIR/.gemini/antigravity/ba-kit/core/contract.yaml" ] || die "canonical Antigravity support contract missing"
[ -f "$HOME_DIR/.gemini/antigravity/ba-kit/scripts/validate-review-receipt.py" ] || die "canonical Antigravity validator missing"
[ "$(python3 "$HOME_DIR/.gemini/antigravity/ba-kit/scripts/validate-review-receipt.py")" = validator-ready ] || die "canonical Antigravity validator is not executable"
pass "multi-home Antigravity targets"

echo "--- Schema-v2 and legacy migration ---"
new_case
mkdir -p "$HOME_DIR/.claude/skills/ba-review" "$(dirname "$(state_file claude)")"
printf '# schema2 old\n' > "$HOME_DIR/.claude/skills/ba-review/SKILL.md"
OLD_HASH=$(shasum -a 256 "$HOME_DIR/.claude/skills/ba-review/SKILL.md" | awk '{print $1}')
jq -n --arg hash "$OLD_HASH" '{schema_version:2,product_id:"ba-kit",product_name:"BA-kit",profile:"standard",version:"1.3.0",status:"installed",files:{"./.claude/skills/ba-review/SKILL.md":{source_sha256:$hash}}}' > "$(state_file claude)"
install_native claude
[ "$(jq -r '.schema_version' "$(state_file claude)")" = 3 ] || die "schema-v2 state not migrated"
grep -q '^# review skill$' "$HOME_DIR/.claude/skills/ba-review/SKILL.md" || die "schema-v2 managed file not upgraded"

new_case
mkdir -p "$HOME_DIR/.claude/skills/ba-review" "$HOME_DIR/.claude/ba-kit"
printf '# legacy old\n' > "$HOME_DIR/.claude/skills/ba-review/SKILL.md"
OLD_HASH=$(shasum -a 256 "$HOME_DIR/.claude/skills/ba-review/SKILL.md" | awk '{print $1}')
jq -n --arg hash "$OLD_HASH" '{"./.claude/skills/ba-review/SKILL.md":$hash}' > "$HOME_DIR/.claude/ba-kit/release-manifest.json"
install_native claude
[ "$(jq -r '.schema_version' "$(state_file claude)")" = 3 ] || die "legacy state not migrated"
grep -q '^# review skill$' "$HOME_DIR/.claude/skills/ba-review/SKILL.md" || die "legacy managed file not upgraded"
pass "schema-v2 and legacy migration"

echo "--- Compatibility barrier and registration rollback ---"
new_case
mkdir -p "$HOME_DIR/.claude/ba-kit"
printf '{"status":"cli-upgrade-required"}\n' > "$HOME_DIR/.claude/ba-kit/RECOVERY_REQUIRED.json"
if install_native claude >/dev/null 2>&1; then die "barrier accepted without valid v3 state"; fi
[ ! -e "$HOME_DIR/.claude/agents/ba-reviewer.md" ] || die "barrier failure mutated runtime"

new_case
mkdir -p "$HOME_DIR/.claude" "$HOME_DIR/.codex"
printf '{"theme":"light","hooks":{}}\n' > "$HOME_DIR/.claude/settings.json"
printf 'model = "user-model"\n' > "$HOME_DIR/.codex/config.toml"
if BA_KIT_TEST_FAIL_REGISTRATION=codex install_native claude,codex >/dev/null 2>&1; then
  die "forced registration failure unexpectedly succeeded"
fi
[ ! -e "$HOME_DIR/.claude/agents/ba-reviewer.md" ] || die "multi-runtime rollback left Claude payload"
[ "$(jq -r '.theme' "$HOME_DIR/.claude/settings.json")" = light ] || die "rollback changed Claude user config"
grep -q 'user-model' "$HOME_DIR/.codex/config.toml" || die "rollback changed Codex user config"
[ ! -e "$(state_file claude)" ] && [ ! -e "$(state_file codex)" ] || die "rollback left canonical state"
pass "barrier and forced registration rollback"

echo "--- Interrupted transaction recovery ---"
new_case
DEST="$HOME_DIR/.claude/templates/frd.md"
TX="$HOME_DIR/.local/share/ba-kit/transactions/interrupted"
SNAP="$TX/snapshot/files/original"
mkdir -p "$(dirname "$DEST")" "$(dirname "$SNAP")"
printf 'partial mutation\n' > "$DEST"
printf 'user original\n' > "$SNAP"
jq -n --arg file "$DEST" --arg snapshot "$SNAP" '{schema_version:1,status:"in-progress",runtime:"claude",records:[{file:$file,kind:"file",snapshot:$snapshot}]}' > "$TX/journal.json"
install_native claude
grep -q '^user original$' "$DEST" || die "interrupted transaction was not restored before install"
[ ! -e "$TX" ] || die "recovered transaction journal not removed"
pass "interrupted journal recovery"

echo "--- Retirement of removed payload files ---"
new_case
install_native claude
printf 'user changed retired file\n' > "$HOME_DIR/.claude/templates/retire-modified.md"
rm "$EXTRACT_DIR/.claude/templates/retire-clean.md" "$EXTRACT_DIR/.claude/templates/retire-modified.md"
refresh_release_manifest
install_native claude
[ ! -e "$HOME_DIR/.claude/templates/retire-clean.md" ] || die "unmodified retired file not removed"
grep -q 'user changed' "$HOME_DIR/.claude/templates/retire-modified.md" || die "modified retired file not preserved"
MOD_DEST="$HOME_DIR/.claude/templates/retire-modified.md"
[ "$(jq -r --arg dest "$MOD_DEST" '.files["./.claude/templates/retire-modified.md"].destinations[$dest].status' "$(state_file claude)")" = preserved-retired ] || die "retired modified status missing"
pass "retirement preserves modified and removes unchanged"

echo "--- Malformed config, state, and journal containment ---"
new_case
mkdir -p "$HOME_DIR/.claude"
printf '{not-json\n' > "$HOME_DIR/.claude/settings.json"
if install_native claude >/dev/null 2>&1; then die "malformed user config accepted"; fi
grep -q '^{not-json$' "$HOME_DIR/.claude/settings.json" || die "malformed user config changed"
[ ! -e "$HOME_DIR/.claude/agents/ba-reviewer.md" ] || die "malformed config failure left payload"

new_case
mkdir -p "$(dirname "$(state_file claude)")" "$HOME_DIR/.claude/ba-kit"
printf '{bad-state\n' > "$(state_file claude)"
printf '{"status":"cli-upgrade-required"}\n' > "$HOME_DIR/.claude/ba-kit/RECOVERY_REQUIRED.json"
if install_native claude >/dev/null 2>&1; then die "malformed canonical state accepted"; fi
[ ! -e "$HOME_DIR/.claude/agents/ba-reviewer.md" ] || die "malformed state failure mutated runtime"

new_case
mkdir -p "$HOME_DIR/.local/share/ba-kit/transactions/bad"
printf '{bad-journal\n' > "$HOME_DIR/.local/share/ba-kit/transactions/bad/journal.json"
if install_native claude >/dev/null 2>&1; then die "malformed recovery journal accepted"; fi
[ ! -e "$HOME_DIR/.claude/agents/ba-reviewer.md" ] || die "malformed journal failure mutated runtime"

new_case
mkdir -p "$HOME_DIR/.claude/ba-kit"
printf 'DO-NOT-CHANGE\n' > "$HOME_DIR/metadata-sentinel"
ln -s "$HOME_DIR/metadata-sentinel" "$HOME_DIR/.claude/ba-kit/VERSION"
if install_native claude >/dev/null 2>&1; then die "symlinked runtime metadata was accepted"; fi
grep -q '^DO-NOT-CHANGE$' "$HOME_DIR/metadata-sentinel" || die "runtime metadata symlink overwrote user file"
[ -L "$HOME_DIR/.claude/ba-kit/VERSION" ] || die "failed metadata install mutated user symlink"
pass "malformed inputs fail closed"

echo "--- Doctor failure modes ---"
new_case
install_native claude
printf 'tampered\n' > "$HOME_DIR/.claude/agents/ba-reviewer.md"
set +e
DOCTOR_OUTPUT=$(node "$LIFECYCLE" doctor --home "$HOME_DIR" --runtimes claude 2>&1)
DOCTOR_RC=$?
set -e
[ "$DOCTOR_RC" -ne 0 ] && printf '%s' "$DOCTOR_OUTPUT" | grep -q '\[FAIL\]' || die "doctor missed tampered required file"

new_case
install_native codex
printf 'model = "user-model"\n' > "$HOME_DIR/.codex/config.toml"
set +e
DOCTOR_OUTPUT=$(node "$LIFECYCLE" doctor --home "$HOME_DIR" --runtimes codex 2>&1)
DOCTOR_RC=$?
set -e
[ "$DOCTOR_RC" -ne 0 ] && printf '%s' "$DOCTOR_OUTPUT" | grep -q '\[FAIL\]' || die "doctor missed missing Codex registration"

new_case
mkdir -p "$HOME_DIR/.local/share/ba-kit/transactions/pending"
printf '{"status":"in-progress","runtime":"claude","records":[]}\n' > "$HOME_DIR/.local/share/ba-kit/transactions/pending/journal.json"
set +e
DOCTOR_OUTPUT=$(node "$LIFECYCLE" doctor --home "$HOME_DIR" --runtimes claude 2>&1)
DOCTOR_RC=$?
set -e
[ "$DOCTOR_RC" -ne 0 ] && printf '%s' "$DOCTOR_OUTPUT" | grep -q '\[RECOVERY\]' || die "doctor missed pending transaction"
pass "doctor reports tamper and recovery failures"

echo "--- Uninstall preserves user config and modified managed files ---"
new_case
mkdir -p "$HOME_DIR/.claude" "$HOME_DIR/.codex"
cat > "$HOME_DIR/.claude/settings.json" <<'JSON'
{"theme":"dark","hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"echo user"}]}]}}
JSON
printf 'model = "user-model"\n' > "$HOME_DIR/.codex/config.toml"
cat > "$HOME_DIR/.codex/hooks.json" <<'JSON'
{"owner":"user","hooks":{"SessionStart":[{"type":"command","command":"echo user"}]}}
JSON
install_native claude,codex
jq '(.hooks.PreToolUse[0].hooks) += [{"type":"command","command":"echo mixed-user-hook"}]' \
  "$HOME_DIR/.claude/settings.json" > "$HOME_DIR/.claude/settings.json.tmp"
mv "$HOME_DIR/.claude/settings.json.tmp" "$HOME_DIR/.claude/settings.json"
printf 'user modified managed skill\n' > "$HOME_DIR/.claude/skills/ba-review/SKILL.md"
node "$LIFECYCLE" uninstall --home "$HOME_DIR" --runtimes claude,codex
[ "$(jq -r '.theme' "$HOME_DIR/.claude/settings.json")" = dark ] || die "uninstall removed Claude user config"
[ "$(jq '.hooks.UserPromptSubmit | length' "$HOME_DIR/.claude/settings.json")" = 1 ] || die "uninstall removed Claude user hook"
[ "$(jq '[.hooks.PreToolUse[]? | select(.hooks[0].ba_kit_managed == true)] | length' "$HOME_DIR/.claude/settings.json")" = 0 ] || die "uninstall retained Claude managed hook"
[ "$(jq '[.hooks.PreToolUse[]?.hooks[]? | select(.command == "echo mixed-user-hook")] | length' "$HOME_DIR/.claude/settings.json")" = 1 ] || die "uninstall removed mixed Claude user hook"
grep -q 'user-model' "$HOME_DIR/.codex/config.toml" || die "uninstall removed Codex user config"
! grep -q 'BA-kit managed agents' "$HOME_DIR/.codex/config.toml" || die "uninstall retained Codex managed block"
[ "$(jq -r '.owner' "$HOME_DIR/.codex/hooks.json")" = user ] || die "uninstall removed Codex hook config"
grep -q 'user modified' "$HOME_DIR/.claude/skills/ba-review/SKILL.md" || die "uninstall removed modified managed file"
[ ! -e "$HOME_DIR/.codex/skills/ba-review/SKILL.md" ] || die "uninstall retained unchanged managed file"
[ "$(jq -r '.status' "$(state_file claude)")" = uninstalled-with-preserved-files ] || die "uninstall tombstone missing"
pass "uninstall registration cleanup and config preservation"

echo "=== Native Runtime Lifecycle Results: $PASS passed ==="

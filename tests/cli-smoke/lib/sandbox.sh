#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# BA-kit CLI smoke test — sandbox helpers
# ============================================================
# Creates isolated HOME/PATH for each test case.

SANDBOX_DIR=""

sandbox_setup() {
  SANDBOX_DIR="$(mktemp -d)"
  mkdir -p "$SANDBOX_DIR/home/.claude/skills"
  mkdir -p "$SANDBOX_DIR/home/.claude/agents"
  mkdir -p "$SANDBOX_DIR/home/.claude/hooks"
  mkdir -p "$SANDBOX_DIR/home/.claude/settings.json.orig"
  mkdir -p "$SANDBOX_DIR/home/.codex"
  mkdir -p "$SANDBOX_DIR/home/.gemini/config"
  mkdir -p "$SANDBOX_DIR/home/.local/bin"
  mkdir -p "$SANDBOX_DIR/home/.local/share"
  mkdir -p "$SANDBOX_DIR/bin"
  mkdir -p "$SANDBOX_DIR/prefix"

  # Seed unrelated content that must survive
  echo '{"hooks":{}}' > "$SANDBOX_DIR/home/.claude/settings.json"
  mkdir -p "$SANDBOX_DIR/home/.claude/skills/unrelated-skill"
  echo "unrelated" > "$SANDBOX_DIR/home/.claude/skills/unrelated-skill/SKILL.md"

  export HOME="$SANDBOX_DIR/home"
  cd "$HOME"
  export PATH="$SANDBOX_DIR/bin:$PATH"
  export XDG_CONFIG_HOME=""
  export GH_CONFIG_DIR="$SANDBOX_DIR/home/.config/gh"

  mkdir -p "$GH_CONFIG_DIR"
  echo "github.com:" > "$GH_CONFIG_DIR/hosts.yml"
  echo "  user: test-user" >> "$GH_CONFIG_DIR/hosts.yml"
  echo "  oauth_token: ghp_test00000000000000000000000000000000" >> "$GH_CONFIG_DIR/hosts.yml"

  # Default: logged-in
  export GH_AUTH_MODE="${GH_AUTH_MODE:-logged-in}"
  export GH_ACCESS_REPOS="${GH_ACCESS_REPOS:-bakit-org/bakit,bakit-org/ba-kit-solo-pro}"
  export CURL_MODE="${CURL_MODE:-ok}"
  export BA_KIT_TESTING="${BA_KIT_TESTING:-1}"
  export CLI_VERSION="1.2.9"
}

sandbox_teardown() {
  cd /tmp 2>/dev/null || true
  [ -n "$SANDBOX_DIR" ] && rm -rf "$SANDBOX_DIR"
}

snapshot_home() {
  local label="${1:-snapshot}"
  local snap_file="$SANDBOX_DIR/snapshot-${label}.txt"
  (cd "$HOME" && find . -type f | sort > "$snap_file")
  sha256 "$snap_file"
}

verify_home_unchanged() {
  local label="${1:-snapshot}" new
  new=$(snapshot_home "${label}-after")
  local old
  old=$(cat "$SANDBOX_DIR/snapshot-${label}.txt.sha" 2>/dev/null || echo "")
  if [ -n "$old" ] && [ "$new" != "$old" ]; then
    echo "FAIL: HOME changed during read-only operation"
    return 1
  fi
  echo "$new" > "$SANDBOX_DIR/snapshot-${label}.txt.sha"
}

# Portable sha256
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# BA-kit CLI smoke test — release fixture generator
# ============================================================
# Creates a minimal synthetic release archive for testing.

FIXTURE_DIR="${FIXTURE_DIR:-/tmp/ba-kit-fixtures}"

generate_public_solo_fixture() {
  mkdir -p "$FIXTURE_DIR"
  local work="$FIXTURE_DIR/solo-build"
  rm -rf "$work" && mkdir -p "$work/.claude/skills/ba-do"
  mkdir -p "$work/.claude/templates" "$work/ba-kit/core"

  for sk in ba-do ba-start ba-impact ba-next brainstorm; do
    mkdir -p "$work/.claude/skills/$sk"
    echo "# $sk skill" > "$work/.claude/skills/$sk/SKILL.md"
  done
  mkdir -p "$work/.claude/skills/ba-start/steps"
  echo "# template" > "$work/.claude/templates/example.md"
  echo "# core" > "$work/ba-kit/core/contract.yaml"

  cat > "$work/manifest.json" << 'MANIFEST'
{
  "name": "BA-kit Solo Basic",
  "product_id": "ba-kit-solo-basic",
  "profile": "solo-basic",
  "version": "0.0.0",
  "min_cli_version": "1.2.9",
  "release_date": "2026-07-15"
}
MANIFEST

  # Generate release-manifest.json
  cd "$work"
  {
    echo "{"
    local first=true
    for f in $(find . -type f ! -name 'release-manifest.json' | sort); do
      if $first; then first=false; else echo ","; fi
      local h
      h=$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}' || sha256sum "$f" | awk '{print $1}')
      printf '  "%s": "%s"' "$f" "$h"
    done
    echo ""
    echo "}"
  } > release-manifest.json

  local archive="$FIXTURE_DIR/ba-kit-v0.0.0.tar.gz"
  tar -czf "$archive" .
  shasum -a 256 "$archive" 2>/dev/null | awk '{print $1}' > "${archive}.sha256" || \
    sha256sum "$archive" | awk '{print $1}' > "${archive}.sha256"

  rm -rf "$work"
  echo "  Fixture created: $archive"
}

generate_standard_fixture() {
  mkdir -p "$FIXTURE_DIR"
  local work="$FIXTURE_DIR/standard-build"
  rm -rf "$work" && mkdir -p "$work/.claude/skills/ba-do" "$work/.claude/templates" "$work/ba-kit/core"

  echo "# ba-kit skill" > "$work/.claude/skills/ba-do/SKILL.md"
  echo "# template" > "$work/.claude/templates/frd-template.md"
  echo "# core" > "$work/ba-kit/core/contract.yaml"

  cat > "$work/manifest.json" << 'MANIFEST'
{
  "name": "ba-kit",
  "product_id": "ba-kit",
  "profile": "standard",
  "version": "1.0.0",
  "min_cli_version": "1.0.0",
  "release_date": "2026-01-01"
}
MANIFEST

  cd "$work"
  {
    echo "{"
    local first=true
    for f in $(find . -type f ! -name 'release-manifest.json' | sort); do
      if $first; then first=false; else echo ","; fi
      local h
      h=$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}' || sha256sum "$f" | awk '{print $1}')
      printf '  "%s": "%s"' "$f" "$h"
    done
    echo ""
    echo "}"
  } > release-manifest.json

  local archive="$FIXTURE_DIR/ba-kit-v1.0.0.tar.gz"
  tar -czf "$archive" .
  shasum -a 256 "$archive" 2>/dev/null | awk '{print $1}' > "${archive}.sha256" || \
    sha256sum "$archive" | awk '{print $1}' > "${archive}.sha256"

  rm -rf "$work"
  echo "  Fixture created: $archive"
}

generate_legacy_standard_fixture() {
  mkdir -p "$FIXTURE_DIR"
  local work="$FIXTURE_DIR/legacy-standard-build"
  rm -rf "$work" && mkdir -p "$work/.claude/skills" "$work/ba-kit/core"

  echo "# legacy skill" > "$work/.claude/skills/ba-client.md"

  # Legacy: no product_id/profile fields
  cat > "$work/manifest.json" << 'MANIFEST'
{
  "name": "ba-kit",
  "version": "0.9.0",
  "min_cli_version": "0.9.0",
  "release_date": "2025-01-01"
}
MANIFEST

  cd "$work"
  {
    echo "{"
    local first=true
    for f in $(find . -type f ! -name 'release-manifest.json' | sort); do
      if $first; then first=false; else echo ","; fi
      local h
      h=$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}' || sha256sum "$f" | awk '{print $1}')
      printf '  "%s": "%s"' "$f" "$h"
    done
    echo ""
    echo "}"
  } > release-manifest.json

  local archive="$FIXTURE_DIR/ba-kit-v0.9.0.tar.gz"
  tar -czf "$archive" .
  shasum -a 256 "$archive" 2>/dev/null | awk '{print $1}' > "${archive}.sha256" || \
    sha256sum "$archive" | awk '{print $1}' > "${archive}.sha256"

  rm -rf "$work"
  echo "  Fixture created: $archive"
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  generate_public_solo_fixture
  generate_standard_fixture
  generate_legacy_standard_fixture
fi

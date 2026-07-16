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

generate_native_standard_fixture() {
  mkdir -p "$FIXTURE_DIR"
  local work="$FIXTURE_DIR/native-standard-build"
  rm -rf "$work"

  mkdir -p \
    "$work/.claude/skills/ba-review" "$work/.claude/agents" \
    "$work/.claude/rules" "$work/.claude/templates" "$work/.claude/hooks" \
    "$work/.codex/skills/ba-review" "$work/.codex/agents" \
    "$work/.codex/templates" "$work/.codex/hooks" "$work/.codex/ba-kit" \
    "$work/.antigravity/skills/ba-review" "$work/.antigravity/skills/ba-start" "$work/.antigravity/templates" \
    "$work/.antigravity/core" "$work/.antigravity/guardrails" \
    "$work/.antigravity/knowledge/ba-kit-workflow" "$work/ba-kit/core"

  printf '# review skill\n' > "$work/.claude/skills/ba-review/SKILL.md"
  printf '# reviewer\n' > "$work/.claude/agents/ba-reviewer.md"
  printf '# quality\n' > "$work/.claude/rules/quality.md"
  printf '# template\n' > "$work/.claude/templates/frd.md"
  printf '# retire clean\n' > "$work/.claude/templates/retire-clean.md"
  printf '# retire modified\n' > "$work/.claude/templates/retire-modified.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$work/.claude/hooks/guardrail-write.sh"
  cat > "$work/.claude/hooks/registration.json" << 'JSON'
{"managed_events":{"PreToolUse":["guardrail-write.sh"]}}
JSON

  printf '# review skill\n' > "$work/.codex/skills/ba-review/SKILL.md"
  printf 'name = "ba-reviewer"\n' > "$work/.codex/agents/ba-reviewer.toml"
  cat > "$work/.codex/agents/registration.json" << 'JSON'
{"canonical_agents":["ba-reviewer"],"compatibility_aliases":{}}
JSON
  printf '# template\n' > "$work/.codex/templates/frd.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$work/.codex/hooks/guardrail-write.sh"
  cat > "$work/.codex/hooks/registration.json" << 'JSON'
{"hooks":{"PreToolUse":[{"type":"command","command":"bash {hooks_root}/guardrail-write.sh"}]}}
JSON
  printf '{"contract_version":2}\n' > "$work/.codex/ba-kit/contract.yaml"

  printf '# review skill\n' > "$work/.antigravity/skills/ba-review/SKILL.md"
  printf 'Read ~/.gemini/antigravity/ba-kit/core/contract.yaml and run ~/.gemini/antigravity/ba-kit/scripts/validate-review-receipt.py\n' > "$work/.antigravity/skills/ba-start/SKILL.md"
  printf '# template\n' > "$work/.antigravity/templates/frd.md"
  printf '{"contract_version":2}\n' > "$work/.antigravity/core/contract.yaml"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$work/.antigravity/guardrails/check-write-scope.sh"
  printf '#!/usr/bin/env python3\nprint("validator-ready")\n' > "$work/.antigravity/guardrails/validate-review-receipt.py"
  cat > "$work/.antigravity/knowledge/ba-kit-workflow/metadata.json" << 'JSON'
{"name":"BA-kit Workflow","managed_by":"ba-kit"}
JSON

  printf '{"contract_version":2}\n' > "$work/ba-kit/core/contract.yaml"

  cat > "$work/manifest.json" << 'MANIFEST'
{
  "name": "BA-kit",
  "product_id": "ba-kit",
  "profile": "standard",
  "version": "1.4.0",
  "min_cli_version": "1.4.0",
  "release_date": "2026-07-16",
  "runtime_payload_schema": 2,
  "runtime_components": [
    {"id":"claude-skills","runtime":"claude","source_prefix":".claude/skills/","destination_key":"skills_root","registration_handler":"managed-tree","required":true,"retirement_policy":"remove-if-unmodified"},
    {"id":"claude-agents","runtime":"claude","source_prefix":".claude/agents/","destination_key":"agents_root","registration_handler":"managed-tree","required":true,"retirement_policy":"remove-if-unmodified"},
    {"id":"claude-rules","runtime":"claude","source_prefix":".claude/rules/","destination_key":"rules_root","registration_handler":"managed-tree","required":true,"retirement_policy":"remove-if-unmodified"},
    {"id":"claude-templates","runtime":"claude","source_prefix":".claude/templates/","destination_key":"templates_root","registration_handler":"managed-tree","required":true,"retirement_policy":"remove-if-unmodified"},
    {"id":"claude-hooks","runtime":"claude","source_prefix":".claude/hooks/","destination_key":"hooks_root","registration_handler":"claude-managed-hook-block","required":true,"retirement_policy":"remove-managed-block"},
    {"id":"codex-skills","runtime":"codex","source_prefix":".codex/skills/","destination_key":"skills_root","registration_handler":"managed-tree","required":true,"retirement_policy":"remove-if-unmodified"},
    {"id":"codex-agents","runtime":"codex","source_prefix":".codex/agents/","destination_key":"agents_root","registration_handler":"codex-managed-agent-block","required":true,"retirement_policy":"remove-if-unmodified"},
    {"id":"codex-templates","runtime":"codex","source_prefix":".codex/templates/","destination_key":"templates_root","registration_handler":"managed-tree","required":true,"retirement_policy":"remove-if-unmodified"},
    {"id":"codex-hooks","runtime":"codex","source_prefix":".codex/hooks/","destination_key":"hooks_root","registration_handler":"codex-managed-hook-block","required":true,"retirement_policy":"remove-managed-block"},
    {"id":"codex-core","runtime":"codex","source_prefix":".codex/ba-kit/","destination_key":"core_root","registration_handler":"managed-tree","required":true,"retirement_policy":"remove-if-unmodified"},
    {"id":"antigravity-skills","runtime":"antigravity","source_prefix":".antigravity/skills/","destination_key":"skills_root","registration_handler":"managed-tree","required":true,"retirement_policy":"remove-if-unmodified"},
    {"id":"antigravity-templates","runtime":"antigravity","source_prefix":".antigravity/templates/","destination_key":"templates_root","registration_handler":"managed-tree","required":true,"retirement_policy":"remove-if-unmodified"},
    {"id":"antigravity-core","runtime":"antigravity","source_prefix":".antigravity/core/","destination_key":"core_root","registration_handler":"managed-tree","required":true,"retirement_policy":"remove-if-unmodified"},
    {"id":"antigravity-guardrails","runtime":"antigravity","source_prefix":".antigravity/guardrails/","destination_key":"guardrails_root","registration_handler":"managed-tree","required":true,"retirement_policy":"remove-if-unmodified"},
    {"id":"antigravity-knowledge","runtime":"antigravity","source_prefix":".antigravity/knowledge/ba-kit-workflow/","destination_key":"knowledge_root","registration_handler":"antigravity-managed-knowledge-entry","required":true,"retirement_policy":"remove-managed-entry"},
    {"id":"shared-controller","runtime":"shared","source_prefix":"ba-kit/","destination_key":"shared_root","registration_handler":"managed-tree","required":true,"retirement_policy":"remove-if-unmodified"}
  ]
}
MANIFEST

  cd "$work"
  {
    echo "{"
    local first=true
    while IFS= read -r f; do
      if $first; then first=false; else echo ","; fi
      local h
      h=$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}' || sha256sum "$f" | awk '{print $1}')
      printf '  "%s": "%s"' "$f" "$h"
    done < <(find . -type f ! -name 'release-manifest.json' | sort)
    echo ""
    echo "}"
  } > release-manifest.json

  local archive="$FIXTURE_DIR/ba-kit-native-v1.4.0.tar.gz"
  COPYFILE_DISABLE=1 tar -czf "$archive" .
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
  generate_native_standard_fixture
fi

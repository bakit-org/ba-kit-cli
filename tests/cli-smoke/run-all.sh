#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# BA-kit CLI smoke test — run all phase cases
# ============================================================
# Platform-aware: skips cases that require unavailable tooling
# (e.g. jq on minimal Windows) rather than failing hard.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAILED=0
SKIPPED=0
TOTAL=0
CASES=()

# Detect platform
OS="$(uname -s)"
IS_WINDOWS="${BA_KIT_WINDOWS:-0}"

if [ $# -gt 0 ]; then
  CASES=("$@")
else
  for f in "$SCRIPT_DIR/cases"/*.sh; do
    [ -x "$f" ] && [ -f "$f" ] || continue
    CASES+=("$f")
  done
fi

# Check prerequisites once
has_jq() { command -v jq >/dev/null 2>&1; }
has_node() { command -v node >/dev/null 2>&1; }

for case in "${CASES[@]}"; do
  TOTAL=$((TOTAL + 1))
  case_name="$(basename "$case")"

  # Skip packaged smoke if npm pack unavailable
  if echo "$case_name" | grep -q "packaged" && ! has_node; then
    echo "SKIP: $case_name (node unavailable)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo ""
  echo "==========================================="
  echo "Running: $case_name ($OS)"
  echo "==========================================="
  if bash "$case"; then
    echo "PASSED: $case_name"
  else
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "==========================================="
echo "Results: $TOTAL total, $((TOTAL - FAILED - SKIPPED)) passed, $SKIPPED skipped, $FAILED failed ($OS)"
echo "==========================================="
[ "$FAILED" -eq 0 ] && echo "ALL CASES PASSED" || echo "$FAILED case(s) FAILED"
exit "$FAILED"

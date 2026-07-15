#!/usr/bin/env bash
# ============================================================
# BA-kit CLI smoke test — assertion helpers
# ============================================================

assert_eq() {
  local got="$1" expected="$2" label="${3:-}"
  if [ "$got" != "$expected" ]; then
    echo "FAIL${label:+ [$label]}: expected '$expected', got '$got'"
    return 1
  fi
  echo "  PASS: $label"
  return 0
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  if ! echo "$haystack" | grep -qF "$needle"; then
    echo "FAIL${label:+ [$label]}: expected output to contain '$needle'"
    return 1
  fi
  echo "  PASS: $label"
  return 0
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "FAIL${label:+ [$label]}: output should NOT contain '$needle'"
    return 1
  fi
  echo "  PASS: $label"
  return 0
}

# Exit code assertion
assert_exit() {
  local code="$1" expected="${2:-0}" label="${3:-}"
  if [ "$code" -ne "$expected" ]; then
    echo "FAIL${label:+ [$label]}: expected exit $expected, got $code"
    return 1
  fi
  echo "  PASS: $label"
  return 0
}

# String emptiness
assert_empty() {
  local val="$1" label="${2:-}"
  if [ -n "$val" ]; then
    echo "FAIL${label:+ [$label]}: expected empty, got: $val"
    return 1
  fi
  echo "  PASS: $label"
  return 0
}

assert_not_empty() {
  local val="$1" label="${2:-}"
  if [ -z "$val" ]; then
    echo "FAIL${label:+ [$label]}: expected non-empty value"
    return 1
  fi
  echo "  PASS: $label"
  return 0
}

# JSON value extraction and comparison
assert_json_field() {
  local json="$1" field="$2" expected="$3" label="${4:-}"
  local got
  got=$(echo "$json" | jq -r "$field" 2>/dev/null) || true
  if [ "$got" != "$expected" ]; then
    echo "FAIL${label:+ [$label]}: expected .$field='$expected', got '$got'"
    return 1
  fi
  echo "  PASS: $label"
  return 0
}

assert_json_field_contains() {
  local json="$1" field="$2" needle="$3" label="${4:-}"
  local got
  got=$(echo "$json" | jq -r "$field" 2>/dev/null) || true
  if ! echo "$got" | grep -qF "$needle"; then
    echo "FAIL${label:+ [$label]}: expected .$field to contain '$needle', got '$got'"
    return 1
  fi
  echo "  PASS: $label"
  return 0
}

# Tree snapshot: record file listing with content hashes
tree_snapshot() {
  local dir="$1" label="${2:-snapshot}"
  local snap_file="${SANDBOX_DIR:-/tmp}/tree-${label}.txt"
  (cd "$dir" && find . -type f ! -path './ba-kit/*' -exec shasum -a 256 {} \; 2>/dev/null | sort) > "$snap_file" 2>/dev/null
  echo "$snap_file"
}

# Assert two tree snapshots are identical (unrelated content preserved)
assert_tree_unchanged() {
  local before="$1" after="$2" label="${3:-}"
  if ! diff -q "$before" "$after" >/dev/null 2>&1; then
    echo "FAIL${label:+ [$label]}: tree changed during read-only operation"
    diff "$before" "$after" 2>/dev/null | head -20
    return 1
  fi
  echo "  PASS: $label"
  return 0
}

# Assert file exists with expected content
assert_file_contains() {
  local path="$1" needle="$2" label="${3:-}"
  if [ ! -f "$path" ]; then
    echo "FAIL${label:+ [$label]}: file not found: $path"
    return 1
  fi
  if ! grep -qF "$needle" "$path"; then
    echo "FAIL${label:+ [$label]}: file $path missing '$needle'"
    return 1
  fi
  echo "  PASS: $label"
  return 0
}

assert_file_not_exists() {
  local path="$1" label="${2:-}"
  if [ -f "$path" ]; then
    echo "FAIL${label:+ [$label]}: unexpected file: $path"
    return 1
  fi
  echo "  PASS: $label"
  return 0
}

# Version comparison helper — uses sort -V for semver ordering
assert_version_gte() {
  local actual="$1" minimum="$2" label="${3:-}"
  local sorted
  sorted=$(printf '%s\n%s\n' "$minimum" "$actual" | sort -V | tail -1)
  if [ "$sorted" != "$actual" ] && [ "$sorted" != "$minimum" ]; then
    echo "FAIL${label:+ [$label]}: $actual < $minimum"
    return 1
  fi
  echo "  PASS: $label"
  return 0
}

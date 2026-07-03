# Phase 1: Runtime Registry + Flag Parsing + Validation

## Context Links

- Parent plan: [plan.md](plan.md)
- Source file: `./ba-kit` (single file, entire product)

## Overview

- Priority: P0 (foundation — nothing else builds without this)
- Status: not started
- Add the runtime registry (parallel arrays), a `--runtime` flag parser/validator
  for `cmd_install`, and update the two duplicated help texts. This phase does
  **not** change the actual merge/install pipeline — `cmd_install` still only
  installs to claude at the end of this phase. It only makes the selection
  and validation logic exist and be callable, so Phase 2 can consume it.

## Key Insights

- `main()` (lines 25-63) and `usage()` (lines 65-80) duplicate the same
  command list text — both need the new `--runtime` line, or they drift.
- The runtime root formula for `claude` must reduce to exactly today's
  constants. Verify this by hand: `RUNTIME_ROOTS[0]="$HOME/.claude"` equals
  `INSTALL_DIR`; `<root>/ba-kit/VERSION` equals today's `VERSION_FILE`. Keep
  `INSTALL_DIR`/`VERSION_FILE`/`PRODUCT_FILE`/`MANIFEST_FILE`/`BACKUP_DIR`
  globals in place unchanged (other commands still use them directly until
  their own phases land) — the new registry is additive, not a replacement,
  in this phase.
- Bash 3.2: no associative arrays with `${!arr[@]}`-style fanciness beyond
  what's already used, no `${var,,}`. Follow the existing `PRODUCT_NAMES`
  pattern exactly (parallel indexed arrays + `for i in "${!ARR[@]}"` loops).

## Requirements

- New flag `--runtime <comma-list>` on `ba-kit install` only (other commands
  get flags in Phase 3/4).
- Omitted flag → default to `claude` only (unchanged behavior).
- Comma-separated list, e.g. `--runtime claude,codex,agy`. Trim whitespace
  around each item. Dedupe if user repeats a key.
- Unknown key → print a clear error listing the 3 valid keys, exit 1. Do
  this validation before any network calls (`check_prereqs`, `select_product`).
- Empty value after `--runtime` (e.g. `--runtime ""` or trailing comma
  producing an empty token) → treat as error, not as "default to claude."

## Architecture

New functions, placed after the `PRODUCT_URLS` array declaration (after
line 20) and before `# === ENTRY POINT ===`:

```bash
# Bumped by hand alongside package.json's "version" on every release —
# the bash script has no reliable path-independent way to read
# package.json at runtime (npm global installs, npx, and symlinked
# ~/.local/bin/ba-kit all resolve differently), so this is a deliberate
# duplicated constant, not a bug.
CLI_VERSION="1.2.0"

RUNTIME_KEYS=("claude" "codex" "agy")
RUNTIME_LABELS=("Claude Code" "Codex CLI" "Antigravity IDE")
RUNTIME_ROOTS=("$HOME/.claude" "$HOME/.codex" "$HOME/.gemini/config")
RUNTIME_SCOPES=("full" "skills" "skills")

runtime_index_for_key() {   # $1=key -> echoes index or returns 1
  local key="$1"
  for i in "${!RUNTIME_KEYS[@]}"; do
    if [ "${RUNTIME_KEYS[$i]}" = "$key" ]; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

runtime_root_for_key()  { local i; i=$(runtime_index_for_key "$1") && echo "${RUNTIME_ROOTS[$i]}"; }
runtime_label_for_key() { local i; i=$(runtime_index_for_key "$1") && echo "${RUNTIME_LABELS[$i]}"; }
runtime_scope_for_key() { local i; i=$(runtime_index_for_key "$1") && echo "${RUNTIME_SCOPES[$i]}"; }

# Parses "$1" (comma-list or empty) into global SELECTED_RUNTIME_KEYS array.
# Exits 1 on unknown key or empty token.
parse_runtime_flag() {
  local raw="${1:-claude}"
  SELECTED_RUNTIME_KEYS=()
  local IFS=','
  local -a tokens=($raw)
  local seen=""
  for tok in "${tokens[@]}"; do
    # trim whitespace
    tok="$(echo "$tok" | tr -d '[:space:]')"
    if [ -z "$tok" ]; then
      echo "Lỗi: --runtime chứa giá trị rỗng."
      echo "Runtime hợp lệ: ${RUNTIME_KEYS[*]}"
      exit 1
    fi
    if ! runtime_index_for_key "$tok" >/dev/null; then
      echo "Lỗi: runtime '$tok' không hợp lệ."
      echo "Runtime hợp lệ: ${RUNTIME_KEYS[*]}"
      exit 1
    fi
    case ",$seen," in
      *",$tok,"*) continue ;;
    esac
    seen="${seen:+$seen,}$tok"
    SELECTED_RUNTIME_KEYS+=("$tok")
  done
}
```

- `cmd_install`'s arg-parsing loop (lines 723-735) gets a new case:
  ```bash
  --runtime)
    target_runtime="$2"
    shift 2
    ;;
  ```
  with `local target_runtime="claude"` declared alongside
  `local target_version="latest"`. At the end of arg parsing, call
  `parse_runtime_flag "$target_runtime"`. Do this immediately after arg
  parsing, before the `echo "BA-KIT INSTALL"` banner, so validation errors
  exit before any other output.
- No other part of `cmd_install` changes in this phase — the rest of the
  function still runs exactly as before (single claude install). Phase 2
  wires `SELECTED_RUNTIME_KEYS` into the actual pipeline.

## Related Code Files

- Modify: `./ba-kit`
  - Lines 8-20 (CONFIG section) — append registry arrays + helper functions.
  - Lines 25-63 (`main()` fallback help block) — add `--runtime` line +
    one-line-per-key note under "Commands:".
  - Lines 65-80 (`usage()`) — same addition, keep in sync with `main()`.
  - Lines 723-735 (`cmd_install` arg loop) — add `--runtime` case + call
    `parse_runtime_flag`.

## Implementation Steps

1. Add `RUNTIME_KEYS`/`RUNTIME_LABELS`/`RUNTIME_ROOTS`/`RUNTIME_SCOPES` and
   the three lookup helpers + `parse_runtime_flag` after the CONFIG block.
2. Add `--runtime` case to `cmd_install`'s while-loop; add
   `local target_runtime="claude"`; call `parse_runtime_flag "$target_runtime"`
   right after the while-loop ends.
3. Update `usage()` and the `main()` fallback block with one new line each:
   `ba-kit install --runtime claude,codex,agy  Chọn runtime cài đặt` plus a
   short note: `claude = full (skills+agents+hooks); codex/agy = chỉ skills`.
4. Temporarily (for this phase's manual verification only) add a debug
   `echo "Runtimes đã chọn: ${SELECTED_RUNTIME_KEYS[*]}"` right after
   parsing, run the manual checklist below, then remove the debug line
   before moving to Phase 2 (Phase 2 replaces it with real usage).

## Todo List

- [ ] Add `CLI_VERSION` constant + registry arrays + helper functions
- [ ] Add `parse_runtime_flag` with validation + dedupe + empty-token check
- [ ] Wire `--runtime` flag into `cmd_install` arg loop
- [ ] Update `usage()` text
- [ ] Update `main()` fallback help text
- [ ] Manual dry-run checklist (below), then remove temporary debug echo

## Success Criteria

- `bash -n ba-kit` passes.
- Manual checks (temporary debug echo from step 4):
  - `ba-kit install` (no flag) → `SELECTED_RUNTIME_KEYS=(claude)`.
  - `ba-kit install --runtime codex` → `(codex)`.
  - `ba-kit install --runtime claude,codex,agy` → all three, in order given.
  - `ba-kit install --runtime codex,codex` → deduped to `(codex)`.
  - `ba-kit install --runtime foo` → error listing `claude codex agy`, exit 1.
  - `ba-kit install --runtime ""` → error, exit 1.
  - `ba-kit install --runtime " codex , agy "` → trims to `(codex agy)`.

## Risk Assessment

- Low risk — purely additive, no existing command path is touched besides
  one new `case` branch in an arg loop and two help-text edits.
- Risk: forgetting to keep `usage()` and `main()`'s fallback block in sync
  (they're already duplicated in the current file) — mitigate by editing
  both in the same commit and diffing them side by side.

## Security Considerations

- None — no new external input beyond a CLI flag, validated against a
  fixed allowlist before use.

## Next Steps

- Phase 2 consumes `SELECTED_RUNTIME_KEYS` and the runtime lookup helpers
  to drive the actual multi-root merge pipeline.

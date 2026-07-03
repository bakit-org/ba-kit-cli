# Phase 3: doctor + version + uninstall Runtime-Awareness

## Context Links

- Parent plan: [plan.md](plan.md)
- Depends on: Phase 1 (registry, `CLI_VERSION`), Phase 2 (per-runtime state
  helpers: `runtime_version_file`, `runtime_product_file`,
  `runtime_manifest_file`, `runtime_backup_dir`, `_copy_safe`)

## Overview

- Priority: P1 (correctness gap if skipped — `install --runtime codex`
  would create state `doctor`/`version`/`uninstall` can't see or clean up)
- Status: not started
- Make `cmd_doctor` report per-runtime install state instead of only
  claude. Make `cmd_version` print the CLI's own version plus per-runtime
  installed product/version. Make `cmd_uninstall` able to target specific
  runtimes (new `--runtime` flag, same validation as install) or
  auto-detect all runtimes with existing state when the flag is omitted —
  and scope its removal/backup correctly per runtime's scope (full vs
  skills-only).

## Key Insights

- Auto-detect-when-omitted for uninstall (rather than requiring the flag)
  keeps backward compatibility: existing users only ever have `claude`
  state, so auto-detect finds exactly `claude` — identical behavior to
  today. Only users who've actually run `install --runtime codex` etc.
  will see uninstall touch more than claude, and that's the correctness
  fix being made here.
- `cmd_uninstall`'s current hardcoded skill-name list (lines 995-999,
  `ba-collab ba-content-audit ba-do ...`) must be reused per selected
  runtime root, not just `$INSTALL_DIR/skills/`. Turn it into a shared
  array (e.g. `BA_KIT_SKILL_NAMES`) declared once near the top of the
  file, referenced by the per-runtime removal loop.
- Full-scope removal (agents/rules/templates/ba-kit dir/core symlink/hooks
  cleanup) only applies to runtimes with `scope = full` — currently only
  `claude`. Skills-only runtimes (codex/agy) only ever get
  `<root>/skills/<name>` dirs and `<root>/ba-kit/` (state) created by
  install, so uninstall for them removes exactly those two things — never
  touch anything else under `~/.codex` or `~/.gemini/config` (those hold
  the user's own unrelated tool config).
- `clean_hooks_json` (writes to `$HOME/.claude/settings.json`) only makes
  sense when `claude` is among the runtimes being uninstalled — gate the
  call.
- Single confirmation prompt covering all runtimes being removed (not one
  prompt per runtime) — list what's about to be removed in the banner
  before asking, matching the existing single-prompt UX style.

## Requirements

### `cmd_doctor`

- Loop `RUNTIME_KEYS`; for each, check `runtime_product_file`/
  `runtime_version_file` existence at that runtime's root and print an
  `[OK]`/`[CHƯA]` line per runtime (mirroring today's single claude block
  at lines 879-886).
- Keep the global gh/gh-auth/product-access/python checks exactly as
  today (lines 888-932) — those aren't per-runtime concepts.
- "Components đã cài" section (935-941): for `claude`, keep exactly
  today's 5 lines (skills/agents/templates/hooks/core counts). For
  `codex`/`agy`, print one line each: skill count under `<root>/skills`
  if that root's state file exists, else skip the runtime entirely from
  this section (not installed there).

### `cmd_version`

- Today: prints one line, `$PRODUCT $VERSION` (claude only), or a
  not-installed message. Becomes:
  1. Always print the CLI's own version first: `BA-kit CLI vX.Y.Z`
     (from the `CLI_VERSION` constant added in Phase 1 — this is the npm
     package's own version, distinct from the downloaded product/content
     version tracked per runtime).
  2. Then loop `RUNTIME_KEYS`; for each with existing state
     (`runtime_product_file`/`runtime_version_file` present), print
     `  <label>: <product> <version>`; for each without state, print
     `  <label>: (chưa cài)`.
  3. If zero runtimes have state, keep it simple — still show the
     CLI version line (that's always true/known), then one line
     `  Chưa cài nội dung nào. Chạy: ba-kit install`.
- No flag needed — always shows all three runtimes' status plus the CLI
  version in one call.

### `cmd_uninstall`

- New optional `--runtime <comma-list>` flag, same parsing/validation as
  install (`parse_runtime_flag`, reused from Phase 1 — note: install's
  default-when-omitted is `"claude"`, but uninstall's default-when-omitted
  must be "auto-detect all runtimes with existing state," which is a
  *different* default — do not call `parse_runtime_flag` with its
  built-in claude default for uninstall's no-flag case; special-case it).
- Auto-detect: when no `--runtime` given, build the target list by
  checking `[ -f "$(runtime_version_file "$key")" ]` for every key in
  `RUNTIME_KEYS`. If none have state, print today's implicit "nothing
  installed" outcome (currently uninstall doesn't check this at all and
  would just no-op through empty removals — keep that harmless behavior,
  but print an explicit "Không có runtime nào đã cài." message and exit 0
  instead of silently running through empty rm calls).
- Confirmation banner lists every runtime+product+version about to be
  removed, single y/N prompt.
- Backup: per target runtime, before removal — full copy for
  `scope=full` (today's exact behavior for claude, using
  `runtime_backup_dir claude` = unchanged `$BACKUP_DIR` path with a
  `pre-uninstall-<timestamp>` subdir, exactly as today), skills-subtree
  copy for `scope=skills` runtimes into their own
  `runtime_backup_dir(key)`.
- Removal, per target runtime:
  - Always: `rm -rf "$root/skills/$name"` for each name in
    `BA_KIT_SKILL_NAMES`.
  - `scope=full` only (today's exact lines 1001-1008): remove
    `agents/`, `rules/ba-kit/`, `templates/`, `ba-kit/`, `core` symlink,
    guardrail hook files, `$BIN_DIR/ba-kit`; call `clean_hooks_json`.
  - `scope=skills` only: additionally remove `$root/ba-kit/` (the
    per-runtime state dir created in Phase 2) — nothing else.

## Architecture

```bash
BA_KIT_SKILL_NAMES=(ba-collab ba-content-audit ba-do ba-figma-sync
  ba-impact ba-kit-update ba-next ba-notion ba-qc-export ba-start
  ba-stitch-sync brainstorm qc-uc-review reverse-web)
```//declared once near CONFIG, replacing the inline for-loop list in
cmd_uninstall.

`cmd_uninstall` new arg parsing (currently takes no args at all):

```bash
cmd_uninstall() {
  local target_runtime=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --runtime) target_runtime="$2"; shift 2 ;;
      *) echo "Không hiểu tham số: $1"; exit 1 ;;
    esac
  done

  local -a TARGET_RUNTIME_KEYS=()
  if [ -n "$target_runtime" ]; then
    parse_runtime_flag "$target_runtime"      # reuses Phase 1 validation
    TARGET_RUNTIME_KEYS=("${SELECTED_RUNTIME_KEYS[@]}")
  else
    for key in "${RUNTIME_KEYS[@]}"; do
      [ -f "$(runtime_version_file "$key")" ] && TARGET_RUNTIME_KEYS+=("$key")
    done
  fi

  if [ ${#TARGET_RUNTIME_KEYS[@]} -eq 0 ]; then
    echo "Không có runtime nào đã cài."
    exit 0
  fi
  # ... banner listing TARGET_RUNTIME_KEYS with product/version, single
  # confirm prompt, then loop per key doing backup + scoped removal ...
}
```

`main()`'s dispatch for `uninstall` (line 31) currently calls
`cmd_uninstall` with no args — change to `cmd_uninstall "$@"` (shift
already happens the same way `install` does it) so the flag reaches it.

## Related Code Files

- Modify: `./ba-kit`
  - Line 31 (`main()` dispatch) — `uninstall) shift; cmd_uninstall "$@" ;;`
  - Lines 871-944 `cmd_doctor` — loop-ify the product/version block and
    the components block.
  - Lines 949-958 `cmd_version` — print `CLI_VERSION` line, loop
    `RUNTIME_KEYS` for per-runtime product/version.
  - Lines 963-1016 `cmd_uninstall` — add flag parsing, auto-detect,
    per-runtime backup+removal loop, extract `BA_KIT_SKILL_NAMES` to a
    top-level constant.
  - CONFIG block — add `BA_KIT_SKILL_NAMES` array near `PRODUCT_NAMES`.

## Implementation Steps

1. Extract the hardcoded skill list (lines 995-999) into
   `BA_KIT_SKILL_NAMES` in CONFIG.
2. Rewrite `cmd_doctor`'s product/version section to loop `RUNTIME_KEYS`.
3. Rewrite `cmd_doctor`'s components section per Requirements (full detail
   for claude, single skill-count line for codex/agy when installed).
4. Rewrite `cmd_version` per Requirements: `CLI_VERSION` line always
   first, then loop `RUNTIME_KEYS` for per-runtime product/version or
   "chưa cài".
5. Change `main()`'s uninstall dispatch to pass args through.
6. Add `--runtime` parsing + auto-detect fallback to `cmd_uninstall`.
7. Rewrite the confirmation banner to list all target runtimes.
8. Rewrite backup step to loop per target runtime with correct scope.
9. Rewrite removal step to loop per target runtime with correct scope,
   gating `clean_hooks_json` on claude being present in the target list.

## Todo List

- [ ] `BA_KIT_SKILL_NAMES` extracted to CONFIG
- [ ] `cmd_doctor` product/version block loops all runtimes
- [ ] `cmd_doctor` components block scoped per runtime
- [ ] `cmd_version` prints `CLI_VERSION` + per-runtime product/version
- [ ] `main()` passes uninstall args through
- [ ] `cmd_uninstall` `--runtime` flag + auto-detect implemented
- [ ] `cmd_uninstall` banner lists all targets before single confirm
- [ ] `cmd_uninstall` backup scoped per runtime
- [ ] `cmd_uninstall` removal scoped per runtime, hooks cleanup gated

## Success Criteria

- `bash -n ba-kit` passes.
- `ba-kit doctor` with only claude installed → output byte-identical in
  structure to today's (same lines, same order) — verify by diffing
  output before/after for a claude-only state dir.
- Manual dry-run with fake state dirs (`mkdir -p /tmp/fake-codex/ba-kit`,
  write VERSION/PRODUCT, `mkdir -p /tmp/fake-codex/skills/ba-start`) —
  temporarily point `RUNTIME_ROOTS[1]` at the fake dir, run `doctor`,
  confirm it reports the fake codex install correctly, then revert.
- `ba-kit version` with nothing installed → shows `BA-kit CLI vX.Y.Z` plus
  "(chưa cài)" for all three runtimes, exits 0 (not an error state).
- `ba-kit version` with only claude installed → `BA-kit CLI vX.Y.Z` plus
  claude's product+version, codex/agy show "(chưa cài)".
- `ba-kit uninstall` with no flag, only claude state present → identical
  behavior to today (single confirm, same removal list, same backup path).
- `ba-kit uninstall --runtime agy` with a fake agy skills dir → confirm
  only `<agy_root>/skills/<name>` dirs and `<agy_root>/ba-kit/` get
  removed; nothing else under the fake agy root is touched; claude state
  untouched.
- `ba-kit uninstall` with no flag but both claude and fake-codex state
  present → auto-detects both, single confirmation banner names both.

## Risk Assessment

- Risk: auto-detect uninstall silently expanding scope beyond what a user
  expects (e.g. they forgot they installed codex support once) — mitigated
  by the confirmation banner explicitly naming every runtime that will be
  touched before the y/N prompt, so nothing is silent at the point of
  action even if detection itself is automatic.
- Risk: `clean_hooks_json` running when it shouldn't (or not running when
  it should) if the claude-in-target-list check is wrong — mitigate with
  a explicit boolean check `contains(TARGET_RUNTIME_KEYS, "claude")`
  rather than inferring it from loop position.

## Security Considerations

- Uninstall removal paths must stay strictly inside `<root>/skills/<name>`
  and `<root>/ba-kit/` for skills-only runtimes — no blanket
  `rm -rf "$root"` under any circumstance. Code-review this explicitly
  since it's a destructive operation on user-controlled-adjacent
  directories (`~/.codex`, `~/.gemini/config` hold non-ba-kit content).

## Next Steps

- Phase 4 extends `cmd_update` similarly, reusing the same detect +
  per-runtime helpers.

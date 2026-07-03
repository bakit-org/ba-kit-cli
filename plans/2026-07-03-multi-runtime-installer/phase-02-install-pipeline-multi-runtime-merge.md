# Phase 2: Install Pipeline — Multi-Runtime Merge + Per-Runtime State

## Context Links

- Parent plan: [plan.md](plan.md)
- Depends on: [phase-01-runtime-registry-and-flag-parsing.md](phase-01-runtime-registry-and-flag-parsing.md)
  (`SELECTED_RUNTIME_KEYS`, `runtime_root_for_key`, `runtime_label_for_key`,
  `runtime_scope_for_key`)

## Overview

- Priority: P0 (the actual feature)
- Status: not started
- Rewire `cmd_install` so one download+extract feeds a loop over
  `SELECTED_RUNTIME_KEYS`, each doing its own scoped backup, scoped merge,
  and scoped state save. `claude` keeps its exact current behavior
  (verified by construction, not just intent — see Key Insights).

## Key Insights

- **`merge_files` currently reads the global `$MANIFEST_FILE` directly**
  (line ~402: `[ -f "$MANIFEST_FILE" ] && old_manifest=$(cat "$MANIFEST_FILE")`).
  This is a real correctness bug for multi-runtime: if left as-is, a codex
  or agy merge would consult claude's manifest (wrong file, unrelated rel
  paths) instead of its own. Must become a parameter, not a global read.
  This is the one non-trivial refactor in this phase — everything else is
  mostly "wrap existing calls in a loop."
- **Backup dir is the one deliberate asymmetry**: claude keeps
  `$HOME/.claude/backups` (existing `BACKUP_DIR` constant, unchanged —
  don't migrate users' existing backups to a new path). codex/agy get
  `<root>/ba-kit/backups` (new, since `<root>/ba-kit/` doesn't exist yet
  for them and there's nothing to preserve).
- **Backup scope for skills-only runtimes is `<root>/skills` only**, not
  the whole runtime root — `~/.codex/` and `~/.gemini/config/` hold the
  user's own unrelated tool config (config.toml, mcp config, prompts).
  `do_backup` needs a `src_dir` parameter instead of hardcoding
  `$INSTALL_DIR`.
- **`post_install` (hooks registration, pip install, `core` symlink) is
  claude/full-scope only by definition** — hooks target
  `$HOME/.claude/settings.json` specifically, pip installs `ba-kit/scripts/
  requirements.txt` which only exists in the full content tree, and the
  `core` symlink is a claude-specific convenience. Gate the whole call on
  `runtime_scope_for_key "$key" = "full"`.
- **Cross-product check must run per selected runtime, before download**,
  so a conflict on `codex` (e.g. codex root already has "BA-kit" installed,
  user requests "BA-kit Solo Pro" for codex) aborts before any network
  transfer, exactly like today's single-runtime check does. Simplification
  (flagged in plan.md open questions and here): the existing
  "already installed at this version — reinstall? (y/N)" interactive
  sub-prompt inside `check_cross_product` (today's lines ~274-287) only
  makes sense for one runtime at a time. For multi-runtime installs, if a
  given runtime already has the exact same product+version, **skip that
  runtime silently** (print "already up to date, bỏ qua") instead of
  prompting — avoids N interactive prompts in one command. Single-runtime
  installs (the default, and the only case that exists today) keep the
  exact current interactive-confirm behavior, since with one runtime in
  the list there's nothing to disambiguate.
- One download, one extract, regardless of runtime count — loop starts
  *after* `extract_release`.

## Requirements

- `merge_files(src, dest, manifest_file, force=false)` — 3rd positional
  param added; all call sites updated.
- `do_backup(src_dir, backup_dir, keep=5)` — generalized from hardcoded
  globals; `prune_backups(backup_dir, keep=5)` likewise takes the dir as a
  param instead of reading `$BACKUP_DIR` directly.
- `save_state(version_file, product_file, manifest_file, extract_dir)` —
  generalized from hardcoded globals.
- New orchestration inside `cmd_install`: single download/extract, then
  `for key in "${SELECTED_RUNTIME_KEYS[@]}"` loop doing backup → merge →
  (post_install if full) → save_state, then one `cleanup` and one
  aggregated `show_result`.
- `show_result` prints one block per selected runtime (product, version,
  and either full component counts or a single skills count, depending on
  scope), plus the backup path(s) actually created.

## Architecture

Per-runtime state path helper (new, near the Phase 1 registry helpers):

```bash
runtime_version_file()  { echo "$(runtime_root_for_key "$1")/ba-kit/VERSION"; }
runtime_product_file()  { echo "$(runtime_root_for_key "$1")/ba-kit/PRODUCT"; }
runtime_manifest_file() { echo "$(runtime_root_for_key "$1")/ba-kit/release-manifest.json"; }
runtime_backup_dir() {
  local key="$1"
  if [ "$key" = "claude" ]; then
    echo "$BACKUP_DIR"          # unchanged: $HOME/.claude/backups
  else
    echo "$(runtime_root_for_key "$key")/ba-kit/backups"
  fi
}
```

Note these formulas reduce to today's exact constants for `claude`:
`runtime_version_file claude` = `$HOME/.claude/ba-kit/VERSION` =
today's `$VERSION_FILE`. Same for product/manifest. This is the
backward-compat proof, not just an assertion — verify it manually in
Success Criteria below.

`cmd_install` new body (replacing lines 743-760):

```bash
check_prereqs
select_product
select_version "$target_version"

# Pre-flight: check cross-product conflicts for every selected runtime
# BEFORE any download. Collect runtimes to actually process (skip
# already-up-to-date ones silently when len(SELECTED_RUNTIME_KEYS) > 1).
local -a RUNTIMES_TO_PROCESS=()
for key in "${SELECTED_RUNTIME_KEYS[@]}"; do
  if check_cross_product_for_runtime "$key"; then
    RUNTIMES_TO_PROCESS+=("$key")
  fi
done
if [ ${#RUNTIMES_TO_PROCESS[@]} -eq 0 ]; then
  echo "Không có runtime nào cần cài/cập nhật."
  exit 0
fi

download_release
extract_release

echo "Đang cài đặt files..."

declare -a RESULT_KEYS=()
for key in "${RUNTIMES_TO_PROCESS[@]}"; do
  local root scope label
  root=$(runtime_root_for_key "$key")
  scope=$(runtime_scope_for_key "$key")
  label=$(runtime_label_for_key "$key")
  echo ""
  echo "-- ${label} (${root}) --"

  if [ "$scope" = "full" ]; then
    do_backup "$root" "$(runtime_backup_dir "$key")"
    merge_files "$EXTRACT_DIR/.claude" "$root" "$(runtime_manifest_file "$key")"
    merge_files "$EXTRACT_DIR/ba-kit" "$root/ba-kit" "$(runtime_manifest_file "$key")" true
    post_install "$root"
  else
    do_backup "$root/skills" "$(runtime_backup_dir "$key")"
    merge_files "$EXTRACT_DIR/.claude/skills" "$root/skills" "$(runtime_manifest_file "$key")"
  fi

  save_state "$(runtime_version_file "$key")" "$(runtime_product_file "$key")" \
             "$(runtime_manifest_file "$key")" "$EXTRACT_DIR"
  RESULT_KEYS+=("$key")
done

cleanup
show_result "${RESULT_KEYS[@]}"
```

`check_cross_product_for_runtime(key)`: same logic as today's
`check_cross_product` but reads `$(runtime_product_file "$key")` /
`$(runtime_version_file "$key")` instead of the globals, and — only when
`${#SELECTED_RUNTIME_KEYS[@]} -gt 1` — replaces the interactive
"reinstall? (y/N)" prompt with a silent skip (`return 1` = "don't
process this runtime"; `return 0` = "process it"). When exactly one
runtime is selected, behavior is byte-identical to today's function
(same prompt, same exit-1-on-different-product).

`post_install` gains a `$1=root` param; every internal reference to
`$INSTALL_DIR` inside it becomes `$root` (framework binary copy, hooks
dir, pip requirements path, core symlink). `register_hooks` also takes
`$1=root` and only makes sense for claude — still fine to keep it generic
since it's only ever called from the `scope = full` branch, but rename
its internal `$INSTALL_DIR` reference to the passed-in `$root` for
consistency and future-proofing rather than assuming a global.

## Related Code Files

- Modify: `./ba-kit`
  - Lines 336-344 `_copy_safe` — unchanged, already generic (works on any
    src/dst pair).
  - Lines 349-374 `do_backup`/`prune_backups` — add `src_dir`/`backup_dir`
    params, remove hardcoded `$INSTALL_DIR`/`$BACKUP_DIR` reads.
  - Lines 392-451 `merge_files` — add `manifest_file` param (3rd
    positional, before `force`).
  - Lines 465-493 `post_install` — add `root` param, replace internal
    `$INSTALL_DIR` uses.
  - Lines 495-600 `register_hooks` — add `root` param, replace internal
    `$INSTALL_DIR` use (settings.json path stays `$HOME/.claude/settings.json`
    always — hooks are a Claude Code concept regardless of param, but pass
    `root` through for the hooks-dir lookup, which for the only caller
    will always be the claude root anyway).
  - Lines 655-665 `save_state` — generalize params.
  - Lines 679-715 `show_result` — accept variadic runtime keys, loop and
    print per-runtime block instead of one hardcoded block.
  - Lines 720-760 `cmd_install` — replace body per Architecture above.
  - New: `check_cross_product_for_runtime(key)` near existing
    `check_cross_product` (lines 246-288) — keep the old function too if
    anything else still calls it directly, or replace it entirely if
    nothing else does (check with grep before deleting).

## Implementation Steps

1. Add `runtime_version_file`/`runtime_product_file`/`runtime_manifest_file`/
   `runtime_backup_dir` helpers next to Phase 1's registry helpers.
2. Refactor `merge_files` to accept `manifest_file` as 3rd param; update
   its two internal reads of `$MANIFEST_FILE` to use the param instead.
3. Refactor `do_backup`/`prune_backups` to take `src_dir`/`backup_dir` (and
   optional `keep`) instead of reading `$INSTALL_DIR`/`$BACKUP_DIR` globals.
4. Refactor `save_state` to take 4 explicit params instead of reading
   globals + `$EXTRACT_DIR`/`$SELECTED_VERSION`/`$SELECTED_PRODUCT`
   directly (keep `$EXTRACT_DIR` as-is since it's genuinely
   invocation-scoped and set once by `extract_release`, not per-runtime —
   fine to read it as a global inside `save_state`, just don't hardcode
   the *destination* file paths).
5. Add `root` param to `post_install` and `register_hooks`; replace
   internal `$INSTALL_DIR` references.
6. Write `check_cross_product_for_runtime(key)` per the single-vs-multi
   prompt behavior described in Key Insights.
7. Rewrite `cmd_install` body per Architecture.
8. Rewrite `show_result` to accept the processed runtime key list and loop.
9. Grep the whole file for remaining bare `$INSTALL_DIR`/`$VERSION_FILE`/
   `$PRODUCT_FILE`/`$MANIFEST_FILE`/`$BACKUP_DIR` reads outside
   `cmd_doctor`/`cmd_update`/`cmd_uninstall`/`cmd_version` (those are
   Phase 3/4 scope, leave untouched here) to make sure nothing inside the
   install path still silently assumes claude.

## Todo List

- [ ] `merge_files` manifest_file param + both internal read sites updated
- [ ] `do_backup`/`prune_backups` generalized
- [ ] `save_state` generalized
- [ ] `post_install`/`register_hooks` take `root` param
- [ ] `check_cross_product_for_runtime` written, single-runtime path
      verified byte-identical to today's prompt behavior
- [ ] `cmd_install` rewritten per Architecture
- [ ] `show_result` loops over processed runtimes
- [ ] Grep sweep for leftover hardcoded globals inside the install path

## Success Criteria

- `bash -n ba-kit` passes.
- Manual verification that claude-only behavior is unchanged:
  - Hand-trace `runtime_version_file claude` → `$HOME/.claude/ba-kit/VERSION`,
    confirm it equals today's `$VERSION_FILE` constant.
  - Hand-trace `runtime_backup_dir claude` → `$BACKUP_DIR`
    (`$HOME/.claude/backups`), confirm no path change.
  - `ba-kit install` (no `--runtime`) walks through the exact same
    function-call sequence as today: `check_prereqs → select_product →
    select_version → check_cross_product_for_runtime(claude) [same
    prompt as before, since only 1 runtime selected] → download_release →
    extract_release → do_backup(full claude root) → merge_files(.claude)
    → merge_files(ba-kit, force) → post_install(claude root) →
    save_state(claude paths) → cleanup → show_result(claude)`.
- Manual dry-run with a fake `$EXTRACT_DIR` (construct a tmp dir with
  `.claude/skills/fake-skill/SKILL.md` and `.claude/agents/`, `ba-kit/VERSION`
  stub) exercising the loop body directly (call the per-runtime block as a
  function with `TMP_DIR`/`EXTRACT_DIR` pre-set, bypassing
  `download_release`) for `--runtime codex`:
  - Confirms only `~/.codex/skills/fake-skill/` gets created — no
    `~/.codex/agents`, no hooks touched, no pip install attempted.
  - Confirms backup only copied `~/.codex/skills` (if pre-existing), not
    all of `~/.codex`.
  - Confirms state written to `~/.codex/ba-kit/VERSION` etc., not
    `~/.claude/ba-kit/`.
- `--runtime claude,codex,agy` dry-run: confirms single download+extract
  happens once (add a temporary `echo "download called"` inside
  `download_release` during the dry run, count invocations = 1).

## Risk Assessment

- **Highest-risk phase in the whole plan** — this is the refactor that
  touches every core function. Mitigate by doing the grep sweep (step 9)
  and the "hand-trace equals today's constants" checks before considering
  the phase done.
- Risk: `merge_files`'s hash-aware "preserve local edits vs. safe upgrade"
  logic silently behaves wrong if `manifest_file` param is passed
  incorrectly (e.g. accidentally passing claude's manifest for a codex
  merge) — the bug would be silent (files get preserved/overwritten
  incorrectly, no error). Mitigate with the explicit dry-run check above
  that inspects state file locations after the fake run.
- Risk: `check_cross_product_for_runtime`'s silent-skip-when-multi
  behavior is a UX judgment call not explicitly signed off by the user —
  flagged in plan.md open questions; confirm before or immediately after
  implementing.

## Security Considerations

- No new external input surface — same `gh`/tarball trust model as today,
  just fanned out to more destination directories. Verify the skills-only
  merge never touches anything outside `<root>/skills` (no path traversal
  from `rel_path` in `merge_files` — this is pre-existing code, not
  changed here, but worth a quick sanity read since scope now includes
  less-trusted-by-convention dirs like `~/.codex`).

## Next Steps

- Phase 3 makes `doctor`/`uninstall` consume the same registry + per-runtime
  state helpers to report on and remove non-claude installs.

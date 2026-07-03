# Phase 4: update Runtime-Awareness (Minimal)

## Context Links

- Parent plan: [plan.md](plan.md)
- Depends on: Phase 1 (registry), Phase 2 (per-runtime state + merge
  helpers), Phase 3 (auto-detect pattern already established for uninstall
  — reuse the same detection loop shape here)

## Overview

- Priority: P2 (nice-to-have per the user's own framing — "may be
  extended too if it's a small clean addition," "keep it minimal")
- Status: not started
- Auto-detect every runtime with existing state (same pattern as Phase
  3's uninstall auto-detect) and refresh each, reusing one download per
  distinct product+version target rather than one per runtime.

## Key Insights

- **Grouping-by-product is the key design decision** — flagged as an open
  question in plan.md, confirm before implementing. Reasoning: today's
  `cmd_update` assumes a single product/version for the whole machine (one
  `PRODUCT_FILE`, one `VERSION_FILE`). With per-runtime state, it's
  *possible* (if unlikely in practice, since all installs typically use
  the same purchased product) for `claude` and `codex` to have divergent
  products if a user ran separate `install --runtime` calls with
  different products over time. The instruction "reuse the single
  per-release download for all detected runtimes just like install does"
  only holds when they share a product+version target. Handling:
  1. Auto-detect all runtimes with state (same as Phase 3).
  2. Group detected runtimes by their recorded product
     (`cat "$(runtime_product_file "$key")"`).
  3. For each distinct product group: resolve latest version for that
     product's repo once, download+extract once, loop merge across every
     runtime in that group (same per-runtime scoped merge logic as
     Phase 2's install loop).
  4. This means "one download per invocation" only holds in the common
     case (all runtimes share one product) — worth stating plainly in the
     update confirmation output so it's not a silent surprise
     (e.g. "Đang cập nhật 2 nhóm sản phẩm riêng biệt...").
- Access-revoked check (today's lines 807-819) must run per product group,
  not globally — a user could have access to product A (used by claude)
  revoked while still holding access to product B (used by codex).
- Confirmation prompt: today is a single "Cập nhật lên ${latest}? (Y/n)"
  — becomes one prompt per product group (if >1 group), or stays exactly
  today's single prompt when there's only one group (the common case,
  which covers every existing user since they only ever have claude).

## Requirements

- No new CLI flag for `update` — pure auto-detection, matching the user's
  explicit instruction that this stays a small, flag-free addition.
- Single-runtime-with-claude-only case (today's only real-world case)
  must produce byte-identical output and behavior to today's `cmd_update`.
- Multi-runtime, single-product-group case: one download, loop merge per
  runtime, one aggregated result summary (reuse Phase 2's `show_result`
  loop shape).
- Multi-runtime, multi-product-group case: one download per group,
  sequential groups, each with its own confirm prompt and its own
  access-revoked handling.

## Architecture

```bash
cmd_update() {
  check_prereqs

  local -a DETECTED_KEYS=()
  for key in "${RUNTIME_KEYS[@]}"; do
    [ -f "$(runtime_version_file "$key")" ] && DETECTED_KEYS+=("$key")
  done

  if [ ${#DETECTED_KEYS[@]} -eq 0 ]; then
    echo "BA-kit chưa được cài đặt."
    echo "Chạy: ba-kit install"
    exit 1
  fi

  # Group detected keys by recorded product name
  # (bash 3.2: parallel arrays, not associative — GROUP_PRODUCTS[i] paired
  # with GROUP_KEYS_<i> built via string-join since nested arrays aren't
  # supported; see Implementation Steps for the exact join/split approach)
  ...group, then for each group: resolve repo, check access, resolve
  latest, compare against that group's current version (they should all
  match since they were installed/updated together — if they don't,
  operate against the lowest common version's product record and log a
  one-line note), confirm, download, extract, loop merge per runtime in
  group (same scoped logic as Phase 2), post_install if full-scope member
  present, save_state per runtime, cleanup once per group.
}
```

Bash 3.2 constraint note for implementation: grouping "runtime keys by
product string" without associative arrays is the one genuinely fiddly
bit here. Simplest correct approach: iterate `DETECTED_KEYS`, for each
build a `product|key1,key2,...` string in a flat array by linear-scanning
existing group entries (small N ≤ 3, so O(N²) is irrelevant) — e.g.
maintain `GROUP_LABELS=()` and `GROUP_MEMBERS=()` parallel arrays, find
matching index by string compare, append or push new group.

## Related Code Files

- Modify: `./ba-kit`
  - Lines 765-866 `cmd_update` — full rewrite per Architecture, reusing
    Phase 2's `merge_files`/`do_backup`/`save_state`/`post_install`
    (with `root` params) and Phase 1/2's runtime helpers.

## Implementation Steps

1. Replace the single-product read (`SELECTED_PRODUCT=$(cat
   "$PRODUCT_FILE")`) with the `DETECTED_KEYS` auto-detect loop.
2. Implement the grouping helper (`GROUP_LABELS`/`GROUP_MEMBERS` parallel
   arrays as described above).
3. For each group: resolve repo from `PRODUCT_NAMES`/`PRODUCT_REPOS`
   (existing lookup logic, lines ~792-799, unchanged), check access
   (existing logic, lines ~807-819, unchanged), resolve latest version
   (existing logic, lines ~821-826, unchanged) — all scoped to the
   group's product instead of the single global `SELECTED_PRODUCT`.
4. Compare current version per member runtime in the group; if any
   member is already at latest, still include it in the merge loop
   (merge is idempotent/hash-aware) rather than special-casing it out —
   simpler than trying to skip individual runtimes mid-group.
5. Confirm once per group (skip group entirely if already-latest for
   all its members, matching today's single "đang dùng phiên bản mới
   nhất" exit-0 short-circuit — but only exit 0 overall if *every* group
   is already latest).
6. Download+extract once per group; loop merge per runtime member using
   Phase 2's scoped merge/backup/save_state calls.
7. Aggregate `show_result` across all processed runtimes at the very end
   (after all groups), not per group.

## Todo List

- [ ] Auto-detect loop replaces single `PRODUCT_FILE` read
- [ ] Grouping-by-product implemented (parallel-array approach)
- [ ] Per-group repo/access/latest-version resolution
- [ ] Per-group confirm prompt, correct short-circuit when all groups
      already latest
- [ ] Per-group download/extract + per-runtime scoped merge loop
- [ ] Aggregated `show_result` at the end across all groups

## Success Criteria

- `bash -n ba-kit` passes.
- Claude-only detected state (today's only real case) → identical output
  and behavior to today's `cmd_update` (single group, single confirm,
  single download).
- Manual dry-run with fake claude + fake-codex state both recording the
  *same* product → confirms exactly one download, both runtimes merged
  and state-saved.
- Manual dry-run with fake claude + fake-codex state recording
  *different* products → confirms two separate confirm prompts and two
  downloads, each scoped correctly to its own group's members.

## Risk Assessment

- Medium risk — the grouping logic is new surface area with no existing
  precedent in the file (everything else in this plan reuses an existing
  pattern). Keep it isolated to `cmd_update` only so a bug here can't
  regress `install`/`doctor`/`uninstall`.
- If the grouping complexity proves not worth it in review, the fallback
  (explicitly sanctioned by the user: "keep it minimal") is to drop
  multi-product-group support entirely and just document that `update`
  requires all detected runtimes to share one product, erroring clearly
  if they don't. Flag this simplification to the user as an alternative
  if Phase 4 implementation time balloons.

## Security Considerations

- None beyond what Phase 2 already covers (same download/merge trust
  model, just grouped differently).

## Next Steps

- Phase 5 documents the whole feature in README/help text and bumps the
  package version.

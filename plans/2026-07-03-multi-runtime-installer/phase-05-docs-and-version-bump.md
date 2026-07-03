# Phase 5: Docs (README + usage/help text) + Version Bump

## Context Links

- Parent plan: [plan.md](plan.md)
- Depends on: Phases 1-4 complete (docs describe final behavior)

## Overview

- Priority: P2 (required for shipping, but purely descriptive — no logic
  changes)
- Status: not started
- Document `--runtime` on `install` (and `uninstall` per Phase 3) in
  `usage()`, `main()`'s fallback help block, and `README.md`. Bump
  `package.json` version.

## Key Insights

- No `CHANGELOG.md` exists in this repo (confirmed by directory listing)
  — do not create one speculatively per the "don't invent things the task
  doesn't need" rule. The conventional-commit message on the shipping
  commit is this repo's changelog mechanism today.
- `usage()` (lines 65-80) and `main()`'s fallback block (lines 47-61)
  are already duplicated content in the current file — both must be
  edited together or they drift further.
- Version bump: this is a new feature (multi-runtime support), not a fix
  — semver minor bump. Current `package.json` version is `1.1.9` (repo's
  last commit was `chore: bump to 1.1.9`) → bump to `1.2.0`.

## Requirements

- `usage()` and `main()` fallback block both gain:
  - `ba-kit install --runtime <list>  Chọn runtime: claude,codex,agy (mặc định: claude)`
  - One line per runtime key explaining scope, e.g.:
    ```
    Runtime hỗ trợ:
      claude  Claude Code — đầy đủ (skills, agents, hooks, templates)
      codex   Codex CLI — chỉ skills
      agy     Antigravity IDE — chỉ skills
    ```
  - `ba-kit uninstall --runtime <list>  Chỉ gỡ runtime chỉ định (mặc định: tự phát hiện tất cả)`
    (only add this line once Phase 3 is actually implemented — don't
    document a flag that doesn't exist yet if phases are shipped
    incrementally).
- `README.md`:
  - `## Usage` section: add the two new flag lines matching `usage()`.
  - New `## Runtimes` section (after `## Usage`, before `## Purchase`)
    explaining the three keys, their scope difference, and the default
    (`claude` only, backward compatible).
- `package.json`: bump `"version"` from `1.1.9` to `1.2.0`.

## Related Code Files

- Modify: `./ba-kit`
  - Lines 47-61 (`main()` fallback help)
  - Lines 65-80 (`usage()`)
- Modify: `README.md`
  - Lines 17-25 (`## Usage`) — add flag lines
  - New section after line 25, before `## Purchase` (line 27)
- Modify: `package.json`
  - Line 3 — version bump

## Implementation Steps

1. Update `usage()` with the new lines (see Requirements).
2. Mirror the exact same addition into `main()`'s fallback block —
   diff the two functions after editing to confirm they match.
3. Update `README.md` `## Usage` section.
4. Add `README.md` `## Runtimes` section.
5. Bump `package.json` version to `1.2.0`.
6. Final full-file check: `bash -n ba-kit`, and if `shellcheck` is
   available, run it and note any findings (fix trivial ones inline,
   flag non-trivial ones to the user rather than silently suppressing).

## Todo List

- [ ] `usage()` updated
- [ ] `main()` fallback help updated, verified matching `usage()`
- [ ] `README.md` Usage section updated
- [ ] `README.md` Runtimes section added
- [ ] `package.json` version bumped to `1.2.0`
- [ ] `bash -n ba-kit` clean
- [ ] `shellcheck ba-kit` run if available, findings triaged

## Success Criteria

- `ba-kit help` and `ba-kit` (no args, no framework installed) both show
  identical new content.
- `README.md` renders correctly (headings, code fences) — visual check.
- `npm pack --dry-run` (or equivalent) shows the bumped version.

## Risk Assessment

- Minimal — text-only changes plus a version number. Only real risk is
  the two help-text blocks drifting apart again, mitigated by the
  side-by-side diff in step 2.

## Security Considerations

- None.

## Next Steps

- None — this is the last phase. After merge, the next release's tarball
  build/CI (`.github/workflows/`) is unaffected since the tarball format
  itself didn't change (skills-only merge just points at a different
  destination root using the same source subtree).

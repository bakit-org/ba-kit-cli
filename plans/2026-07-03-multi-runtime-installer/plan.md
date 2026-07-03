# Plan: Multi-Runtime Installer Support

## Goal

Add `ba-kit install --runtime <comma-list>` support for `claude` (full scope,
unchanged behavior), `codex` (Codex CLI, skills-only), and `agy` (Antigravity
IDE, skills-only). No flag = `claude` only, 100% backward compatible.
Extend `doctor` and `uninstall` to be runtime-aware so they can report on and
cleanly remove what a non-claude install created. Extend `update` minimally
if it stays small.

## Scope note

The release tarball format is unchanged — skill packages (`SKILL.md` dirs)
are byte-identical across all three runtimes. This is a CLI-only change to
`./ba-kit` (~1020 lines, single bash script, the entire product).

## Non-goals (v1)

- No agents/hooks/templates/rules for codex or agy — skills only.
- No changes to the private content repos or release tarball layout.
- No new test framework — this repo has none; verification is
  `bash -n` + `shellcheck` (if available) + manual dry-run checklist.

## Phases

| Phase | File | Touches |
|---|---|---|
| 1 | [phase-01-runtime-registry-and-flag-parsing.md](phase-01-runtime-registry-and-flag-parsing.md) | CONFIG block, `main()` fallback help, `usage()`, `cmd_install` arg loop |
| 2 | [phase-02-install-pipeline-multi-runtime-merge.md](phase-02-install-pipeline-multi-runtime-merge.md) | `_copy_safe`, `do_backup`, `prune_backups`, `merge_files`, `post_install`, `save_state`, `show_result`, `cmd_install` |
| 3 | [phase-03-doctor-uninstall-runtime-awareness.md](phase-03-doctor-uninstall-runtime-awareness.md) | `cmd_doctor`, `cmd_version`, `cmd_uninstall`, `clean_hooks_json` (gating only) |
| 4 | [phase-04-update-runtime-awareness.md](phase-04-update-runtime-awareness.md) | `cmd_update` |
| 5 | [phase-05-docs-and-version-bump.md](phase-05-docs-and-version-bump.md) | `README.md`, `usage()`/help text, `package.json` |

Sequential only — this is one file, changes compound. Do not parallelize
phases.

## Key architectural decision (applies to all phases)

Generalize the existing claude-only state constants into a small
per-runtime lookup instead of a rewrite. For runtime key `claude`, the
generalized path formulas reduce to *exactly* today's constants
(`$HOME/.claude/ba-kit/VERSION`, etc.) — verified in Phase 1 — so claude
behavior is provably unchanged, not just "should be unchanged."

Parallel indexed arrays (bash 3.2 compatible, matches existing
`PRODUCT_NAMES`/`PRODUCT_REPOS`/`PRODUCT_URLS` pattern):

```bash
RUNTIME_KEYS=("claude" "codex" "agy")
RUNTIME_LABELS=("Claude Code" "Codex CLI" "Antigravity IDE")
RUNTIME_ROOTS=("$HOME/.claude" "$HOME/.codex" "$HOME/.gemini/config")
RUNTIME_SCOPES=("full" "skills" "skills")
```

Per-runtime state lives at `<root>/ba-kit/{VERSION,PRODUCT,release-manifest.json}`
for every runtime including claude (this is already claude's exact layout).
Backup dir is the one exception: claude keeps `$HOME/.claude/backups`
(preserve existing user backups, no path migration); codex/agy get
`<root>/ba-kit/backups`.

## Verification approach (no test framework exists)

1. `bash -n ba-kit` after every phase.
2. `shellcheck ba-kit` if installed, else note as skipped.
3. Manual dry-run checklist (documented per-phase in each phase file's
   Success Criteria) using a fake pre-extracted `$EXTRACT_DIR` — real
   installs require `gh auth` + purchased private-repo access not
   available in this environment.

## Decided

- `cmd_version` is runtime-aware: always prints the CLI's own version
  (`CLI_VERSION` constant, Phase 1) first, then per-runtime installed
  product/version or "(chưa cài)" for each of `claude`/`codex`/`agy`
  (Phase 3).
- Phase 4 keeps the full grouping-by-product strategy for `update`
  (not the simpler "error on mismatch" fallback) — confirmed by user.

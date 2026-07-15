# BA-kit CLI

AI-powered Business Analyst toolkit for Claude Code, Codex CLI, and Antigravity IDE.

## Install

```bash
npm install -g @bakit-org/cli
```

Or try without installing:

```bash
npx @bakit-org/cli doctor
```

## Usage

```bash
ba-kit install                     # First install (default: claude runtime)
ba-kit install --runtime <list>    # Install for specific runtime(s), e.g. claude,codex,agy
ba-kit update                      # Update to latest (all installed runtimes)
ba-kit doctor                      # Health check
ba-kit version                     # Show CLI version + per-runtime installed version
ba-kit uninstall                   # Uninstall (with backup, auto-detects installed runtimes)
ba-kit uninstall --runtime <list>  # Uninstall specific runtime(s) only
```

There is no `--product` flag. Product selection is access-driven:
- **Without GitHub authentication:** public Solo Basic is automatically selected.
- **With GitHub authentication:** you see a numbered menu of products your account can access (private products plus public Solo).

## Products

| Product | Access | Profile | Contents |
|---------|--------|---------|----------|
| BA-kit Solo Basic | Public (free) | `solo-basic` | 5 skills + templates + core |
| BA-kit | Private | `standard` | Full skills, agents, hooks, templates |

### Solo Basic Scope

Solo Basic installs exactly five skills (`ba-start`, `ba-do`, `ba-next`, `ba-impact`, `brainstorm`)
plus `templates/` and `core/` to every selected runtime. It does **not** install agents, hooks,
scripts, settings, framework files, pip packages, or tool lanes.

## Runtimes

| Key | Runtime | Scope |
|-----|---------|-------|
| `claude` (default) | Claude Code | Full — skills, agents, hooks, templates |
| `codex` | Codex CLI | Skills only |
| `agy` | Antigravity IDE | Skills only |

Omit `--runtime` to install for Claude Code only (unchanged, backward-compatible
default). Pass a comma-separated list to install for multiple runtimes in one
command, e.g. `ba-kit install --runtime claude,codex,agy`.

## Prerequisites

- **Public Solo Basic:** `jq` and `curl` (pre-installed on macOS; `apt install jq` on Ubuntu).
- **Private products:** [GitHub CLI](https://cli.github.com) (`gh`) authenticated with `gh auth login`.
- Node.js 18+ (for `npm install -g`).
- Windows only: [Git for Windows](https://git-scm.com/download/win) (provides `bash.exe`, required by the CLI).

## State And Recovery

The CLI uses schema-v2 `state.json` files (`~/.claude/ba-kit/state.json` etc.) to track
installed products, versions, and managed file hashes. This enables safe update, uninstall,
and reinstall without data loss.

### Recovery

- **Schema-v2 downgrade is unsupported.** If you installed with a newer CLI version, upgrade
  the npm package first before uninstalling or updating.
- **Tombstone after uninstall:** uninstalling leaves a minimal state record (tombstone) so a
  same-product reinstall recognises preserved files instead of treating them as conflicts.
- **Doctor** (`ba-kit doctor`) is read-only — use it to diagnose state issues.
- **Partial/corrupt state** blocks fresh installs, updates, and uninstalls to prevent data loss.
- For recovery: upgrade the npm CLI to the latest version and run `ba-kit doctor` for guidance.

### Trust Boundary

Release archives are downloaded over HTTPS from GitHub Releases. Checksums verify download
integrity under GitHub TLS and release-authority trust — they are not an independent
cryptographic signature or publisher provenance. Always install from the official
`@bakit-org/cli` npm package and the `bakit-org` GitHub organisation.

## Quick Start

### Public Solo Basic (free)

```bash
npm install -g @bakit-org/cli
ba-kit install                    # auto-selects Solo Basic
```

Start using `/ba-start` in Claude Code.

### Private Products

1. Buy BA-kit on [Polar.sh](https://polar.sh/checkout/polar_c_Bd8xfL8VTBQtYpol2MdbS2M5acEFMsjKmDFec0bYVGF)
2. Accept GitHub invite (check email)
3. Install GitHub CLI: `brew install gh`
4. Login: `gh auth login`
5. Install CLI: `npm install -g @bakit-org/cli`
6. Install BA-kit content: `ba-kit install`
7. Start using: `/ba-start` in Claude Code

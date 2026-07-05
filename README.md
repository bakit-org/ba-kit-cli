# BA-kit CLI

AI-powered Business Analyst toolkit for Claude Code.

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

## Runtimes

| Key | Runtime | Scope |
|-----|---------|-------|
| `claude` (default) | Claude Code | Full — skills, agents, hooks, templates |
| `codex` | Codex CLI | Skills only |
| `agy` | Antigravity IDE | Skills only |

Omit `--runtime` to install for Claude Code only (unchanged, backward-compatible
default). Pass a comma-separated list to install for multiple runtimes in one
command, e.g. `ba-kit install --runtime claude,codex,agy`.

## Purchase

https://polar.sh/checkout/polar_c_Bd8xfL8VTBQtYpol2MdbS2M5acEFMsjKmDFec0bYVGF

## Prerequisites

- [GitHub CLI](https://cli.github.com) (`gh`) — `brew install gh`
- `gh auth login` — authenticate with GitHub
- Node.js 18+ (for `npm install -g`)
- Windows only: [Git for Windows](https://git-scm.com/download/win) (provides `bash.exe`, required by the CLI)

## Quick Start

1. Buy BA-kit on [Polar.sh](https://polar.sh/checkout/polar_c_Bd8xfL8VTBQtYpol2MdbS2M5acEFMsjKmDFec0bYVGF)
2. Accept GitHub invite (check email)
3. Install GitHub CLI: `brew install gh`
4. Login: `gh auth login`
5. Install CLI: `npm install -g @bakit-org/cli`
6. Install BA-kit content: `ba-kit install`
7. Start using: `/ba-start` in Claude Code

# BA-kit CLI

Supported customer installer for BA-kit on Claude Code, Codex CLI, and Antigravity IDE.

## Install

```bash
npm install -g @bakit-org/cli@^2.0.0
bakit install
bakit doctor
```

CLI 2.0.0 supports BA-kit runtime payload schema 2 and maintains canonical schema-v3 state. Omit `--runtime` to install Claude Code only; select one or more runtimes explicitly when needed:

```bash
bakit install --runtime claude,codex,agy
bakit update
bakit doctor
bakit version
bakit uninstall --runtime codex,agy
```

There is no `--product` flag. Product selection is access-driven:

- Without GitHub authentication, public Solo Basic is selected automatically.
- With GitHub authentication, the CLI shows the products available to the account.

## Interaction Language

On the first interactive install, BA-kit asks for `Tiếng Việt` or `English`. The choice controls installer messages, later CLI output, and the language BA agents use when communicating with the user. It does not change the separately governed artifact language.

The preference is stored at `$XDG_CONFIG_HOME/ba-kit/config.json`, or `~/.config/ba-kit/config.json` when `XDG_CONFIG_HOME` is unset. Non-interactive installs deterministically select `vi`. Existing installations without a valid preference also continue in Vietnamese. There is intentionally no public `--language` flag.

Each installed runtime receives a managed `ba-kit/preferences.json` projection with `schema_version: 1` and `interaction_language: vi|en`. Install and update write these projections transactionally; uninstall removes them while preserving the global preference.

## Runtime Scope

| Key | Runtime | Standard profile |
| --- | --- | --- |
| `claude` | Claude Code | Native skills, agents, hooks, rules, templates, contract, guardrails |
| `codex` | Codex CLI | Native generated skills, registered agents/hooks, templates, contract, guardrails |
| `agy` | Antigravity | Native skills plus managed Knowledge Item and role/handoff profiles; hybrid enforcement |

Antigravity always provisions `~/.gemini/antigravity` as the canonical support root, then also installs into detected `~/.gemini/antigravity-cli` and `~/.gemini/antigravity-ide` homes. Its interactive runtime does not expose a deterministic headless hook surface, so preflight/audit enforcement remains wrapper/operator-driven.

The standard payload includes the four canonical delegated roles: `ba-researcher`, `ba-documentation-agent`, `ux-designer`, and independent read-only `ba-reviewer`. A producer cannot approve its own work. Required review receipts are bound to source hashes, and missing or stale receipts block compilation/package promotion.

### Solo Basic Scope

Solo Basic installs exactly five skills (`ba-start`, `ba-do`, `ba-next`, `ba-impact`, `brainstorm`) plus templates and core contract content. It does not install standard-profile agents, hooks, scripts, settings, framework files, pip packages, or tool lanes.

## Prerequisites

- Node.js 18+.
- Public Solo Basic: `jq` and `curl`.
- Private products: GitHub CLI (`gh`) authenticated with `gh auth login`.
- Windows: Git for Windows, which provides `bash.exe`.

## State, Transactions, And Recovery

Canonical state is stored at:

```text
~/.local/share/ba-kit/runtime-state/{runtime}/state.json
```

Schema-v3 state records the payload schema, product/profile/version, runtime targets, registrations, interaction-language projections, managed hashes, and preserved-file status. Legacy and schema-v2 installs migrate forward during install/update.

Install, update, and uninstall are transactional across selected runtimes. Journals live under `~/.local/share/ba-kit/transactions/`; an interrupted transaction is recovered before a later mutation. Malformed journals or state fail closed. `bakit doctor` is read-only and reports the recovery issue.

Files are removed or replaced only while their hashes still match BA-kit-managed content. User-modified and retired files are preserved as `preserved-modified`. Uninstall may leave an `uninstalled-with-preserved-files` tombstone so a later reinstall does not misclassify those files; `bakit version` and `bakit doctor` report that state as uninstalled, not active. Codex hook cleanup handles both direct and nested hook entries while preserving user-owned hooks.

Runtime assets and metadata files are checked against approved runtime roots after realpath resolution. Symlinked parents/files that escape those roots fail closed before mutation.

`RECOVERY_REQUIRED.json` prevents an older CLI from mutating a schema-v3 installation. Do not delete the barrier. Upgrade the npm CLI and run:

```bash
bakit doctor
bakit update
bakit doctor
```

Doctor checks schema-v3 state, managed path containment and hashes, transaction health, native Reviewer/orchestration capabilities, and Claude/Codex registrations. Repair uses `bakit update` after any malformed external configuration is corrected.

## Trust Boundary

The CLI validates the release manifest, runtime component contract, and extracted file hashes before mutation. GitHub release checksums protect download integrity under GitHub TLS and release-authority trust; they are not an independent publisher signature. Install only the official `@bakit-org/cli` package and releases from the `bakit-org` GitHub organization.

## Release Compatibility

BA-kit archives with `runtime_payload_schema: 2` require CLI 2.0.0 or newer. Release order is CLI first, then the BA-kit archive. npm publishing, Git tags, GitHub Releases, and rollout require explicit maintainer authorization.

Never downgrade schema-v3 state in place. If a release must be rolled back, use transaction recovery or a forward CLI/BA-kit patch and keep project artifacts plus review receipts unchanged.

## Quick Start

### Public Solo Basic

```bash
npm install -g @bakit-org/cli@^2.0.0
bakit install
bakit doctor
```

### Private Products

1. Accept the product's GitHub organization invitation.
2. Install and authenticate GitHub CLI with `gh auth login`.
3. Install `@bakit-org/cli` 2.0.0 or newer.
4. Run `bakit install --runtime <runtime-list>`.
5. Run `bakit doctor` before starting `/ba-start` or `/ba-do`.

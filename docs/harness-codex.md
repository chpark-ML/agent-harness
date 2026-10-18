# harness-codex — shared workflows in Codex

Installs the same canonical skill bodies used by Claude Code into Codex's supported skill discovery path. Shared principles and the selected workflow rules enter through a marked `AGENTS.md` block. [ADR-0016](adr/0016-codex-workflows.md) explains the delivery choice; the inventory and execution evidence live in [agent-layer](agent-layer.md).

## Install and update

Run from a consumer repository's root:

```bash
curl -fsSL https://raw.githubusercontent.com/chpark-ML/agent-harness/main/install.sh | bash -s -- --agent codex --scope project
```

For both hosts:

```bash
curl -fsSL https://raw.githubusercontent.com/chpark-ML/agent-harness/main/install.sh | bash -s -- --agent both --scope project
```

The bootstrap defaults to `--agent claude`, `--scope user` and the development profile. Codex supports the shared `core`, `dev`, `research` and `slides` workflow profiles. For example:

```bash
curl -fsSL https://raw.githubusercontent.com/chpark-ML/agent-harness/main/install.sh | bash -s -- --agent codex --scope project --profile research,slides
```

Run the same bootstrap again to update from the current source. With a downloaded or piped script, the bootstrap fetches the source from GitHub; `--ref` selects its revision. A checkout uses its own source unless `--ref` is supplied. The selected Codex profiles replace the previous Codex selection. Other profiles, third-party dependencies and `--with-tools` keep their Claude behavior with `--agent both`; Codex keeps its host tools.

Start a new Codex session after installation. Skills remain selective: Codex discovers their descriptions and reads a body when needed. Superpowers remains the implementation owner when available; otherwise the skills use the host's existing workflow. Browser review and rendering require an available host adapter or renderer.

## Scope and ownership

| Scope | Instructions | Payload and receipt | Skill discovery |
|---|---|---|---|
| Project | `AGENTS.md` | `.agents/agent-harness/` | `.agents/skills/` |
| User | `${CODEX_HOME:-$HOME/.codex}/AGENTS.md` | `${CODEX_HOME:-$HOME/.codex}/agent-harness/` | `$HOME/.agents/skills/` |

Project links and receipt paths survive moving or cloning the whole installed tree. User paths must be absolute. The filesystem must support real symlinks; Git Bash installations that substitute copies are refused before replacement. Native Codex execution is verified on macOS and its loader is checked on Linux in CI. Each skill link reaches a copied canonical package, including its references and attribution, so the original source checkout can disappear. To add a profile absent from that snapshot, rerun the bootstrap or supply a complete checkout with `--source`.

The installer owns only its payload, recorded skill links and the block between `agent-harness:codex:start` and `agent-harness:codex:end`. It preserves consumer instruction bytes and later edits outside that block. Conflicting skills, changed managed files or an edited block stop updates and removal. Do not edit the managed snapshot; put project verification skills and other customizations outside it.

`AGENTS.override.md` at the target scope would hide the installed block, so installation and doctor report that conflict. The generated instruction file must fit `HARNESS_CODEX_DOC_LIMIT` (default 32768 bytes). If the host's `project_doc_max_bytes` differs, match the limit explicitly. Parent instructions also count toward Codex's combined budget; this file-size check does not establish the combined runtime cost.

Codex TOML, permissions, approvals and Claude settings remain consumer-owned. This adapter delivers workflow instructions and skills; Claude hooks, permission tiers, output styles, slash commands and plugin dependencies retain their Claude integration. Codex uses its own enforcement and available tools.

## Check, preview and remove

The project snapshot includes its own management executable:

```bash
bash .agents/agent-harness/payload/plugins/harness-core/bin/harness-codex doctor
bash .agents/agent-harness/payload/plugins/harness-core/bin/harness-codex init --dry-run
curl -fsSL https://raw.githubusercontent.com/chpark-ML/agent-harness/main/uninstall.sh | bash -s -- --agent codex --scope project --dry-run
curl -fsSL https://raw.githubusercontent.com/chpark-ML/agent-harness/main/uninstall.sh | bash -s -- --agent codex --scope project
```

For user scope, the installer prints the exact executable path; pass `--scope user`. A Claude install also exposes `harness-codex` through the existing terminal shim. Codex-only installs use the printed path and do not overwrite global shell commands.

`doctor` verifies receipt hashes, links and the instruction block. It does not run a model. Destination replacements are staged before mutation; failed updates or removal roll back the previous payload, links and instructions. If recovery itself fails, the error names the retained recovery directory.

## Verification

The shipped verifier tests ownership, relocation, user scope, byte preservation, instruction limits and failed-write recovery under Bash 3.2. The repository bootstrap verifier exercises real install/removal routes and a real local Git fetch; its Claude network boundary is a logged fixture.

```bash
make verify-codex
make verify-codex-loader
```

The second command requires Codex CLI. It uses the actual app-server skill loader, removes a skill file as a broken control, restores it and verifies disappearance after uninstall. It makes no model request and runs in CI. A separate actual Codex model execution and its limits are recorded in [agent-layer §4b](agent-layer.md#4b-what-to-expect--what-is-measured-and-what-is-not).

The supported discovery and instruction mechanisms are documented by OpenAI: [skills](https://learn.chatgpt.com/docs/build-skills) and [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

# ADR-0016 — Deliver the shared workflows to Codex

**Status:** Accepted, 2026-10-18

## Context

After requesting the broad pstack integration, the owner explicitly required it to work in Codex as well as Claude Code. The existing plugin install proved only Claude delivery. Repository instructions alone did not register the consumer-facing skills in Codex.

This is an owner-requested runtime adapter. It does not imply two observed incidents or admit a second implementation framework. Canonical workflow content remains in the existing packages.

## Decision

Use Codex's documented `.agents/skills` discovery, which accepts symlinked skill directories, and its `AGENTS.md` instruction mechanism. `harness-codex` copies selected canonical packages into an owned snapshot, links their skills into the proper discovery scope and compiles shared principles and rules into one marked instruction block. Bodies, references, scripts and attribution stay together. Host-specific paths and unavailable-tool fallbacks are stated in the shared bodies.

The bootstrap and removal scripts accept `--agent claude|codex|both`; the existing default remains Claude. A combined install resolves Codex content from the marketplace source actually selected by Claude, rather than mixing a local checkout with remote plugin content. Project installs stay inside the repository. User instructions follow `CODEX_HOME`, while user skills follow `$HOME/.agents/skills`. A receipt records file hashes and owned links. Conflicts and edited managed content fail before replacement; staged changes retain rollback data through completion.

Codex has a native plugin system too. Direct skill discovery provides the project/user scope boundary needed here without editing the user's TOML plugin registrations. This choice makes no claim that native Codex plugins cannot load the packages. The actual loader is checked instead of inferring discovery from file existence.

Host permissions remain authoritative. This adapter does not translate Claude hooks or permission settings, select a Codex model, create browser connections, install third-party dependencies or arrange delegation. Shared instructions use the implementation workflow and tools actually available in the current host.

## Verification and consequences

The shipped Bash verifier covers the ownership contract and failed-write recovery. A repository verifier covers bootstrap selection and pinned source retrieval. CI pins the exercised Codex CLI and queries its actual skill loader with a missing-file control, reload and uninstall. An actual Codex session must read and execute the engineering body before release.

The [single source of truth](../agent-layer.md) records measured coverage, context figures and remaining limits. Claude quality and trigger measurements are not transferred to Codex. `AGENTS.md` file size is guarded, but aggregate instruction limits and existing host policies still require the native runtime.

The owned snapshot makes installed workflows independent of the original checkout. Updates need a complete source for selected profiles. Consumer modifications belong outside the snapshot. No separate Codex skill fork or duplicate skill inventory is introduced.

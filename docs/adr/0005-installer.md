# ADR-0005: The installer is an overlay tree, two tiers, marker-based merging, and a manifest

- **Status**: Accepted — point 3 (marker-based hook merging) is superseded by [ADR-0008](0008-plugin-declarative-split.md)
- **Date**: 2026-08-06

## Context

The installer touches a consumer's `.claude/settings.json`. That file holds things we did not create — model settings, plugins, the user's own hooks and permissions — and there is no way to get them back once lost.

Two reference assets each had half an answer. One never overwrote `settings.json` wholesale: it parsed and re-serialised with jq, left a timestamped backup before every write, and had install and uninstall call the same function in opposite directions. The other split files into two tiers (overwrite / first time only) and copied them from a hand-maintained `for` loop.

Neither addressed one problem: the first merges a **single key** in `settings.json`. Here we have to mix several hook registrations inside an array with the consumer's own, and later pick out only ours.

## Decision

Four things.

**1. The overlay tree is the file list.** Everything under `<overlay>/files/` is copied to the matching consumer path. `install.sh` walks it with `find`, so there is no list to maintain — add a file and it installs, and you cannot forget to register it.

> *After ADR-0008*: this property did not disappear, it **moved**. Hooks, skills, commands and verifiers became plugin components, and the platform discovers them at convention paths, so there is still no list. The declarative payload that remains is seven files, so `harnessctl` plans explicitly instead of walking a tree — only module rules are globbed, from `rules/<module>/*.md`. The conclusion, that no list has to be maintained, is the same; only the means differ.

**2. Two tiers.** *managed* is overwritten with the latest on reinstall. *template* is copied once and belongs to the consumer thereafter (`CLAUDE.md`, the path-guard config files). Each overlay's `templates.txt` declares which is which.

> *After ADR-0008*: still true. Only the tier declaration moved, from `templates.txt` into harnessctl's planning code (`add` / `addt`).

**3. Marker-based hook merging.** *(→ **Superseded** by [ADR-0008](0008-plugin-declarative-split.md). Hooks are now registered by the plugin in `hooks/hooks.json` against `${CLAUDE_PLUGIN_ROOT}`, and the installer neither reads nor writes the `hooks` block of `settings.json`. The marker, the strip-then-append, and the jq programs that existed for both were deleted. The text below stays as a record.)* Every harness hook installs under `.claude/hooks/harness/`, and that path fragment appears in the registration's command string. Merging is **strip-then-append** — for each event, remove only the registrations containing the marker, then append the fragment's. That makes reinstall idempotent, keeps uninstall away from the consumer's hooks, and lets a hand-edited `settings.json` converge instead of accumulating duplicates.

**4. `.claude/harness-manifest.json` is the receipt for everything else.** The permission strings actually added, the scalar keys set, the paths of JSON containers we created, the line appended to `.gitignore`, the list of installed files, the selected modules. Uninstall reverses this receipt and nothing else.

> *After ADR-0008*: the fields are unchanged. What shrank is the scope of "everything else" — with hooks out of the merge, all the installer touches in `settings.json` is the three permission tiers and one scalar (`includeCoAuthoredBy`), and the receipt records exactly that much.

Two properties follow:

- **Every install first reverts the previous install, then reapplies.** Additions are always computed against the original state, so reinstalls do not accumulate.
- **Dropping a module deletes its files.** The manifest knows the previous list, so the set difference is the removal set. No separate partial-uninstall command is needed.

Taken directly from the reference installer: all preflight checks pass before any write (fail-before-mutate), timestamped backups with a counter to survive same-second collisions, a `BASH_SOURCE` guard against `curl | bash`, a smoke test straight after install, and a "what it touches" audit section in the README.

## Consequences

- `settings.json` is re-serialised by jq, so **the formatting changes** (two-space indent; key order preserved). The first install's diff mixes in a formatting change. The README says so.
- ~~Our hooks are added as a **separate group** under the same matcher rather than joining the consumer's existing group.~~ → After ADR-0008: **the installer does not touch `hooks` at all.** The consumer's hook block is byte-identical before and after install, and `scripts/verify-install.sh` asserts it ("the consumer's `.hooks` block is byte-identical after install"). The machinery for holding an ownership boundary is gone because the boundary is gone.
- Permission strings the consumer already had survive uninstall, because we never "added" a string we did not add.
- Delete the manifest and symmetric removal becomes impossible. `install.sh --uninstall` stops without one.
- If a managed path holds a file the harness does not own, the install **stops without writing anything**.
- `settings.json.bak-*` snapshots survive uninstall. That is a deliberate safety net, and the uninstaller prints the path.
- *(Added after ADR-0008)* Uninstall became two commands. `harnessctl uninstall` reverses the receipt and leaves the plugins alone, so it also prints `claude plugin uninstall ... --prune`.

## Alternatives considered

- **Replace `settings.json` wholesale with ours** (one reference harness's approach) — simplest, and it erases the consumer's configuration.
- **Add a marking key to hook registrations** (something like `"_harness": true`) — puts a key in that the Claude Code schema does not have, and ownership is lost the moment a user edits it away. A path marker cannot be deleted, because the hook needs it to work at all.
- **An explicit file array inside install.sh** (the reference installer's approach) — the list is visible during review, but it introduces a failure mode where adding a file means forgetting to register it. Deriving from the tree removes that failure mode entirely.
- **A per-module partial-uninstall command** — redundant, since `--with` already handles it as a set difference.

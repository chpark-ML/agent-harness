# ADR-0007: There are two install levels, divided by audience

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

The first version supported project-level installs only. Both reference harnesses were project-level, and the reasoning was that team sharing needs committed files. But that reasoning covers only *some* of the assets.

Guards carry the opposite logic. `secret-scrubber` exists so that a key never leaks — and under a per-project install, **the repository that forgot to install is exactly the repository where the accident happens**. Somebody else's repo cloned for five minutes, a scratch directory thrown together in a hurry: nowhere near a harness install, and precisely where a careless command comes from. A guard with a hole in its coverage is weak not in proportion to the hole's size but to *where the hole is*.

One more observed fact: the `~/.claude/settings.json` of the user who built this repository had zero hooks, no `CLAUDE.md`, and one permissions key (`defaultMode`). An empty user level is the default state.

Constraints confirmed in the documentation:

- **Hook registrations merge across levels** ("Hook entries merge across settings levels rather than replacing each other"), and an identical handler runs once. But the two levels register different command strings (`$CLAUDE_PROJECT_DIR/...` versus an absolute path), so they are not treated as the same handler and **run twice**. *(→ After [ADR-0008](0008-plugin-declarative-split.md) this condition cannot arise. The installer registers no hooks, so there is no way for two levels to produce different command strings.)*
- **Permissions merge across scopes** as well.
- **`${CLAUDE_PROJECT_DIR}` is documented**, but there is no documented variable pointing at the user config directory from inside a hook.
- **Path-scoped rules files are documented for the project level only.** There is no mention of `~/.claude/rules/`.

## Decision

There are two install levels, divided **by audience, not by convenience**.

| | Project (default) | `--user` |
|---|---|---|
| Location | `<project>/` + `<project>/.claude/` | `~/.claude/` (or `$CLAUDE_CONFIG_DIR`) |
| Audience | the **team** that clones this repository | **you**, working on this machine |
| Committed | yes | no |
| Applies to | that project | every project, including a five-minute clone |

**The recommended default is `--user`.** Put guards, skills, commands and principles on the machine once, and add a project install only when *the team needs the same conventions* and when *project-specific rules and settings are needed*.

Three things follow:

1. **Strip the `.claude/` prefix.** The user config directory *is* that `.claude`. `map_rel` remaps overlay paths to the level, so both levels share one code path.
2. **`--user` does not install `rules/`.** There is no evidence they are read at user level, so installing them would produce *files that look like they work and do nothing*. The installer prints what it skipped and points at a project install. Standing instructions at user level go in `~/.claude/CLAUDE.md`.
3. **Warn when both are installed.** Hooks run twice — the blocking outcome is the same, but informational hooks print over each other. We do not switch one off automatically, because which one to switch off is the user's call.

The ownership marker changes too: `.claude/hooks/harness/` → **`/hooks/harness/`**. When `CLAUDE_CONFIG_DIR` is set the user config directory is not named `.claude`, and a marker that can vanish is not a marker.

### Update (after [ADR-0008](0008-plugin-declarative-split.md))

The decision to divide **by audience**, and the table above, still hold. The implementation and three of the consequences changed.

- **The `--user` flag became `harnessctl init --scope user|project`.** And the scope surface went from one to two — the plugin half is decided by the plugin system's own `claude plugin install --scope user|project|local`, and the declarative half by harnessctl's `--scope`. They are independent, and matching them up is the user's job. `harnessctl --scope local` does not exist yet (backlog).
- **Point 1 (`map_rel`) is gone.** Instead of a function remapping the overlay per level, `harnessctl` fixes `TARGET`, `SETTINGS`, `MANIFEST` and `CONFIG_DIR` once from the scope and plans on top of them. `--scope user` creates no `.gitignore` and does not require `.git`.
- **Point 2 (rules are project-only) still holds, and now governs `harnessctl`.** The absence of a documented `~/.claude/rules/` has not changed, and no path opened on the plugin side either — `rules` is not a plugin component. So rules can only be delivered by `harnessctl` at project scope, and at user scope it prints what it skipped. `verify-install.sh` asserts both properties.
- **Point 3 (warn when both are installed) is retired.** Only one thing registers hooks — the plugin — so however many scopes you run `harnessctl init` in, hooks register once. Initialising two scopes is now ordinary, non-interacting behaviour, and each scope keeps its own manifest.
- **The `/hooks/harness/` ownership marker is retired too.** Its purpose was to pick our hook registrations out of `settings.json`, and there are no registrations to pick. The installer's only basis for ownership is now the manifest.

## Consequences

- A user-level install does not require `.git` and does not create a `.gitignore`.
- ~~Hook registrations embed a real path (`$HOME/.claude/...`, or an absolute path under a custom config dir). There is no documented alternative.~~ → After ADR-0008: hook registrations are gone, so this problem is gone. The plugin uses the documented `${CLAUDE_PLUGIN_ROOT}` anchor, and the path points at the plugin cache whatever the install scope.
- The `protected-paths` hook now reads the **union** of the user and project configs. If machine-wide protection disappeared because a project has its own list, the guard would be weakest in a project nobody configured.
- A `--user` install **is not shared with the team.** When team conventions are needed, a project install is still the answer. ~~You then see the duplicate-hook warning.~~ → After ADR-0008: the two scopes simply run together, with no warning.
- The verification burden grew. `scripts/verify-install.sh` uses `CLAUDE_CONFIG_DIR` to point at a scratch directory and checks the user-level round trip too — it never touches the real `~/.claude`, so it runs unchanged in CI and on a developer's machine.

## Alternatives considered

- **Project level only** (the first version) — team sharing works, but the guards keep a hole, and the hole is exactly where the accidents are.
- **User level only** — the guards are complete, but nothing reaches the team and path-scoped rules cannot be used.
- **Automatically skip the project hooks when both are installed** — no duplication, but remove the user level later and the project is silently undefended. Warn, and let the user decide. *(After ADR-0008 the problem itself is gone, so this alternative is moot.)*
- **Install to `~/.claude/rules/` and hope it works** — that is placing a file on no evidence, and a rules file with no force is worse than none.

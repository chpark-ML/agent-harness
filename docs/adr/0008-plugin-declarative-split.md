# ADR-0008: Split the harness into a plugin and a declarative installer — the platform drew the line

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

The first version was one file-copying installer ([ADR-0005](0005-installer.md)). It copied an overlay tree into the consumer's `.claude/` and merged `settings.json` with jq. It worked, and it cost three things. Updates depended on the consumer re-running it; hook registrations lived inside the consumer's `settings.json` mixed with theirs (the marker and strip-then-append machinery existed for that reason alone); and there was no concept of a version at all.

The Claude Code plugin system solves all three. In exchange it cannot carry every harness asset. What it can and cannot carry is not a matter of taste — it is written down.

| Asset | Can a plugin carry it | Basis |
|---|---|---|
| Hooks | ✅ `hooks/hooks.json` | A component. Paths anchor on `${CLAUDE_PLUGIN_ROOT}` |
| Skills, commands, agents | ✅ `skills/`, `commands/`, `agents/` | Components |
| Executables | ✅ `bin/` | "Executables added to the Bash tool's `PATH` while the plugin is enabled" |
| Dependencies on external plugins | ✅ `dependencies` | [ADR-0009](0009-external-dependencies.md) |
| Permissions (allow, ask, deny) | ❌ | A plugin's `settings.json`: "only the `agent` and `subagentStatusLine` keys are supported" |
| `includeCoAuthoredBy` | ❌ | Same reason |
| `CLAUDE.md` | ❌ | "A `CLAUDE.md` file at the plugin root is not loaded as project context" |
| `.claude/rules/**` | ❌ | Not on the component list. There is no documented `~/.claude/rules/` either ([ADR-0007](0007-install-levels.md)) |
| Consumer-owned config templates | ❌ | Plugin files live in a cache that updates replace. Not a place for a value the consumer edited to survive |

The four it cannot carry have no workaround. Permissions could be imitated with hooks, but that means reimplementing the permission model; imitating `CLAUDE.md` with a skill turns a standing instruction into a conditional one.

## Decision

The harness ships in two pieces, and **which piece something goes in is decided by one question: can a plugin carry it?**

**1. The plugin** — `harness-core` and the profiles. Six guard hooks, the skills, the `/verify` command, the hook verifiers, and `bin/harnessctl`. Claude Code loads, updates and scopes it directly.

> *After 2026-08-11*: the hook count has moved since (a seventh guard shipped). [`agent-layer.md`](../agent-layer.md) §3 is the source of truth for current numbers — the figures here are a record of that moment.

**2. `harnessctl init`** — the three permission tiers, `includeCoAuthoredBy`, `CLAUDE.md`, `.claude/rules/harness/**`, and two path-guard config templates. The plugin ships it in `bin/`, so it needs no separate install.

`harnessctl` keeps every property of ADR-0005 that still earns its place — two tiers (managed / template), all preflight checks before any write, timestamped backups with a counter, parse-and-re-serialise on `settings.json`, and **symmetric removal driven by the manifest receipt**. The one thing gone is hook merging, and with it the marker, the strip-then-append, and the jq programs that served them.

**The declarative payload lives in `harness-core` and nowhere else.** Plugin caches are separate per plugin and cannot reach across with `../`, so scattering the payload per profile would send `harnessctl` hunting through another plugin's cache. Profile selection is absorbed by the `harnessctl init --with dev,research` flag instead. Skills go the other way, into their own profile — the platform loads them from each cache directly.

`install.sh` calls the two halves in order so one command finishes the install. A session restart is needed for Claude Code to *load* the plugin, not to *write* the declarative half, and a script running in a shell can call `harnessctl` at its path in the plugin directory.

**The manifest states a `version`.** Leaving `version` empty makes the git commit SHA the version, which updates automatically on every commit — but using `claude plugin validate --strict` as a CI gate requires it to be stated. The price is plain: shipping a change means bumping the version.

## Consequences

- **No `hooks` block appears in the consumer's `settings.json`.** The installer neither reads nor writes it, and `scripts/verify-install.sh` asserts `.hooks` is byte-identical before and after install. The machinery ADR-0005 worked hardest on became entirely unnecessary.
- **Plugin files cannot be opened in the consumer's tree.** They live in a cache that updates replace. So a hook's block message is the **only interface** a user can reach — it has to carry what was caught, how to get past it, and a link to `docs/hooks/<name>.md`. ADR-0002's requirement went from advice to necessity.
- **CI gained a job.** `make verify-plugins` needs the Claude CLI, so it runs separately — a CLI or registry problem should not drag the behavioural jobs down with it. The other two jobs (ubuntu bash 5, macOS bash 3.2) run on jq, git and python3 alone, and on a machine without the CLI `make verify` simply skips that item.
- **A commit alone delivers nothing to users.** `version` bump joins the new-hook artifact bundle as its own item (`CLAUDE.md` §2).
- The install is one command, but the guards only start working after a session restart — plugins load at session start. The script says so at the end.
- **There are now two scope surfaces.** The plugin half uses `claude plugin install --scope user|project|local`, the declarative half `harnessctl init --scope user|project`. They are independent and matching them is the user's job (`harnessctl` has no `local` yet). Conversely, [ADR-0007](0007-install-levels.md)'s duplicate-hook warning is gone — however many scopes you run `harnessctl init` in, only the plugin registers hooks.
- **Uninstall is two commands too.** `harnessctl uninstall` reverses the receipt, and `claude plugin uninstall ... --prune` removes the plugins. The first prints the second.

## Alternatives considered

- **Plugin only** — the cleanest delivery, but half the harness never ships. A bundle of guards with no permission tiers, no five-principle `CLAUDE.md` and no rules is not a harness.
- **Installer only** (keep the first version) — it works, but there is no update path, no version, no external plugin dependencies, and hook registrations keep intruding into the consumer's `settings.json`. It is the choice that leaves you hand-building what the platform provides.
- **Load skills with `@skills-dir` and no marketplace** — the lightest option. But no version, no team delivery path, and hooks and `bin/` cannot be carried at all, so the guards drop out entirely.
- **Scatter the declarative payload per profile** — matches the module boundary in shape, but plugin caches are separate, so `harnessctl` would have to cross into another one. The `--with` flag does the same job without crossing a cache boundary.

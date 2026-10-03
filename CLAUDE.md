# CLAUDE.md — working on agent-harness itself

This repository ships a Claude Code harness as plugins plus a declarative installer. Read [the consumer defaults](plugins/harness-core/declarative/CLAUDE.md) before non-trivial work; they apply here too. Match the user's language. Shipped content is English except §8's named exceptions.

## 1. What goes where

| Artifact | Location |
|---|---|
| Shared hook, skill, command, executable or output style | `plugins/harness-core/{hooks,skills,commands,bin,output-styles}/` |
| Profile-specific skill | `plugins/harness-<profile>/skills/` |
| Shipped verifier | `plugins/harness-core/scripts/` |
| Permissions, settings scalars, consumer `CLAUDE.md`, rules and config templates | `plugins/harness-core/declarative/` |
| External plugin | The profile's `dependencies` |
| Repository-only tools | `scripts/` and `.claude/` |
| Superpowers design records | `docs/superpowers/{specs,plans}/`; frozen after merge |

A plugin cannot distribute permissions, `CLAUDE.md` or rules; `harnessctl` writes them ([ADR-0008](docs/adr/0008-plugin-declarative-split.md)). Keep declarative payloads in core because plugin caches cannot reference siblings. Profile skills stay in their own plugins.

## 2. A new hook is a bundle of artifacts

All required; use the same `<name>` throughout:

1. `plugins/harness-core/hooks/<name>.sh`
2. `plugins/harness-core/scripts/verify-<name>.sh`, with 8+ cases
3. `docs/hooks/<name>.md`
4. Registration in `plugins/harness-core/hooks/hooks.json`, anchored on `${CLAUDE_PLUGIN_ROOT}`
5. `docs/agent-layer.md` inventory update
6. Core manifest `version` bump
7. Blocking hooks: independent incident cases in `evals/incidents.sh`, drawn from §2's accident table in agent-layer rather than from the regexes

Use [harness-reviewer](.claude/agents/harness-reviewer.md) for bundle audits. A version bump changes the cache key but does not update an installed machine: the installer must run `plugin update`, and install any newly unsatisfied dependencies. Reinstalling an already-present dependency can clear its auto-installed flag; do not do that indiscriminately.

## 2b. A new skill is a bundle too

1. `plugins/harness-<profile>/skills/<name>/SKILL.md`, with a quoted description
2. `evals/trigger/<name>.json`: 6 positive and 6 negative cases, including neighboring skills' work
3. `make bench-trigger` measurement recorded in agent-layer §4b
4. agent-layer §3 inventory update
5. One end-to-end execution of the body before merge
6. That plugin's `version` bump

A negative case checks where work went, not just whether our skill stayed silent. Use repeated trials (default 3), a positive control and a fixture satisfying the prompt's premises. Read agent-layer §4b's instrument limits before interpreting a zero. Trigger success does not verify the body.

## 2c. A new `bin/` executable is a bundle too

1. Executable `plugins/harness-core/bin/<name>` with catches / scope / bypass in its header
2. `plugins/harness-core/scripts/verify-<name>.sh`, using §4's case policy
3. `docs/<name>.md`
4. A shim through `install.sh`'s existing `bin/` glob; no hook registration
5. agent-layer inventory update
6. Core `version` bump

Plugin `bin/` reaches the Bash tool's PATH, not the user's terminal; the shim supplies the documented terminal command.

## 2d. And every bundle moves the published numbers

Run `make verify-all` to derive the check total; update its five published copies in both READMEs and agent-layer. Do not guess counts.

CI measures the current installed plugin's always-on cost. After the first PR run, republish the measured worst case in both READMEs, agent-layer and `Makefile`. A developer's stale cache cannot price the new tree; plan for the CI round trip.

## 2e. An output style is a bundle too — and it is the only one in the system prompt

1. `plugins/*/output-styles/<name>.md`: `name`, quoted `description`, explicit `keep-coding-instructions`
2. Selecting `outputStyle` scalar in `declarative/settings-fragment.json`, namespaced `<plugin>:<style name>`
3. `docs/output-styles.md`
4. Frontmatter discovery and context-budget accounting
5. Installer cases proving selection and preservation of a consumer's own style through install and uninstall
6. agent-layer update and plugin `version` bump
7. One real execution with the style selected

The verifier derives the selector from frontmatter; do not hardcode a duplicate name. `keep-coding-instructions` defaults to false and removes built-in coding instructions. State the value deliberately. Do not use `force-for-plugin` without an explicit case for overriding the consumer's selection. Only one style is active; budget the largest, not the sum. §2d applies.

## 3. The hook contract

- Shipped scripts and executables use **bash 3.2 and jq only**. No Python, Node, `mapfile`, associative arrays or `${x^^}`. Repository-only `scripts/` are exempt ([ADR-0002](docs/adr/0002-hook-contract.md)).
- Under `set -u`, expand possibly-empty arrays as `"${a[@]+"${a[@]}"}"`.
- Hooks parsing stdin self-disable with one stderr line and exit 0 when jq is missing. Hooks that never read stdin need no jq guard.
- Only a blocking hook exits 2; informational hooks always exit 0.
- A block message states what was caught, how to proceed and `docs/hooks/<name>.md`. Consumers cannot read the cached script as their interface.
- Headers state catches / scope / bypass.

## 4. The verification mandate

```bash
make verify-all
make verify BASH=/bin/bash
```

Run both before merge; `verify` alone does not validate the published total. `make bench*` costs model sessions and is not a CI gate.

- Use `_verify-lib.sh` for shipped verifiers and `scripts/_check-lib.sh` for repository checks; do not add another runner.
- Cover no-op, block and boundary inputs. When widening a guard, pin a similar input that must still pass. Add the incident regression before the fix.
- Cover each environment-dependent path. Write portable reproductions where possible, such as `PYTHONIOENCODING=ascii` for encoding failures. Python verifiers use `errors='replace'` when reporting.
- A repository verifier needs self-tests when it can falsely reject valid input. Prevent omissions with discovery globs first; self-evident assertions need no tests mirroring their implementation.
- Skill, rule, agent and style frontmatter must parse; quote descriptions. Skill descriptions carry explicit negative routing and the second-language triggers declared in `.claude/trigger-langs`.
- Installer changes must pass `scripts/verify-install.sh`, including canonically identical settings after uninstall and preservation of user edits.
- Prose procedures require an end-to-end execution; structural checks cannot establish that the instructions work.

## 5. `docs/agent-layer.md` is the single source of truth

Scope, inventory and backlog belong only in [agent-layer](docs/agent-layer.md), not a new roadmap or README expansion ([ADR-0004](docs/adr/0004-single-source-of-truth.md)). Mirror published verification and cost figures as §2d requires.

## 6. Commits and PRs

- Branch `{feat,fix,chore}-<slug>`; PR title `[<slug>] <description>`, at most 70 characters.
- Verb-first commit subject; explain why in the body. Split commits by meaning.
- No AI attribution in commits or PRs ([ADR-0006](docs/adr/0006-no-ai-attribution.md)). This repository does not install its own guards.
- Structural harness changes and content additions go in separate PRs.
- Read `.claude/harness-gaps.md` before opening a PR. Raise repeated observations in the PR's Notes; keep unrelated repairs separate.

## 7. Resisting over-design

A new hook, rule or module requires a problem that actually occurred twice. Record candidates as ⏳ in agent-layer §7, naming the accident they address. Prefer removal over speculative defenses.

## 8. What stays in Korean, and why

English is the shipped default. Preserve these exceptions:

- `README.ko.md`: mirror of `README.md`; update both together.
- `.claude/harness-gaps.md`: append-only ledger; translating it rewrites history.
- Benchmark prompts in `scripts/bench-*.sh` and quoted measurement inputs: translating changes the experiment. A translated run is a new dated measurement.
- Korean trigger and negative-routing clauses in skill descriptions: the measured deployment choice declared in `.claude/trigger-langs`. Do not require Korean in a deployment declaring another language; do not silently translate existing measurement inputs.

# AGENTS.md

Conventions for any agent working in or reviewing this repository. **This file is a summary — [`CLAUDE.md`](CLAUDE.md) is the full version, and the reasoning lives in [`docs/adr/`](docs/adr/).** Where the two appear to disagree, `CLAUDE.md` wins and the difference is a bug worth reporting.

This repository *is* a Claude Code harness: guard hooks, skills, and a declarative installer, shipped as plugins. Reviews that only check general correctness miss most of what goes wrong here, because most of what goes wrong is a contribution that is *incomplete* rather than incorrect.

## The nine things a review should actually check

1. **bash 3.2 and `jq` only.** Shipped hooks and `bin/` executables run on stock macOS `/bin/bash` — no `mapfile`, no associative arrays, no `${x^^}`, no python or node. Under `set -u`, expand a possibly-empty array as `"${a[@]+"${a[@]}"}"`. ([ADR-0002](docs/adr/0002-hook-contract.md))

2. **Only a blocking hook exits 2.** Everything else exits 0 no matter what. An informational hook that stops a turn is a bug. A hook that reads stdin self-disables with one stderr line and `exit 0` when `jq` is absent — a missing dependency must never block work.

3. **A block message is the only interface a consumer has.** They cannot open the hook file; it lives in the plugin cache. The message carries *what was caught*, *how to get past it*, and a pointer to `docs/hooks/<name>.md`.

4. **A contribution is a bundle, and missing one artifact makes it unfinished.** A new hook owes six ([`CLAUDE.md`](CLAUDE.md) §2): the script, a verifier with 8+ cases, `docs/hooks/<name>.md`, registration in `hooks/hooks.json` anchored on `${CLAUDE_PLUGIN_ROOT}`, an update to `docs/agent-layer.md`, and a `version` bump. A skill owes a trigger eval (§2b). A `bin/` executable owes a shim in `install.sh` rather than a `hooks.json` entry (§2c). The `<name>` must be identical everywhere or the audit cannot run mechanically.

5. **The `version` bump is not optional.** The plugin manifest states a `version`, so committing alone delivers nothing — Claude Code sees the same string and keeps its cache. A behaviour change with no bump is a change no consumer receives.

6. **A guard merged without verification is decoration.** ([ADR-0003](docs/adr/0003-verification-mandate.md)) Cases come in three kinds — **no-op** (input the hook must not touch), **block**, and **boundary** (something that resembles what is blocked and must pass). The third is the one that earns its keep: a check that cries wolf gets switched off, and switched off is the same as absent. `make verify BASH=/bin/bash` is the gate before merging, because that is the 3.2 floor.

7. **New hooks, rules and modules are added only for a problem that happened twice.** ([`CLAUDE.md`](CLAUDE.md) §7) Candidates wait in the `docs/agent-layer.md` §7 backlog marked ⏳. **A suggestion to add something because it would be nice to have is a convention violation here, not a contribution** — say what it would answer and how often it has actually happened. Occurrences are counted in `.claude/harness-gaps.md`, an append-only ledger.

8. **The inventory lives in `docs/agent-layer.md` and nowhere else.** ([ADR-0004](docs/adr/0004-single-source-of-truth.md)) Do not add scope, counts or roadmap to the README or a new file. The published check total must agree across the two READMEs and `agent-layer.md` §4; `make verify-all` enforces that, and `make verify` alone does not.

9. **`README.md` and `README.ko.md` are a mirror pair.** A change to one that does not touch the other is a defect.

## Two traps that look like findings

- **No AI attribution, ever.** No `Co-Authored-By: Claude` trailer, no `🤖 Generated with` footer, in commits or PR bodies. ([ADR-0006](docs/adr/0006-no-ai-attribution.md)) A hook enforces this for consumers, but this repository cannot install onto itself, so discipline is the only thing holding it.

- **Some Korean text is deliberate — do not propose translating it.** ([`CLAUDE.md`](CLAUDE.md) §8) Everything shipped is English, with four named exceptions: `README.ko.md` (a chosen mirror), `.claude/harness-gaps.md` (an append-only ledger — translating it would mean rewriting history), the benchmark prompts in `scripts/bench-*.sh` (measurement *inputs*; translate one and the recorded number describes a run that never happened), and the `한국어 트리거` clauses in five skill descriptions (measured, kept because the result was not significant either way).

## Repository shape

| Path | What it is |
|---|---|
| `plugins/harness-*/` | what the plugin system carries — hooks, skills, commands, verifiers, `bin/` |
| `plugins/harness-core/declarative/` | the three things a plugin **cannot** carry — permissions, `CLAUDE.md`, rules — written by `harnessctl` ([ADR-0008](docs/adr/0008-plugin-declarative-split.md)) |
| `install.sh` | thin bootstrap; runs both halves in order and holds no harness logic |
| `scripts/` and `.claude/` | this repository only, never shipped |
| `docs/agent-layer.md` | the single source of truth |
| `docs/adr/` | why each decision was made |

## Verifying

```bash
make verify                  # syntax, frontmatter, doc refs, budget, hooks, harnessctl, manifests
make verify BASH=/bin/bash   # the macOS bash 3.2 floor — required before merging
make verify-all              # the above, plus whether the published check total matches reality
```

`make bench*` costs real model sessions and does not run in CI. Do not propose it as a gate.

## Commits and pull requests

Branch `{feat,fix,chore}-<slug>`; PR title `[<slug>] <description>`, 70 characters or fewer. Split commits by meaning. Structural changes to the harness and content additions go in separate pull requests.

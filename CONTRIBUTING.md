# Contributing

This repository is a Claude Code harness: guard hooks, conventions, and an installer that can be reversed. The conventions it ships apply to work on it too — read [`plugins/harness-core/declarative/CLAUDE.md`](plugins/harness-core/declarative/CLAUDE.md) before anything non-trivial.

[`docs/agent-layer.md`](docs/agent-layer.md) is the single source of truth for scope, inventory and backlog. Change it there and nowhere else; a second copy is a copy that will be wrong.

**Language.** Documentation is English. Korean mirrors exist for the README (`README.ko.md`) and may lag. Skill descriptions keep their bilingual triggers — that is a measured mechanism, not prose, and removing it is a change that has to be measured first.

---

## Before you start

```bash
make verify-all              # everything, plus the published check total
make verify BASH=/bin/bash   # macOS bash 3.2 — the floor, required before merge
```

Both must pass. CI runs the first on Ubuntu, the second on macOS, and validates plugin manifests in a third job.

---

## The two rules that decide most reviews

### 1. A guard merged without verification is decoration

Every blocking hook ships with `plugins/harness-core/scripts/verify-<name>.sh`, at least eight cases, and all three kinds:

| Kind | What it proves |
|---|---|
| **no-op** | input the hook must ignore |
| **block** | what it must stop |
| **boundary** | something that *resembles* what is blocked and must pass |

The third is what earns its keep. A verifier with only block cases proves the hook stops what it should and says nothing about what it lets through — and the second is how guards actually die, because the first false positive on ordinary work is when someone turns it off.

**Widening a guard requires cases in the opposite direction.** A pattern was once broadened to catch more secrets and began blocking every branch name starting with `sk-`. There were block cases for the new direction and none for the old, so the regression was invisible.

### 2. New assets are for problems that happened twice

One occurrence goes in the PR description. Two makes it a candidate. The count lives in `.claude/harness-gaps.md` because "twice" cannot be counted across sessions from memory — **write the first one down even though it is not yet actionable**, in the same turn you notice it.

An empty ledger is not evidence that there are no gaps. It usually means nobody wrote to one.

---

## Adding things

### A hook

Six artefacts, and the same `<name>` in four of them so the audit is mechanical:

1. `plugins/harness-core/hooks/<name>.sh`
2. `plugins/harness-core/scripts/verify-<name>.sh` — 8+ cases
3. `docs/hooks/<name>.md`
4. registration in `plugins/harness-core/hooks/hooks.json`, anchored on `${CLAUDE_PLUGIN_ROOT}`
5. an entry in `docs/agent-layer.md`
6. a `version` bump in the plugin manifest

**The version bump is not optional.** Manifests pin a version, so a commit alone does not reach users — Claude Code keeps the cached copy when the version string has not moved.

### A skill

Same idea, with the verifier replaced by a measurement:

1. `plugins/harness-<profile>/skills/<name>/SKILL.md` — the description **must be quoted** (see below)
2. `evals/trigger/<name>.json` — 6 positive, 6 negative. **The negatives matter more**: use near-misses that should route to a neighbouring skill
3. `make bench-trigger`, with the numbers recorded in `docs/agent-layer.md` §4b
4. a `version` bump

A negative case asks *"did the work go where we said it would"*, not *"did our skill stay quiet"*. `bench-trigger` records which skill was actually invoked, so routing to the named neighbour is a pass and routing nowhere is a different result with a different fix.

**One run per query is not a measurement.** The default is three.

### A repo-only verifier

`scripts/verify-*.sh` has no fixed case requirement. What it owes depends on how it can be wrong:

| Failure mode | What it owes | Example |
|---|---|---|
| **false positive** — calls a correct thing wrong | **cases.** A checker that cries wolf gets switched off, and a switched-off checker is worth zero | `verify-doc-refs` (19 cases) |
| **omission** — fails to look at something | **design first.** Glob the file list instead of hardcoding it, so the omission cannot happen. Cases only where design cannot reach | `context-budget` |
| self-evident | neither | `verify-frontmatter` |

**A line that runs in only one of the environments a verifier meets is unverified.** `verify-check-total` carried a branch that only runs without the Claude CLI, was written on a machine that has one, and broke the first time CI ran it.

---

## The hook contract

- **bash 3.2 and jq only.** No Python or Node ([ADR-0002](docs/adr/0002-hook-contract.md)). macOS `/bin/bash` is the floor — no `mapfile`, no associative arrays, no `${x^^}`. Under `set -u`, expand empty arrays as `"${a[@]+"${a[@]}"}"`. That rule is about what ships: repo-only scripts under `scripts/` may use python3, and four do.
- **A hook that parses stdin disables itself when jq is absent** — one line to stderr and `exit 0`. A missing hook must never block work. Hooks that only call `git` and never read stdin have no such guard, and their docs say so.
- **Only blocking hooks exit non-zero.** Everything else exits 0 no matter what. An informational hook that halts a turn is a bug.
- **A block message says what was caught and how to resolve it**, and points at `docs/hooks/<name>.md`. Consumers cannot open the hook file — it is in the plugin cache — so the message is the only interface.

---

## Where things go

The split is not a preference; it is where the platform draws the line ([ADR-0008](docs/adr/0008-plugin-declarative-split.md)). A plugin cannot carry three things: its `settings.json` supports only `agent` and `subagentStatusLine`, a plugin-root `CLAUDE.md` is not loaded as context, and `rules` is not a plugin component. Those three go in `declarative/` and `harnessctl` writes them.

| What | Where |
|---|---|
| hooks | `plugins/harness-core/hooks/` + registration in `hooks.json` |
| skills every consumer gets | `plugins/harness-core/skills/` |
| skills for one profile | `plugins/harness-<profile>/skills/` |
| verifiers | `plugins/harness-core/scripts/` |
| executables | `plugins/harness-core/bin/` — auto-added to the Bash tool's PATH |
| permissions, scalars | `plugins/harness-core/declarative/settings-fragment.json` |
| `CLAUDE.md`, rules, consumer templates | `plugins/harness-core/declarative/` |
| external plugin dependencies | that profile's `dependencies` |
| used only in this repository | `scripts/`, `.claude/` — not shipped |

**All declarative payload lives in `harness-core` alone.** Spreading it across profiles would make `harnessctl` search another plugin's cache, and caches are isolated per plugin with `../` traversal forbidden. Profile selection is a flag: `harnessctl init --with <name>`.

---

## Context budget

Every skill description and rule file is a per-session tax on every consumer, forever.

```bash
make context-budget    # per scope and profile, against the ceiling in the Makefile
```

`make verify` fails past `CONTEXT_CEILING`. **Adding always-on context is a trade** — a change that needs more says what comes out, or raises the ceiling deliberately and says why.

The published figure was once wrong by 3.6× because the table counted plugin skills and ignored `CLAUDE.md` and `rules/`, which the installer writes and which load every session. Rules cost more than skills. Numbers in documents are generated, not typed.

---

## Commits and pull requests

- Branch `{feat,fix,chore}-<slug>`. No `/` — the slug becomes a worktree and directory name.
- Commit subjects start with a verb; the body carries *why*, not *what*.
- PR title `[<slug>] <description>`, **70 characters or fewer**. `pr-create` counts it for you, because this repository shipped one at 71 and opened another at 79 before anything counted.
- PR body: Motivation → Changes → Verification → Notes. **Verification means commands you actually ran and their output.** "Should work" is not verification.
- **No AI attribution** ([ADR-0006](docs/adr/0006-no-ai-attribution.md)). No `Co-Authored-By` trailer, no generated-with footer. A hook blocks it, but this repository cannot install its own guards onto itself, so it holds by discipline.
- Structural changes to the harness ship separately from content.
- Read `.claude/harness-gaps.md` before opening a PR. A second occurrence goes in the body under `## Notes`.

---

## Benchmarks are not tests

`make verify` is free and runs in CI. `make bench*` spends model sessions and real money, runs by hand, and its numbers are recorded in `docs/agent-layer.md` §4b.

A benchmark that gates CI becomes a test, and then it gets written to pass instead of written to inform. The guard benchmark is expected to score below 100% — the misses are the report.

**Before concluding anything from a negative result, confirm the mechanism could have fired.** Nine instrument failures are catalogued in §4b, and every one of them printed a clean zero that looked exactly like a real finding.

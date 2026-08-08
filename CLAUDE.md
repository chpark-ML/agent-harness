# CLAUDE.md — working on agent-harness itself

This repository *is* a Claude Code harness, shipped as plugins plus a declarative installer. The conventions below apply while developing it. The product's own behavioural defaults live in [`plugins/harness-core/declarative/CLAUDE.md`](plugins/harness-core/declarative/CLAUDE.md) — **read that file before any non-trivial task here**; it applies to work in this repository too, and it is the text consumers receive:

1. **Think Before Coding** — state assumptions, surface alternatives, stop when unclear.
2. **Simplicity First** — minimum code that solves the problem, nothing speculative.
3. **Surgical Changes** — every changed line traces to the request.
4. **Goal-Driven Execution** — define the check, run it, then report done.
5. **Surface Harness Gaps** — propose, don't silently patch around.

**Language.** Match the user's prompt language. Everything that ships is written in English — documents, scripts, and the output the two programs print. The exceptions are deliberate and named in §8.

---

## 1. What goes where

There are two delivery paths, and the fork is **whether a plugin can carry it** ([ADR-0008](docs/adr/0008-plugin-declarative-split.md)).

| What you are adding | Where it goes |
|---|---|
| A hook | `plugins/harness-core/hooks/<name>.sh` + registered in `hooks/hooks.json` |
| A skill or command every consumer gets | `plugins/harness-core/{skills,commands}/` |
| A skill only one profile gets | `plugins/harness-<profile>/skills/` |
| A verification script | `plugins/harness-core/scripts/` |
| An executable | `plugins/harness-core/bin/` — added to the Bash tool's PATH automatically |
| Permissions and scalars | `plugins/harness-core/declarative/settings-fragment.json` |
| `CLAUDE.md`, rules, consumer config templates | `plugins/harness-core/declarative/` |
| A dependency on an external plugin | That profile's `dependencies` |
| Something only this repository uses | `scripts/` and `.claude/` (not shipped) |

**Exactly three things a plugin cannot carry, and all three are confirmed facts**: a plugin's `settings.json` supports only `agent` and `subagentStatusLine`, a plugin-root `CLAUDE.md` is not read as context, and `rules` is not on the component list. Only those three go in `declarative/`, and `harnessctl` writes them.

**The declarative payload lives in `harness-core` and nowhere else.** Scatter it per profile and harnessctl has to find another plugin's cache — but caches are separate per plugin and `../` references are forbidden. Profile selection is handled by the `harnessctl init --with <name>` flag instead. Skills are the opposite: the platform loads them from each plugin's own cache, so they belong in their own profile.

## 2. A new hook is a bundle of artifacts

Miss one and it is unfinished. The [`harness-reviewer`](.claude/agents/harness-reviewer.md) agent audits this.

1. `plugins/harness-core/hooks/<name>.sh`
2. `plugins/harness-core/scripts/verify-<name>.sh` — 8 cases or more
3. `docs/hooks/<name>.md`
4. Registration in `plugins/harness-core/hooks/hooks.json` (anchored on `${CLAUDE_PLUGIN_ROOT}`)
5. `docs/agent-layer.md` updated
6. `version` bumped in `plugins/harness-core/.claude-plugin/plugin.json`

The `<name>` has to match in all four places or the audit cannot run mechanically.

**The version bump is not optional.** The manifest states a `version`, so committing alone delivers nothing to users — Claude Code sees the same version string and keeps its cache. We accept that constraint in order to use `claude plugin validate --strict` as a CI gate (an unspecified `version` turns from a warning into a failure under strict).

## 2b. A new skill is a bundle too

For the same reason hooks owe a verifier, skills owe a **trigger eval**. A description's triggers and its negative routing are claims about behaviour, and an unmeasured claim is just a claim.

1. `plugins/harness-<profile>/skills/<name>/SKILL.md` — the description **must be quoted** (§4)
2. `evals/trigger/<name>.json` — 6 positive, 6 negative. **The negatives matter more**: put in the near-misses that should reach a neighbouring skill.
3. Measure with `make bench-trigger` and put the result in the §4b table of `docs/agent-layer.md`
4. Bump that plugin's `version`

**A negative case asks "did the work go where we wrote that it would", not "did our skill stay quiet".** `bench-trigger` records which skill was actually called, so you can check whether it reached the neighbour the negative routing named. If it reached nothing at all, that is a different result and it is fixed differently.

**One run per query is not a measurement** (the default is 3). And trigger measurement has several ways of quietly killing the instrument, so read [the trap table in §4b](docs/agent-layer.md) before concluding anything.

## 2c. A new `bin/` executable is a bundle too

Different from a hook in two places, which is why it needs its own list.

1. `plugins/harness-core/bin/<name>` — executable bit set, `catches` / `scope` / `bypass` in the header comment
2. `plugins/harness-core/scripts/verify-<name>.sh` — the case mix is set by §4's table
3. `docs/<name>.md` — not `docs/hooks/`, because it is not a hook
4. **A shim in `install.sh`**, not a `hooks.json` entry. A plugin's `bin/` reaches the Bash tool's PATH but **not the user's terminal**, so an executable with no shim ships with a documented command that does not exist. The shim loop globs `bin/`; do not add a name to it.
5. `docs/agent-layer.md` updated
6. `version` bumped

## 3. The hook contract

- **bash 3.2 and jq only.** No Python or Node extensions ([ADR-0002](docs/adr/0002-hook-contract.md)). The exception is the repo-only `scripts/verify-frontmatter.sh`, which is not shipped and so uses python3. macOS's `/bin/bash` is the floor — no `mapfile`, no associative arrays, no `${x^^}`. Under `set -u`, expand an empty array as `"${a[@]+"${a[@]}"}"`.
- **A hook that parses stdin** disables itself with one stderr line and `exit 0` when `jq` is absent. A missing hook must not block work. Hooks that only call `git` and never read stdin (`session-brief`, `check-uncommitted`) correctly have no such guard — each hook's document says so, so nobody goes hunting for a guard that was never there.
- **Only a blocking hook exits 2.** Everything else exits 0 no matter what. An informational hook that stops a turn is a bug.
- A block message carries *what was caught* and *how to get past it*, and points at `docs/hooks/<name>.md`. A consumer cannot open the hook file in their own tree — it lives in the plugin cache — so the message is the only interface.
- Put catches / scope / bypass in the header comment.

## 4. The verification mandate

**A guard merged without verification is not a guard, it is decoration** ([ADR-0003](docs/adr/0003-verification-mandate.md)).

```bash
make verify-all              # verify, plus whether the published check total matches reality
make verify                  # syntax + frontmatter + doc-refs + budget + hooks + harnessctl + manifests
make verify BASH=/bin/bash   # the macOS bash 3.2 floor — required before merging
```

**Whether a repo-only verifier (`scripts/verify-*.sh`) owes its own cases is decided by how that verifier fails.** Unlike hooks there was no rule, so three of them were judged on the spot, and those three cases made the rule.

| How it fails | What to attach | Example |
|---|---|---|
| **False positive** — calls a correct thing wrong | **Cases.** A check that cries wolf gets switched off, and a switched-off check is zero | `verify-doc-refs` (19 cases) |
| **Omission** — does not look at what it should | **Prevent it by design first.** Glob instead of hardcoding a list. Cases only when design cannot | `context-budget` (the file list is a glob) |
| True or false is self-evident | Neither | `verify-frontmatter` |

**And either way, a line that runs in only *one* of the environments the verifier runs in is an unverified line.** `verify-check-total` was written on a machine with the Claude CLI, and the branch that runs only when the CLI is absent executed for the first time in CI, where it broke.

- Verifiers use `run_case` / `expect` / `expect_match` from `plugins/harness-core/scripts/_verify-lib.sh`. Do not write a new one.
- Cases come in three kinds: **no-op** (input the hook must not touch), **block**, and **boundary** (something that resembles what is blocked and must pass). The third is the one that earns its keep.
- **Frontmatter on a skill, rule or agent fails silently and empty.** An unquoted YAML scalar containing a colon-space fails to parse, and the description loads blank — no triggers, no negative routing. `scripts/verify-frontmatter.sh` stops that. Always quote the description value.
- If you touched the installer, `scripts/verify-install.sh` is the gate. Especially the property that *settings.json after uninstall is canonically identical to the original* — break that and a consumer loses something.
- After an incident, add the regression case before the fix.
- **A benchmark is not `verify`.** `make verify` is free and CI runs it. `make bench*` burns model sessions, so it costs real money and does not run in CI — run it by hand when you change something it covers, and record the number in §4b.

## 5. `docs/agent-layer.md` is the single source of truth

A change to the harness's scope, inventory or backlog updates **that file only** ([ADR-0004](docs/adr/0004-single-source-of-truth.md)). Do not copy the same content into the README or a separate roadmap — the moment there are two, one of them is about to become false. Not shipping an installed index file is the same reasoning.

## 6. Commits and PRs

- Branch `{feat,fix,chore}-<slug>`, PR title `[<slug>] <description>`, 70 characters or fewer.
- **No AI attribution** ([ADR-0006](docs/adr/0006-no-ai-attribution.md)). No `Co-Authored-By: Claude` trailer, no `🤖 Generated with` footer. This repository is not protected by its own hooks (it cannot install onto itself), so discipline is the only thing holding it.
- Structural changes to the harness and content additions go in separate PRs.
- Read `.claude/harness-gaps.md` before opening a PR. If an entry is on its second occurrence, raise it in the PR body under `## Notes` — this repository follows its own §5 too.

## 7. Resisting over-design

The §2 this repository preaches at consumers applies to this repository. One of the reference harnesses deleted 875 lines of just-in-case defence in a single commit, and that was a win. A new hook, rule or module is added only for a problem that **actually happened twice**. Candidates sit in the `docs/agent-layer.md` backlog marked ⏳, waiting for the second occurrence.

## 8. What stays in Korean, and why

Everything shipped is English. Four things are not, and each is a decision rather than an omission — so nobody "finishes the job" by translating them.

- **`README.ko.md`** — the mirror, chosen deliberately. It tracks `README.md`; do not let them drift.
- **`.claude/harness-gaps.md`** — a repo-local, append-only ledger. Translating it would mean rewriting history entries, which is the one thing an append-only record must not do. It is not shipped.
- **Benchmark prompts** in `scripts/bench-convention.sh` and `scripts/bench-tier.sh`, and the trigger phrases quoted in ADR-0011's measurement table. These are measurement *inputs*: translate one and the recorded number describes a run that never happened. If a bench is ever re-run in English, that is a new measurement with its own row, not an edit to an old one.
- **The `한국어 트리거` clauses in the five skill descriptions** — measured, not assumed: pass^3 0.83 against 0.50, Fisher *p* = 0.545, kept because the result was not significant either way (§4b). `TRIGGER_LANGS` in the `Makefile` makes the requirement a property of this deployment rather than of the harness, so a contributor writing for another language is not asked for a Korean marker.

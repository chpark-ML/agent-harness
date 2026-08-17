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
| A dated Superpowers design record (spec or plan) | `docs/superpowers/{specs,plans}/` (not shipped; frozen once its work merges) |

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
7. **Blocking hooks only** — cases in `evals/incidents.sh`, written from the §2 accident table without looking at the hook's regexes

The `<name>` has to match in all four places or the audit cannot run mechanically.

**Item 7 is what the verifier cannot do.** `verify-<name>.sh` scores the hook against cases drawn from its own patterns, so on its own it measures what we built rather than what we meant to stop. `gh-account-guard` shipped with a full verifier and no corpus cases at all, and the published catch rate then described four blocking hooks while reading as if it described five.

**The version bump is not optional.** The manifest states a `version`, so committing alone delivers nothing to users — Claude Code sees the same version string and keeps its cache. We accept that constraint in order to use `claude plugin validate --strict` as a CI gate (an unspecified `version` turns from a warning into a failure under strict).

## 2b. A new skill is a bundle too

For the same reason hooks owe a verifier, skills owe a **trigger eval**. A description's triggers and its negative routing are claims about behaviour, and an unmeasured claim is just a claim.

1. `plugins/harness-<profile>/skills/<name>/SKILL.md` — the description **must be quoted** (§4)
2. `evals/trigger/<name>.json` — 6 positive, 6 negative. **The negatives matter more**: put in the near-misses that should reach a neighbouring skill.
3. Measure with `make bench-trigger` and put the result in the §4b table of `docs/agent-layer.md`
4. An entry in the §3 inventory of `docs/agent-layer.md` — the skills row counts per profile
5. **Run the body once, end to end, before merging.** Any commit range will do
6. Bump that plugin's `version`

**Item 5 is the one the trigger eval cannot cover.** `bench-trigger` measures whether the skill *fires*; nothing measures whether its procedure *runs*. A hook has `verify-<name>.sh` and an executable has its own verifier — a skill body is prose, and prose is not executed by anything. `cross-model-review` merged at 12/12 with three defects in its Step 4, and one real run found all three: a transport that did not exist, a guard that read the page once when the page lags, and a stability test that both reads passed while the answer was still truncated.

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

## 2d. And every bundle moves the published numbers

The three lists above say what to write. This says what writing it breaks, and it applies to all of them — the counts in the documents are derived from the tree, so adding a file changes them.

- **The check total.** A new `SKILL.md` is +3 on its own: `verify-doc-refs` scans it twice (once as a document, once as an instruction file) and `verify-frontmatter` once. `make verify-all` fails until the five published copies agree, so this one announces itself — but budget the commit.
- **The always-on worst case.** Only CI can measure it. `context-budget` reads the *installed* plugin, and a developer machine has the released version from GitHub, not the tree — it will say `measuring the OLD one` and refuse to gate. So **the first CI run on the PR produces the real number, and a second commit republishes it** in `README.md`, `README.ko.md`, `docs/agent-layer.md` and the `Makefile`. Plan for the round trip rather than discovering it.

Do not hand-edit either figure to what you expect. Both are generated, and the last time one was typed it was wrong by 3.6×.

## 3. The hook contract

- **bash 3.2 and jq only.** No Python or Node extensions ([ADR-0002](docs/adr/0002-hook-contract.md)). **The rule is about what ships**: nothing under `plugins/` may use python3, and the repo-only `scripts/` may — four do today (`verify-frontmatter`, `verify-doc-refs`, `verify-benches`, `bench-tier`), plus `bench-trigger.py` which is wholly Python and never part of `verify`. macOS's `/bin/bash` is the floor — no `mapfile`, no associative arrays, no `${x^^}`. Under `set -u`, expand an empty array as `"${a[@]+"${a[@]}"}"`.
- **A hook that parses stdin** disables itself with one stderr line and `exit 0` when `jq` is absent. A missing hook must not block work. Hooks that never read stdin have nothing to parse, so they need no jq and correctly have no such guard (today the two informational ones, `session-brief` and `check-uncommitted` — which tools a hook shells out to is beside the point) — each hook's document says so, so nobody goes hunting for a guard that was never there.
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
| True or false is self-evident | Neither | `verify-frontmatter`'s checks (its *reporting* path is a separate question and earned 4 — see below) |

**And either way, a line that runs in only *one* of the environments the verifier runs in is an unverified line.** `verify-check-total` was written on a machine with the Claude CLI, and the branch that runs only when the CLI is absent executed for the first time in CI, where it broke.

**"Environment" is not only CI-versus-local — the third occurrence was the locale.** `verify-frontmatter` printed its summary with an em-dash and Python's stdout defaults to `errors='strict'`, so on a cp949 console it passed 11 / 11 and then died reporting it: a green run exiting 1. Every python-embedding verifier now sets `errors='replace'` — degrade the character, never the verifier — and `verify-frontmatter.sh --selftest` holds the line, half of it a glob so a fourth script cannot arrive without it. **Write the reproduction so it runs everywhere**: `PYTHONIOENCODING=ascii` reproduces this on any platform, which is why the case is worth having; a Windows-only case would have been invisible to CI and become the same bug again.

- Hook verifiers use `run_case` / `expect` / `expect_match` from `plugins/harness-core/scripts/_verify-lib.sh`; repo-only verifiers use `scripts/_check-lib.sh`, which sources it and adds `check_rc` / `check_eq` / `summary` on top (the hook runner needs a hook file, which repo-only scripts do not have). Do not write a third.
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
- **The Korean in the five skill descriptions** — the `한국어 트리거` clauses (410 characters, counted from the label through the period closing the last quoted phrase) *and* the negative-routing sentences that follow them (198 more). Only the first half was measured — measured, not assumed: pass^3 0.83 against 0.50, Fisher *p* = 0.545, kept because the result was not significant either way (§4b). [`.claude/trigger-langs`](.claude/trigger-langs) makes the requirement a property of this deployment rather than of the harness, so a contributor writing for another language is not asked for a Korean marker. It is a file and not a `Makefile` variable for a measured reason: Windows `make.exe` re-encodes recipe text through the ANSI codepage on its way into the child environment, so `한국어` arrived as mojibake and five skills that plainly carry the marker were reported as missing it.

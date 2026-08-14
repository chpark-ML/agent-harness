# ADR-0011: An external ecosystem survey — what comes in and what does not

- **Status**: Accepted
- **Date**: 2026-08-07

## Context

Nine candidates were named: `karpathy-guidelines`, `caveman`, `ui-ux-pro-max`, `handoff`, `skill-creator`, `omniroute`, `claude-mem`, `task-observer`, `headroom`. Only `headroom` was installed, and even that was inactive and scoped to **another project** (`ponytail` likewise). The other eight had nothing to do with this repository.

On the first pass I cut three of them on **packaging** — "`task-observer` cannot be `claude plugin install`ed", "`skill-creator` shares triggers with `writing-skills`, so keep one". Both were wrong. A `SKILL.md` can simply be copied, and whether two skills overlap is something you only learn by reading the bodies. It was the third repetition of the exact mistake [ADR-0009](0009-external-dependencies.md) had already turned into a rule: *conflicts with an external skill are judged by the body, not the name.*

## Decision

### 1. Adopt `skill-creator` — as an **instrument**, not a skill

This is the survey's one large finding. It is not the "skill-writing helper" its name suggests but an **evaluation harness**, carrying three subagents (`analyzer`, `comparator`, `grader`) and seven scripts. It gives us three things we did not have.

- **Paired with-skill / baseline runs.** Both arms launch in the same turn — the textbook way to control for time of day and API variation.
- **`aggregate_benchmark.py` reports mean ± stddev and delta.** A machine doing the same calculation as the significance discipline we had just written into [agent-layer §4b](../agent-layer.md).
- **`run_loop.py` optimises a description's trigger accuracy.** It splits the trigger eval 60/40 into train and test, runs each query three times to measure the trigger rate, and picks the best candidate **by the test score** (picking on train overfits).

One thing `analyzer` looks for is a **non-discriminating assertion** — a check that passes whether or not the skill is present. It is the machine version of the principle we had written down as "a benchmark that always returns 100% carries no information".

**It is on the official marketplace, so we install rather than vendor it** (Apache-2.0). The same provenance argument as Superpowers.

### 2. Keep **both** `skill-creator` and Superpowers `writing-skills`

The first verdict, "triggers overlap, keep one", is withdrawn after reading the bodies. They do not overlap.

| | `writing-skills` (Superpowers) | `skill-creator` (official) |
|---|---|---|
| What | **How to write** a skill — TDD mapping, prose shapes per failure type, a rationalisation table, closing loopholes | **How to measure** whether a skill works — paired runs, grading, aggregation, trigger optimisation |
| Instrumentation | A conceptual baseline, no tools | Scripts, subagents, reports |

The first is discipline, the second is a ruler. They share trigger phrasing, but drawing the dividing line **along the lifecycle stage** — before writing, or measuring after — resolves it, the way [ADR-0009](0009-external-dependencies.md)'s update section established.

### 3. Take only the **ledger mechanism** from `task-observer`

`CLAUDE.md` §5 defines a harness gap as something you propose after it has **happened twice**. **That threshold is currently unenforceable** — there is no device that counts occurrences across sessions, so it rests entirely on what you happen to remember in the moment.

`task-observer` is exactly that counter: it appends an observation to a log file within the same turn (*"writing it down IS the enforcement"*), keeps a taxonomy, and surfaces entries periodically. Its **SIMPLIFYING signals** section in particular — *"ask what to remove as deliberately as what to add"* — points the same way as our §2 and §7 resistance to over-design.

**We do not copy the whole skill.** It is 446 lines and half of it overlaps our §5. What we take is one mechanism, *a durable ledger*, scoped down to harness gaps. Attribution is recorded (CC BY 4.0).

### 4. `karpathy-guidelines` — do not install, credit the source, absorb the one missing line

**Our `CLAUDE.md` §1–4 is this skill.** Compared after normalising dashes and whitespace, 20 of its 23 normative sentences matched verbatim, and two of the remaining three were the same sentence worded differently. The one thing we added is §5.

A real defect surfaced here. **The skill is MIT, we redistribute a substantial part of it to consumers, and the repository credited it nowhere.** A compliance problem found while surveying, and fixed immediately — a **Provenance** section went into the preamble of `declarative/CLAUDE.md`.

Exactly one normative sentence was genuinely missing, and it went into §2: *"If you write 200 lines and it could be 50, rewrite it."*

We do not install it. Two copies of the same rules would load, and only one of them would be ours to fix.

### 5. `harness-100` — depend on it, do not absorb it

[`revfactory/harness-100`](https://github.com/revfactory/harness-100) (Apache-2.0) is 100 project templates across 10 domains (100 each in English and Korean). Each is `{NN}-{name}/.claude/{CLAUDE.md, agents/, skills/}` with one orchestrator skill, 4–5 specialist agents, and 2–3 domain skills.

**Verdict: depend. Zero new files.** The same problem ADR-0009 already solved with Superpowers — general working capability is composed from other people's work, and we keep the guards, the conventions and the install ([agent-layer.md §1](../agent-layer.md), Non-goal). An individual harness cannot pass ADR-0001's admission test by construction (*would this make sense installed as-is in another domain, on another stack?*). Us shipping `01-youtube-production` would be a different product.

**Absorption was considered and dropped on measurement.** Six domains ≈ 62 harnesses × ~560 tok each ≈ **35k tok per session**. The always-on ceiling is 9,000 and current consumption is 8,026, so not even one domain fits (12–15 harnesses, ~7–8k). **The unit of installation has to be one harness, and they have already cut it that way** — there is no reason for us to bundle it back up.

**Coexistence was measured.** `31-ml-experiment` was laid over a session with our harness installed, 12 cases × 3 runs:

| | Result |
|---|---|
| Did it take our seats (6 negatives) | **Zero.** `repro-checklist`, `research-notes` ×2, `results-deck`, `pr-review` and `pr-create` each held **3/3, unanimously** |
| Did their orchestrator get its own seat (6 positives) | 4/6. Of the two misses, one was a leading `Bash` call (an instrument limitation) and one was `superpowers:brainstorming` taking it 3/3 — **which is our own doctrine** (*"Let's build X" → brainstorming first*) |

**Two things to know before using it.** ① The skill files are lowercase `skill.md` (zero `SKILL.md`) — macOS's default filesystem is case-insensitive so they load, but on Linux and in containers they do not. ② Verification is zero: 1,808 markdown files with no tests, no eval sets and no CI, and the README's *"Trigger Boundaries — Should-trigger + NOT-trigger **defined**"* says defined, not measured.

### 6. Nothing else comes in

| Candidate | Basis for the verdict |
|---|---|
| `caveman` | 65% fewer output tokens. But [ADR-0002](0002-hook-contract.md) fixed as a hook contract that *a block message carries both what was caught and how to get past it*. They fight head-on |
| `ui-ux-pro-max` | Domain-profile material. This repository is not a UI project and the occurrence count is zero — it fails §7's "wait for the second occurrence". If it is ever needed, as `harness-frontend` |
| `claude-mem` | Five lifecycle hooks capturing and storing **all tool I/O**. Not something to bring into a repository running `secret-scrubber` without first checking what it swallows |
| `omniroute` | Not a plugin but a local gateway (npm). Prompts and code pass through a third-party proxy — a security decision, not a harness one |
| `handoff` | `harness-research`'s five-document set already covers continuity on the research side. Zero occurrences on the development side. To the backlog |
| `headroom`, `ponytail` | **This row was wrong.** It originally read *"an inactive install under another project's scope, not this repository's asset"* — which is not a verdict, it is a description of this machine. The bodies were read later and each judged in [agent-layer §3b](../agent-layer.md): **rejected** (a proxy, and paid) and **held, with its eval design absorbed** |

## What the survey found about the instruments — the more valuable half

Trying to measure `results-deck`'s trigger rate walked into **three false-negative traps**. All three produced output that looked identical: "0.0 — did not trigger".

1. **A timeout is indistinguishable from a non-trigger.** At the defaults `--timeout 30 --num-workers 10`, `claude -p` is cut off before it reaches the first Skill call, and every result is 0.0. Running the control at `--num-workers 1 --timeout 150` turned it into 3/3.
2. **An installed skill cannot be measured through a stand-in.** The harness exposes the description as a temporary slash command, but when the real skill is installed the model calls **the real one**. The detector looks for the temporary name and records "did not fire". Measuring it means disabling that plugin first.
3. **Only the first tool call is examined.** The detection code returns False immediately if the first `tool_use` is not `Skill` or `Read`. A task that points at repository files can have the model start by looking around with `Bash`, and then a later skill call is recorded as a non-trigger.

**One rule follows: run a positive control alongside any trigger measurement.** Take one skill that is not installed and must certainly fire, measure it under the same conditions, and confirm the instrument is in a state where it can ring at all. All three traps would have been caught by that single control.

This is the third instance of the lesson [agent-layer §4b](../agent-layer.md) learned from the first LSP run — *when you get a negative result, first check whether the conditions for the mechanism to fire were even met*. Three makes it a rule.

## What the measurement actually returned — `results-deck`'s trigger rate

`scripts/bench-trigger.py`, built to avoid the three traps, measures **the real installed skill**. It fires a prompt, watches only the first tool call, and kills the run — a full run costs money, and the one thing we want to know is a single opening move. Timeouts are recorded separately from non-triggers.

**Negative routing came back clean at 6/6** (on both full runs). Rendering, layout, PDF, note-writing, a conversational answer and a diagram all failed to pull the skill in. The `slides-grab` and `research-notes` names pinned into the description do work.

**The positives did not.** The first measurement was 4/6, and both misses were *development-side reporting* (a release write-up, a manager readout). The Korean trigger list leaned research-side. A textbook case of the undertrigger `skill-creator`'s own text warns about — *"Claude tends to under-call skills, so write the description to push slightly"*.

Development-side phrasing was strengthened (`릴리스 정리해서 보고 자료로`, `스테이크홀더 리뷰용으로 정리해줘`, "readout", "even when the user never says 'slides' or 'deck'") and the six positives were **compared pairwise, three runs each**.

| Query | Before | After |
|---|---|---|
| guard-hook benchmark (ko) | 1.00 | 1.00 |
| pyright LSP ablation (en) | 0.33 | **0.67** |
| based on FINDINGS.md (ko) | 1.00 | 1.00 |
| v1.4 release → stakeholders (ko) | 0.67 | **1.00** |
| manager readout (en) | 0.00 | 0.00 |
| summarise the research results (ko) | 1.00 | 1.00 |
| **Total triggers** | 12 / 18 (67%) | **14 / 18 (78%)** |

**Two improved, zero worsened, four tied.** By sign test *p* = 0.25, so it is **not significant** — with six pairs it could hardly be otherwise. The reason for adopting it anyway is not significance but **monotonicity**: no query got worse, and the very case that prompted the change (the release one) went 0.67 → 1.00. Our discipline was "do not claim an effect below 20%", not "do not fix without measuring", and what is claimed here is the absence of a regression, not an effect size.

**The remaining 0/3 is recorded.** *"what would a good narrative look like for a 15 minute slot"* — a question about approach rather than a request for an artefact, so the model answers it directly. Whether that is even a description-level problem is unclear, so it is left as a limit rather than fixed.

One more methodological trap worth leaving behind. The first comparison ran **once per query** and produced 4/6 against 4/6 — with **different members**. It could have been read as an improvement or as a regression. Raising it to three runs revealed the direction. **In trigger measurement, one run per query is not a measurement.**

## Consequences

- **§4b's "convention compliance is unmeasured" is stale.** It said `claude plugin eval` was blocked behind early access — `skill-creator` provides the DIY version, and in the same shape as the design sketched by hand in §4b.
- Our skill descriptions are long, carrying Korean and English triggers and negative routing. That can now **be measured for routing as intended, and must be.** Unmeasured negative routing is just a claim.
- ~~Running a trigger eval requires disabling the plugin under test~~ — only when using `skill-creator`'s `run_eval.py`. So we do not use it. `scripts/bench-trigger.py` measures the installed skill as it is, needs no disabling, and is better for it: it measures **the configuration the user actually runs**.
- `skill-creator` costs **112 tok** always-on and **10.9k** on invocation (measured, and recorded in the §4b table). Cheaper than one of our skills standing still, and thirty times more when called — the right shape for a developer-only asset that is not shipped.
- Adopting the `task-observer` ledger makes §5 enforceable for the first time, and simultaneously risks producing **a log file nobody reads**. So its scope is narrowed to harness gaps, and surfacing is hung off `pr-create` so that an empty ledger does not become the normal state.

## Alternatives considered

- **Vendor `skill-creator`.** Rejected. It is on the official marketplace, it is Apache-2.0, and its scripts import each other. Copy it and upstream fixes stop reaching us.
- **Install `task-observer` whole.** Rejected. That it cannot be `claude plugin install`ed is solved by copying, but half of its 446 lines overlap §5. Two copies of the same discipline is the thing we tell other people not to do.
- **Install all nine and choose afterwards.** Rejected. Installing `claude-mem` and `omniroute` makes data and path changes that are hard to undo. Reading the bodies first is cheaper.

---

> **Correction (2026-08-13).** Two of this survey's decisions did not survive contact with a re-review. **§1's adoption of `skill-creator` lapsed silently**: installed 2026-08-07, it was orphaned on 2026-08-09 and never used once — the verdict outlived the installation, and only the 2026-08-13 candidate re-review noticed (`.claude/harness-gaps.md`, same date). It is demoted to a dated verdict rather than re-installed, with the re-adoption condition written down: `claude plugin eval` leaving early access, since its `--ablation with-without` (already advertised in `--help`, still refused at runtime as of 2026-08-13) is the native form of the paired with/without runs that were §1's reason to adopt. Second, the survey's Context named nine candidates; a second pass over eleven more is recorded in [agent-layer §3b](../agent-layer.md), where it belongs — including one verdict this ADR's framing helped get wrong (`claude-video`, first refused under a misreading of the working-skills non-goal that would also have refused Superpowers).

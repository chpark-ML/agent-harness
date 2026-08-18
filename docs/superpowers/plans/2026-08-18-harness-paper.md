# harness-paper Plan — the manuscript half of the research module

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> Dated design record. Counts quoted below describe the tree at the time of writing; [`agent-layer.md`](../../agent-layer.md) is the source of truth for current numbers.

**Goal:** Make *every number in a manuscript traces to the run that produced it* enforceable, on any project, in any plain-text manuscript format, with no assumption about directory layout, build system, venue or output language.

**Architecture:** Not a port. The invariant is already stated by the research module (`ARTIFACTS.md`) and already mechanised by the slides module (`check-claims.sh`), which takes *a document and an artifact map* and knows nothing about slides. A manuscript is that script's third caller. What genuinely has to be added is a consumer-owned path config (the `protected-paths` pattern) and the one discipline a manuscript needs that a deck does not — the retraction sweep.

**Tech Stack:** bash 3.2, no jq, no network. Reuses `plugins/harness-slides/scripts/check-claims.sh`.

---

## 1. Why the obvious plan was wrong

The obvious plan was to port [`ehr-research`](https://github.com/chpark-ML/ehr-research)'s paper assets — 27 skills, 7 agents, 10 hooks, 9 rules, including `repro-audit`, `latex-build`, `citation-management` and two paper rules. Reading them changed the design in three ways.

**The source does not generalise to its own second manuscript.** Its repository holds five publication directories, four of them with a `paper/`. Both paper rules are scoped `paths: ["pubs/drop-not-reliance/paper/**"]` — one publication. Their own ledger records this as `G21`, unfixed. The four differ from each other, too: two carry `paper/TRANSLATION_KR.md` and two do not, one carries `docs/{STATUS,FINDINGS,ARTIFACTS}.md` and three do not, one has `figures/` and `paper/styles/` and the others have neither. **Any design that hardcodes a layout is already falsified at N=2 inside the repository it came from.**

**The general thing already exists here, and it is not a paper asset.** `check-claims.sh` is invoked as `check-claims.sh <deck.md> [artifacts.md]`. It is parameterised on both the document and the artifact map, and its header states the invariant in document-neutral terms — *a number that cannot be traced through `ARTIFACTS.md` to the run that produced it is not yet a result*. It has 36 verification cases and a documented list of what it deliberately ignores. Porting `repro-audit`'s provenance discovery (it greps `results/` and `outputs/`) would be building a second, weaker instance of something already built and measured.

**Most of the source's paper assets are format-bound, not paper-bound.** `latex-build` is LaTeX. `citation-management` is BibTeX. The venue rules are ML conferences. `TRANSLATION_KR.md` sync is one lab's bilingual habit. None of that survives the admission test, and none of it is what makes a manuscript hard.

## 2. The generality tests, decided before anything is written

Generality is a claim, and this repository's rule is that an unmeasured claim is just a claim. Three tests, in increasing strength. **A design that fails any of them is not shipped.**

- [ ] **T1 — zero config is silence.** With no config file present, every check degrades to a no-op and nothing warns, exactly as `protected-paths` ships disabled when its file has no meaningful lines. A project that writes no papers must not notice this profile exists.
- [ ] **T2 — N=4 in the source repository, unchanged.** The four publications in `ehr-research/pubs/*` that have a `paper/` must each work with one config file and **no change to any shipped file**. They vary in translation, note-set and figure layout, which is the point — this is the test the source itself fails.
- [ ] **T3 — format independence.** The same design must work on a Markdown manuscript with no LaTeX anywhere. `check-claims.sh` already does this for `.md`, so T3 is really a test that widening it to `.tex` did not make Markdown a special case.

**T2 is the load-bearing one.** It is cheap (the repository is on this machine), it is falsifiable, and it is the exact test that separates *a general design* from *a port with the paths pulled out*.

## 3. What ships

Four things. Nothing else.

### 3a. `paper-paths.txt` — a consumer-owned config

Follows [`protected-paths`](../../hooks/protected-paths.md) exactly: a template installed once, the consumer's thereafter; user scope ∪ project scope; absent or comment-only means every check that needs it skips.

```
# paper-paths — where this project keeps its manuscript and the things it must agree with.
# key = value, one per line. Every key is optional; a missing key disables the
# checks that need it. Globs are allowed.
manuscript = pubs/*/paper/*.tex
artifacts   = pubs/*/docs/ARTIFACTS.md
sweep       = pubs/*/slide/**  pubs/*/docs/**  pubs/*/figures/**
```

Three keys, because three is what the checks below actually need. **No key for the build system, the bibliography, the venue or the output language** — those are what made the source project-bound.

### 3b. `check-claims.sh` widened to LaTeX

The script's skip rules are currently Markdown-shaped (`<!-- -->` comments, `](link)` targets, `` `inline code` ``). LaTeX needs the equivalents, and only the equivalents:

- `%` to end-of-line as a comment, and `\%` as *not* a comment
- `\cite{...}`, `\ref{...}`, `\label{...}` — identifiers that carry digits
- `\section`/`\subsection` auto-numbering is absent from source, so nothing to do
- **numbers inside math mode stay claims** — that is where a manuscript's results live

Everything else it already handles: years, ISO dates, version tokens, thousands separators, `§` references.

- [ ] Add LaTeX cases to `verify-check-claims.sh`, including the boundary case `\%` (a literal percent, not a comment) and one where a real result inside `$...$` must still be caught.
- [ ] Keep the Markdown cases passing unchanged — that is T3.

### 3c. One rule — `rules/paper/manuscript.md`

Distilled from the source's `research-workflow.md`, keeping only what is format- and layout-free. Target size is `dev/review.md`'s (~1,000 tok), against a source of ~2,800.

**Keep:**

- **Claim scope stated identically wherever it appears.** The source names four places (Abstract, Intro, the Method section, Conclusion); the general form is *every place that states the scope states the same scope*, which needs no section vocabulary.
- **A motivation must be used and a method must be motivated.** Format-free.
- **A prediction is measured or explicitly scoped out.** Format-free.
- **The retraction sweep.** When a claim is withdrawn or narrowed, sweep every path under `sweep` case-insensitively, and record the search terms and their results. Two things the source learned the hard way and both generalise: *grep cannot reach inside a figure*, so an edited figure is re-exported and looked at; and present-state documents must be swept while history documents (a reversal section, a review log) must not, because deleting the record is the failure the record exists to prevent.
- **A review request produces a ranked list, not edits.** This is already `dev/review.md`'s R3, so it is a cross-reference, not a new rule.

**Drop:** the translation sync, `make paper-build VENUE=`, page-limit tactics, venue-specific advice, and the `pubs/` layout.

**Known hole, carried over honestly:** the source's `G19` records that the sweep is structurally blind when a claim is *narrowed* rather than withdrawn, because the old wording partly survives. The rule must say so rather than inherit the hole silently.

### 3d. One skill — `manuscript-audit`

Runs the checker over the manuscript against the artifact map, then reports what the checker cannot judge: claims whose numbers appear in `ARTIFACTS.md` but under a different run, and scope statements that disagree between sections. Grades and reports; **does not edit** — the rule above says a review request produces a list.

- [ ] Trigger eval: 6 positive, 6 negative. The negatives matter more — the near-misses route to `results-deck` (a talk, not a manuscript), `research-notes` (recording a result, not auditing one) and `repro-checklist` (making a run repeatable, not checking a written claim).
- [ ] Run the body end to end once before merging, on a real manuscript. `cross-model-review` merged at 12/12 with three defects in its body, and one real run found all three.

## 4. What does not ship, and why

| Not shipping | Because |
|---|---|
| `latex-build` | LaTeX-bound. The consumer already has a build command; §4's *build and inspect* already requires running it |
| `citation-management` | BibTeX-bound. The general form — every citation resolves, every entry is cited — needs a bibliography format key, which is the fourth config key this design refuses |
| `check-bib-sync.sh` | Guards a symlink invariant in a `pubs/*/paper|slide` layout. A site convention, not a discipline |
| `beamer-slides`, `slide-deck`, `presentation-flow` | Same lifecycle stage as `results-deck` with different output technology, so [ADR-0009](../../adr/0009-external-dependencies.md)'s dividing line has nothing to cut on. Open decision below |
| `paper-summary`, `paper-translation`, `review-orchestrator` | Reading *other people's* papers into Korean. A literature pipeline, not manuscript writing |
| `conference-report` | A trip report in one lab's template and language |
| `experiment-pipeline`, `reproducibility-protocol` | Overlaps `harness-research`'s `repro-checklist` |
| Venue rules, page tactics, `TRANSLATION_KR.md` | Site-bound by construction |

## 5. The ceiling, and a measurement gap it exposes

Current worst case is ~7,927 tok against a 9,000 ceiling — **1,073 of headroom**. One skill description is ~130. One rule at `dev/review.md`'s size is ~1,029. Together that is ~1,159, which does not fit.

**But the rule should be path-scoped, and a path-scoped rule is not always-on.** All three rules shipped today declare `paths: ["**/*"]`, and `context-budget.sh` therefore adds every rule's full byte cost to the profile total unconditionally. A rule scoped to `**/*.tex` and the configured manuscript paths costs nothing in a session that never opens one — yet the instrument would count it in full and report the ceiling blown.

- [ ] **Before writing the rule, decide whether `context-budget.sh` should discount path-scoped rules.** If it should, that is a separate change and a ledger entry: our cost model assumes a property of our rules rather than of rules. If it should not, the rule has to fit in ~900 tok and the skill in the remainder.

**Do not raise the ceiling to make room.** The Makefile records the gap as deliberate headroom, and raising it to fit the first thing that does not fit is how a budget stops being one.

## 6. Sequence

1. - [ ] **T1 and the config.** Ship `paper-paths.txt` as a template plus the resolution logic, with the absent-file path verified first. Nothing else works until a missing config is silent.
2. - [ ] **Widen `check-claims.sh` to LaTeX**, with cases. This is the highest-value step and it touches no new profile — it improves an existing, measured script.
3. - [ ] **Run T2 immediately after step 2**, before writing the rule or the skill. Four publications, one config each, no shipped-file changes. If it fails, the design is wrong and the remaining steps are wasted.
4. - [ ] **Resolve the path-scoped-rule measurement question** (§5).
5. - [ ] **The rule**, then **the skill**, each with its full bundle. One at a time.
6. - [ ] Update `docs/agent-layer.md` §2 (the manuscript row gains an owner), §3, §3b, §7 and §8; both READMEs; republish the check total from CI.

**Steps 1–3 are the plan.** If T2 passes, the rest is ordinary bundle work. If T2 fails, stop and re-plan rather than adding config keys until it passes — a fourth and fifth key is how this becomes a port with the paths pulled out.

## 7. Open decisions

- **The slides collision.** A LaTeX manuscript makes a Beamer deck natural, and `harness-slides` renders HTML through `slides-grab`. Three options: keep slides as-is and let the manuscript be LaTeX-only; add a Beamer path to the slides profile; or let `harness-paper` carry deck generation for LaTeX projects and accept the same-stage overlap deliberately. **Not decided here** — it needs a demand basis, and none of the four test publications requires it for T2.
- **Whether `harness-paper` is a profile at all.** Everything in §3 except the skill could live in `harness-research`, which already owns `ARTIFACTS.md` and the invariant. A separate profile is justified only if a project writes manuscripts without doing the experiments — which does happen (a survey, a position paper). Decide after T2, when the config's real shape is known.


---

## T2 result (2026-08-18) — the design changed on measurement

**T2 ran before the rule and the skill were written, which is what the sequence was for.** The four manuscripts in `ehr-research/pubs/*/paper/` were checked against the one `ARTIFACTS.md` that exists among them.

**The first run failed loudly: 854 claims and 519 findings on a 574-line paper.** A check that reports 519 findings is a check somebody switches off, which §4's table already names as the way a false-positive check becomes worth zero.

Splitting the tokens by where they sit explained it, and reversed a design decision made by reasoning:

| Where the numbers are | Count in that paper | What they are |
|---|---|---|
| Inside 12 table/figure blocks | 493 | Cells produced wholesale by a run |
| Inside inline math `$…$` | 333 | Subscripts, indices, thresholds — notation |
| Plain prose | 43 | The headline claims |

**§3b said "numbers inside math mode stay claims — that is where a manuscript's results live". That was wrong.** In a manuscript, math is where *notation* lives; results live in table cells and in plain prose. The measurement is what caught it — the reasoning behind the original line was plausible and produced a check nobody could use.

**Two rules changed as a result**, and both are pinned by cases:

- **Inline math is skipped.** A number in `$…$` is notation.
- **Table and figure blocks are skipped and counted, not checked.** Requiring every cell to appear in `ARTIFACTS.md` is a demand nobody meets; what those blocks need is a provenance row naming the run, and that is a *different check*. The script now reports how many blocks it did not look at rather than drowning the prose findings in cells.

**After the change, T2 passes and is actionable**: 34 prose claims and 5 findings on that paper (12 blocks skipped), and 8 / 13 / 4 claims with no findings on the other three.

### What this means for the rest of the plan

- **§3b is done and shipped.** `check-claims.sh` reads LaTeX, the suite went 36 → 50 cases, and the Markdown cases are unchanged (T3).
- **§3a, §3c and §3d are not started, and §3a's shape is now in question.** The token-level check needs only a path — no `artifacts` key, no `sweep` key — so a three-key config may be two keys more than the checker wants. Decide the config's shape from what the *rule* and the *skill* need, once those exist.
- **A new item, and it is the one with the most value left**: block-level provenance. *Does every table and figure declare the run that produced it, and is that run in the artifact map?* That is O(10) findings per paper instead of O(500), it is what the 493 skipped tokens actually need, and it did not exist in the source repository either.
- **T1 is untested** because nothing reads a config yet.


---

## Block provenance shipped (2026-08-18)

The item the T2 result named as *the one with the most value left* is now `plugins/harness-slides/scripts/check-provenance.sh`, with 21 cases.

**It is a second script rather than a mode of the first, because it answers a different question at a different granularity.** `check-claims.sh` asks whether a *number* appears in the artifact map — right for prose and for a deck that quotes a handful of figures, useless for a table. This asks, once per block, *does this say which run produced it, and is that run in the map?* Folding it into the first would also have changed that script's contract for every existing Markdown deck.

**The marker is a comment**, so it is native to the format and invisible in the built output — `% source: make eval-main` in LaTeX, `<!-- source: make eval-main -->` in Markdown. No macro to define, no package to load, and it works on the line above the block or inside it.

**The exit codes are split, and that split is the design.** A marker naming a run nobody recorded fails; a block with no marker is reported and does not. Collapsing them would fail every document on first contact — measured: the four test manuscripts have 12, 5, 5 and 5 blocks and **not one carries a marker**, because the convention did not exist until now. `--strict` turns unmarked blocks into a failure once a document has been marked up, the way `context-budget.sh`'s `--require-plugins` turns a partial measurement into a gate.

**The two checks partition the document, and a case pins it.** The blocks `check-claims.sh` skips are exactly the blocks this one counts — verified on the four manuscripts (12 and 12, 5 and 5) and asserted in `verify-check-provenance.sh`, so a number can never be both skipped by one and ignored by the other.

### Still open

- **§3a, §3c, §3d** — the config, the rule and the skill. Both checkers take paths as arguments and need no config at all, so §3a's three keys are now clearly a guess made before the checks existed. Decide its shape from the rule and the skill.
- **T1** remains untested; nothing reads a config.
- **Adoption has no path yet.** The convention exists and nothing tells an author about it. That is what the skill in §3d is for.


---

## The skill shipped (2026-08-19)

`manuscript-audit` is §3d, in `harness-slides` beside the two checkers it calls.

**Placement was forced, not chosen.** A skill reaches scripts through `${CLAUDE_PLUGIN_ROOT}`, which is its *own* plugin, and cross-plugin references are forbidden — so the skill has to live where the checkers live. §7's question is therefore still open but now has a mechanism attached: `harness-core/bin/` is on the Bash tool's PATH for every session, and every profile depends on core, so promoting the two checkers there is what lets the skill move to `harness-research`. That is a structural change and belongs in its own PR.

What did change is the profile's description, which was narrower than the profile: `harness-slides` now says it covers claim traceability for **what a result becomes** — a deck outline and a manuscript audit. Two skills, one job, two outputs.

**Running the body end to end found three defects**, which is the step a trigger eval cannot cover:

- Listing candidates with `git ls-files '*.tex' '*.md'` returned **53 files in a repository with no manuscript at all**, and `head` hid the rest without saying so. It now greps for `\begin{document}`.
- The artifact-map glob offered `harness-research`'s **template**, and auditing against an empty template reports every number as untraceable — which reads exactly like a catastrophic finding.
- `check-provenance.sh`'s summary printed two of its three categories, so on a real draft it said *1 carry a source, 10 do not* out of 12 and left the reader to wonder about the twelfth.

### Routing: 12/12, and a discarded first measurement worth more than the number

The first run scored **1/6 positives** and it was the instrument. Nearly every trial returned `no tool call`, the six negatives included — and a room where nothing fires passes every negative trivially. The prompts named files the working directory did not contain, so the model answered *there is no such file*; the bench measured the fixture's emptiness. Against a fixture that actually holds a manuscript and an artifact map, the same twelve queries and the same description scored **12/12, pass^3 1.00**, with all three named neighbours taking their work 3/3.

**The lesson is a new instance of an old rule and belongs with the others**: a trigger fixture has to satisfy its own prompts' premises, and nothing checks that. Recorded in §4b.

### Still open

- **§3a and §3c** — the config and the rule. Both checkers and the skill take paths as arguments and need no config, so §3a's three keys remain a guess made before anything existed. The rule is the last piece that would need one.
- **T1** remains untested; nothing reads a config.
- **Promoting the checkers to `harness-core/bin/`**, which is what unblocks moving the skill to `harness-research`.

# paper-figures Plan — the producer side of the provenance convention

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> Dated design record. Counts quoted below describe the tree at the time of writing; [`agent-layer.md`](../../agent-layer.md) is the source of truth for current numbers.

**Goal:** Make the figure-provenance convention adoptable. `check-provenance.sh` reads a marker that says which run produced a table or figure; nothing writes one. Add the writer, and take manuscript *authoring* from an external plugin instead of building it.

**Architecture:** Not a figure library. [`2026-08-18-harness-paper.md`](2026-08-18-harness-paper.md) records the gap in its own words — *"Adoption has no path yet. The convention exists and nothing tells an author about it."* — and measured why it matters: the four test manuscripts carry 12, 5, 5 and 5 blocks and **not one carries a marker**. `manuscript-audit` reads the convention. This is the writer of the same convention, so it is the second half of a mechanism that already ships with 21 verification cases, not a new subsystem.

**Tech Stack:** matplotlib and TikZ on the consumer's side; the skill body is prose. Calls `harness-check-provenance` from `harness-core/bin` (on the Bash tool's PATH since [#79](https://github.com/chpark-ML/agent-harness/pull/79), which is what lets this skill live in `harness-research` rather than beside the checkers).

---

## 1. Where this came from

A survey of twelve external repositories on 2026-08-20. Four were read in full: [`ruvnet/ruflo`](https://github.com/ruvnet/ruflo), [`chrischoy/figura`](https://github.com/chrischoy/figura), [`PM-Shawn/tikz-scientific-figures`](https://github.com/PM-Shawn/tikz-scientific-figures), [`WenyuChiou/academic-writing-skills`](https://github.com/WenyuChiou/academic-writing-skills). Eight more were surveyed at manifest level.

**Every figure candidate makes figures well and none ties a figure to the run that made it.** That is the whole finding. `figura` runs a render → view → fix loop and delegates image audit to a subagent so image bytes stay out of the main context. `opentikz` ships parametric templates so an agent edits rather than hand-writes TikZ. `research-skills` has seven figure skills. None of them emits anything a provenance check could read, because none of them has a provenance check.

**Two of the three figure candidates cannot be vendored.** `figura` shows an MIT badge in its README and **ships no LICENSE file** — the GitHub API reports no license, and there is no such file in the tree. `tikz-scientific-figures` has no repository LICENSE either (only the vendored editor's own). Their code is readable for ideas and not copyable. [`opentikz`](https://github.com/opentikz/opentikz) is the exception and the reason it is in this plan: **MIT for code, CC0 for content**, so its templates and icons can be vendored outright.

## 2. The admission tests, decided before anything is written

**F2 is the load-bearing one.** The other three are ordinary bundle discipline.

- [ ] **F1 — zero config is silence.** A project that draws no figures must not notice this skill exists. It is a skill, not a hook, so this is nearly free — but the skill must not instruct anyone to create `ARTIFACTS.md` in a repository that has no notes.
- [ ] **F2 — the writer and the reader agree by construction.** The exact marker string this skill emits must be accepted by `harness-check-provenance` in both LaTeX (`% source: <command>`) and Markdown (`<!-- source: <command> -->`), **pinned by a case in `plugins/harness-core/scripts/verify-harness-check-provenance.sh` that quotes the skill's own template.** Two halves of one convention that agree only because the same author wrote both on the same day is how they drift on the third edit.
- [ ] **F3 — routing survives the additions.** Measure before shipping, not after. Two distinct risks: our new description entering a trigger space that already holds Superpowers' 14, and — if §5 proceeds — the dependency's `paper-review` sitting next to our `pr-review` under near-identical names.
- [ ] **F4 — the ceiling holds, measured in CI.** Headroom is roughly 700 tok (badge: 8.3k against the 9,000 gate; `README.md:203` records ~7,927 from a CI run). The new description is ~180 tok with its Korean triggers. §5's dependency adds two descriptions totalling 1,337 characters, ~334 tok. Together ~514 against ~700 — it fits on paper, and `context-budget` reads the *installed* plugin, so **only CI produces the real number.** Budget the round trip that §2d of `CLAUDE.md` describes.

## 3. What ships

Three things.

### 3a. One skill — `plugins/harness-research/skills/paper-figure/`

`harness-research` is the home because it owns `ARTIFACTS.md` and the invariant *a number not traceable through this file is not yet a result*. The 2026-08-19 note records that `manuscript-audit` was forced into `harness-slides` to reach its scripts; promoting the checkers to `harness-core/bin` removed that constraint for anything written after it.

The body is a loop with a registration step, in this order:

1. **Render** — matplotlib for data plots (`.py`), TikZ standalone for schematics (`.tex`). Dispatch on what the figure *is*, not on the file extension the user happened to open.
2. **Inspect at print size** — render to PNG at 300 dpi scaled to the column width the venue actually uses, and look at it. A first-pass figure almost always has one user-visible defect, and the ones that matter are legibility at print size, not aesthetics on screen.
3. **Fix, capped at two cycles.** The cap is the point. Without it this becomes an unbounded pixel hunt, and `figura`'s README argues the same cap from the same reasoning.
4. **Emit the provenance marker** — the line `harness-check-provenance` reads, naming the command that produced the figure.
5. **Register the row in `ARTIFACTS.md`** — so the run the marker names is a run the map knows.

**Steps 4 and 5 are the reason this skill exists.** Steps 1–3 are available from four external repositories.

- [ ] Description quoted (§4 of `CLAUDE.md`), with Korean triggers and negative routing.
- [ ] **Run the body end to end once on a real figure before merging.** This is the step no eval covers, and it has caught defects three times in this repository — `cross-model-review` merged at 12/12 with three defects in its Step 4, and `manuscript-audit`'s first real run found three more.

### 3b. Vendored CC0 templates from `opentikz`

Under `plugins/harness-research/skills/paper-figure/templates/`, with the upstream commit SHA and the CC0 designation recorded in the directory's own README. Parametric templates an agent edits beat TikZ an agent writes from scratch, because the failure mode of the second is a document that does not compile.

- [ ] Take only what a paper figure needs. A catalogue is not a deliverable.

### 3c. Trigger eval — `evals/trigger/paper-figure.json`

6 positive, 6 negative. **The negatives are the work**, and there are four neighbours to route to, which is more than usual:

| Near-miss | Should reach |
|---|---|
| "이 결과 발표자료로 만들어줘" | `results-deck` |
| "대시보드에 차트 하나 추가해줘" | `dataviz` |
| "이 실험 결과 기록해줘" | `research-notes` |
| "논문 수치 검증해줘" | `manuscript-audit` |

- [ ] Measure with `make bench-trigger` at the default 3 runs, and record the result in `docs/agent-layer.md` §4b. One run per query is not a measurement.

## 4. What does not ship, and why

| Not shipping | Because |
|---|---|
| A matplotlib style library | A style file is a preference, not a discipline. The `dataviz` skill already loads on any chart, and [`tvhahn/matplotlib-skill`](https://github.com/tvhahn/matplotlib-skill) (MIT) covers the same ground better than we would |
| `figura`'s `export.py` | Genuinely good code — traversal guard, all-or-nothing atomic promote — and **unlicensed.** The pattern is absorbable; the file is not |
| An SVG editor with save-back | `tikz-scientific-figures`'s `edit_server.py` binds 127.0.0.1 and replaces atomically, but `POST /save` has no origin check and the bundled editor carries jQuery UI 1.8.17. A local write endpoint is not worth this |
| A LaTeX build command | Already excluded by the 2026-08-18 plan, for the same reason: §4's *build and inspect* already requires running the consumer's own build |
| Our own manuscript-authoring skill | Same lifecycle stage as §5's dependency, and §7 of `CLAUDE.md` admits a new asset only for a problem that happened twice |
| Anything from `ruflo` | ~23k tok of always-on context, an unpinned `npx ruflo@latest` on every tool call with all output discarded, and a PreCompact hook that injects unsourced performance claims into the model's context. Its release workflow's reproducibility gate is worth reading; the rest is a rejection |

## 5. The manuscript-authoring stage — depend, do not build

[`WenyuChiou/academic-writing-skills`](https://github.com/WenyuChiou/academic-writing-skills) (MIT, ★17, 44 commits) as a `harness-research` dependency, **conditional on F3.**

**The dividing line is clean.** [ADR-0009](../../adr/0009-external-dependencies.md) admits a dependency at a *different* lifecycle stage. Our `manuscript-audit` verifies a finished draft against the runs behind it and explicitly does not edit. That plugin drafts and revises. Different stage, no overlap to divide.

Verified on 2026-08-20: `claude plugin validate --strict` passes, `pytest tests/ -q` gives 12 passed, all frontmatter parses, both skill descriptions are quoted.

- [ ] **F3 gates this.** `paper-review` and our `pr-review` are one character apart in the trigger space. Install at a scratch `CLAUDE_CONFIG_DIR`, run `bench-trigger` against our documented `pr-review` 11/12, and add a §3b row with the number. **If routing degrades, this stops here** and the row records why — a rejection with a measurement behind it is worth more than an adoption without one.

## 6. Absorbed regardless — the version-bump guard

The single most valuable thing in the survey is not a skill. It is one CI job in `academic-writing-skills/.github/workflows/test.yml`: **a PR touching `skills/` fails unless the plugin's `version` value also changed.**

`CLAUDE.md` §2 already states the rule — *"The version bump is not optional... committing alone delivers nothing to users"* — and enforces it with discipline, because this repository cannot install its own hooks onto itself. That job turns the sentence into a gate. Two details in it are worth copying exactly, and both are commented upstream as lessons:

- It compares against `git merge-base`, not the base branch tip, so a PR does not start failing when `main` moves.
- It compares the version **value** parsed from JSON, not the diff line, because a line that moves without changing would otherwise pass.

- [x] Write our own, covering **any** changed file under `plugins/<name>/` against that plugin's `.claude-plugin/plugin.json` — not an enumerated subset. `commands/` and `declarative/` reach the consumer from the same cached plugin as `skills/` and `hooks/`, and a list of watched directories is a list somebody forgets to extend. Structural change, its own PR (§6 of `CLAUDE.md`).

## 7. Sequence

1. - [x] **`[version-bump-guard]`** — §6. Independent of everything else, and it protects every later step in this plan from the failure mode where the work merges and reaches nobody.
2. - [x] **`[ecosystem-figures]`** — §3b rows in `docs/agent-layer.md` for the eleven candidates, with the Basis column carrying what was actually checked: license file present or absent, `claude plugin validate --strict` result, test run result, always-on bytes. Documents only.
3. - [ ] **F2 first, before the skill body.** Fix the marker template and add the case to `plugins/harness-core/scripts/verify-harness-check-provenance.sh` that quotes it. If the writer and the reader cannot be pinned to each other mechanically, the rest of §3a is decoration.
4. - [ ] **F3** — the trigger measurement, for both the new skill's description and §5's dependency. Record in §4b. This decides whether step 6 happens at all.
5. - [ ] **§3a and §3b** — the skill and the templates, with the full bundle. Then the CI round trip for F4 and the republished check total: a new `SKILL.md` is **+3** on the published total (`verify-doc-refs` scans it as a document and as an instruction file, `verify-frontmatter` once), and `make verify-all` fails until all five published copies agree.
6. - [ ] **`[depend-awskills]`** — only if step 4 says routing survives.

**Steps 1–4 are the plan.** Steps 5 and 6 are ordinary bundle work once the measurements are in.

## 8. Open decisions

- **Whether the two halves want one skill or two.** Making a figure and registering it are one workflow for an author and two concerns for a reviewer. Shipping one skill risks a body that does two things; shipping two risks a second description in a trigger space with ~700 tok of headroom. **Decide after step 3**, when the marker template exists and its cost is known.
- **Whether `paper-figure` closes the 2026-08-18 plan's §3a.** That plan left its config's shape undecided because both checkers take paths as arguments and need no config. If this skill also needs none, then §3a is answered by deletion rather than by design — which would be the right answer and should be recorded as one.
- **The Beamer collision is still open** and this plan does not touch it. A TikZ figure makes a Beamer deck natural, and `harness-slides` renders HTML through `slides-grab`. Unchanged from §7 of the 2026-08-18 plan: it needs a demand basis and there is none yet.


---

## Spike result (2026-08-20) — the cap earned its number, and the loop is not monotonic

The question the spike had to answer was not "can TikZ draw this" but **can the loop in §3a reach a figure an author would paste into a paper**. It was run against the three reference SVGs the user supplied, of which one — a method figure for a patch-level prediction and position-gating architecture — is the class this skill targets. The other two are slide diagrams with third-party logo bitmaps and are the negative-routing case, not the target.

**What was built.** A data-panel renderer (matplotlib → PDF, seeded) plus a `standalone` TikZ figure that composes it, compiled with pdfLaTeX to a **333.6 × 77.1 pt vector PDF** — 4.63 × 1.07 in, a single column. Every constant was read off the reference rather than invented: the palette (`#1C5A94` structural, `#DABDBD` encoder, `#FAF09D` classifier, `#CAE9F2` gate, `#C6E7CD` position, `#DCDADA`/`#C4C4C4` volumes, `#575757` rules) and the stroke ladder.

**The stroke ladder is the one constant that had to be transformed, not copied.** The reference quantises stroke width to exactly four values — 3, 5, 10, 15 — but the export is 14067 px wide for a figure that prints at roughly 7 in, so those numbers carry the export scale and not the design. The **ratio** 1 : 1.67 : 3.33 : 5 is the design, and it maps onto 0.2 / 0.35 / 0.7 / 1.05 pt. A skill that copies absolute units out of an SVG will produce hairlines or slabs depending on what the exporter happened to choose.

### The measured defect sequence

| Render | Found at 300 dpi, print size |
|---|---|
| 1 | **3** — the dashed group edge ran through the group heading; the input label overlapped the box corner and escaped the frame; both trapezoids widened vertically instead of along the flow |
| 2 | **2** — the shape labels collided with the volume stack and clipped their accents; the module captions had been pushed *outside* the box **by cycle 1's own padding fix** |
| 3 (the cap) | **1** — visible only at 900 dpi: the `\hat{}` accent on one label was erased by the opaque white background placed behind the heading **in cycle 1** |

**§3a's two-cycle cap was argued from someone else's README. It now has a reason of its own: the loop is not monotonic.** Cycle 1's fix for the heading collision caused the clipped accent found in cycle 3, and cycle 1's padding change caused a caption regression found in cycle 2. Two of the three later defects were *introduced by earlier fixes*. Iterating past the cap trades one defect for another, so what the cap produces is not a finished figure — it is a figure plus **one named remaining defect**, handed back. That is a different deliverable from "done" and the skill body has to say so.

### Three things this settles

- **§8's first open decision closes: one skill.** The data panel and the schematic are two *stages*, not two concerns — one `.tex` composes both, and the composition is where the print-size defects appear. There is no seam to split on.
- **§3a step 2 must name its renderer, and the name is `pdftoppm` on the compiled PDF.** The reference SVGs rendered through Inkscape showed every embedded logo clipped — `erdock`, `ckerdoc`, a ghosted wordmark — and QuickLook rendered the same files correctly. The cause is Figma's `patternContentUnits="objectBoundingBox"` with a `<use transform="matrix(…)">` and `preserveAspectRatio="none"`, which Inkscape mis-scales. **An inspection renderer that disagrees with the publication renderer makes the loop chase defects that do not exist**, and it nearly did here — the clipping was read as a defect in the user's figure before a second engine cleared it.
- **The boundary between the two stages is a rendering, not a drawing.** The reference contains an MRI volume and heatmap cubes. Those are renderings of arrays and TikZ cannot draw them, so they are produced from data, under a fixed seed, and placed with `\includegraphics`. This is also what makes the provenance marker natural rather than bolted on: the panel already has a command behind it.

### What the compiled figure gains over the reference

Not a style argument — these are properties of the artifact. The math is real LaTeX, so `\hat{\mathbf{X}}\in\mathbb{R}^{w\times h\times d\times f}` sets in the document's own font at the document's own size instead of being frozen paths; the text is selectable and searchable, where the reference export contains **zero `<text>` elements**; the file is 102 KB against 1.9 MB; and changing a symbol is an edit and a recompile.

### Still not measured

- **The skill body.** The spike proves the pipeline is reachable *by hand*. Whether the written procedure gets a model there is what §3a's "run the body end to end once" is for, and it is the step no eval covers.
- **Freehand organic shapes.** The reference's brain silhouette and the slide diagrams' mascot logos are not TikZ work, and the plan should say which figure kinds it declines rather than discover it mid-loop.
- **Who reads the fix.** Judging the remaining defect at the cap requires knowing TikZ. The skill mechanises the loop; it does not remove that.

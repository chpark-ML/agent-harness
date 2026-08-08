---
name: results-deck
description: "Use when development or research results in this repository need to become a presentation — turns the repo's own artifacts (FINDINGS, ARTIFACTS, experiment_plan, a changeset, a release) into a deck outline in which every number is traceable to the run that produced it, then hands rendering to slides-grab. Use it for the development side too — a release readout, a stakeholder or sprint review, a demo — any time a changelog, PR list, or benchmark output has to become something people sit through. Reach for it even when the user never says 'slides' or 'deck': a readout, a write-up, or 자료 built from work already in the repo is this skill. 한국어 트리거: '결과 발표자료 만들어줘', '실험 결과 슬라이드로', '이번 작업 발표용으로 정리', '데모/리뷰 자료 만들어줘', '연구 결과 정리해서 보여줘', '릴리스 정리해서 보고 자료로', '스테이크홀더 리뷰용으로 정리해줘'. 슬라이드의 *렌더링·디자인·편집·PDF 변환* 은 이 스킬 말고 slides-grab 의 스킬들로 (slides-grab-plan/html/design/export), 노트 자체를 만들고 유지하는 것은 research-notes 로."
---

# results-deck

Turns artefacts into a **narrative**. It does not render — `slides-grab` does that far better, and this skill's output is that tool's input.

There is one reason this skill exists. **A results talk is where untraceable numbers get quoted.** The notes may record which run produced a table, but the moment it moves onto a slide the number survives and the evidence falls away. And then the audience quotes that number and decides things with it.

## Step 0 — What is being presented

One of two. Do not mix them.

- **Research results** — sourced from `FINDINGS.md` (what came to be believed), `experiment_plan.md` (how it was found out), `ARTIFACTS.md` (where it came from). If the note set does not exist, run `research-notes` first.
- **Development results** — sourced from the change history, PR bodies, release notes, benchmark output.

## Step 1 — Collect the evidence first

**Gather the numbers before writing any slides.** Reversed, you end up looking for numbers that fit the narrative, which is choosing evidence to match a conclusion already decided.

If `ARTIFACTS.md` exists, that is the list of quotable numbers. If it does not, build the table first — claim · the command that produced it · where the output is · date. A number not in that table does not go on a slide.

## Step 2 — The narrative

One claim per slide. The skeleton of a results talk:

```
1  what the problem was      (why this work happened — in the audience's language)
2  what was done             (the approach, one slide)
3  what was found            (the core result — the numbers gather here)
4  how much to believe it    (sample, variance, controls, how to reproduce)
5  what is not established    (limits, and results that were overturned)
6  next                      (one concrete action)
```

Do not drop 4 and 5. **A talk with no overturned results reads as a talk where they were deleted** — the same reason `FINDINGS.md` preserves reversals. A negative result is a result.

## Step 3 — The traceability check

Once there is a draft, check it by machine. That is not the same as reading it over.

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/check-claims.sh" <deck.md> [ARTIFACTS.md]
```

It asks whether every number in the deck appears in the evidence file. A flagged number is one of two things — a figure nobody can reproduce, or a row missing from the evidence table. **Decide which before acting**: if the row is missing, add it; if the number cannot be reproduced, take it off the slide.

Years, dates, versions, list numbers, slide references, identifiers shaped like `ADR-0008`, link targets, inline code and HTML comments are excluded by the checker itself. Only the remaining exceptions — a bare number after a word, like `bash 5` — get a `<!-- no-claim -->` on that line. **Never use `<!-- no-claim -->` to let an unsupported number through.** The moment you do, the check becomes decoration.

**Do not hand a draft that fails the check to the renderer.**

## Step 4 — Hand off to rendering

If `slides-grab` is installed, pass the outline to its skills (`slides-grab-plan` → `slides-grab-html` → `slides-grab-export`). If it is not, `harnessctl doctor` prints the install command. This skill ends here — design, layout and PDF are not rebuilt.

## What this skill does not do

- Render or design slides.
- Put an approximate number on a slide because the evidence table has no row for it.
- Drop the limits section. If space is short, shorten a different slide.

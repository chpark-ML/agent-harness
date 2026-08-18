---
name: manuscript-audit
description: "Use before submitting or revising a paper, when the numbers in a manuscript need checking against the runs that produced them — audits a LaTeX or Markdown draft in two passes, prose figures against ARTIFACTS.md and every table and figure against the run it names, and reports a ranked list without editing the draft. 한국어 트리거: '논문 수치 검증해줘', '논문이랑 코드 정합성 봐줘', '이 표 어디서 나온 거야', '투고 전에 숫자 점검', '원고 수치 추적 확인', '제출 전 검증'. 결과를 발표자료로 만드는 것은 이 스킬 말고 results-deck, 결과를 노트에 기록하는 것은 research-notes, 실행을 재현 가능하게 만드는 것은 repro-checklist 로."
---

# manuscript-audit

Checks that **every number a manuscript states can be traced to the run that produced it**, and reports what cannot.

The invariant is not this skill's — `harness-research`'s `ARTIFACTS.md` already states it: *a number not traceable through this file is not yet a result*. What this skill does is apply it to the one document where breaking it is most expensive, because a paper's numbers outlive the session, the repository and often the author's memory of which script made them.

**It reports and does not edit.** A finding here is either a missing row in the notes or a wrong number in the draft, and which one it is takes judgement the audit does not have.

## Step 0 — Is a manuscript actually in play?

This skill wants a draft — `.tex`, `.md`, or another plain-text manuscript — and the artifact map it should agree with. If the request is about turning results into a talk, hand off to `results-deck`. If it is about recording a result, `research-notes`. If it is about making a run repeatable, `repro-checklist`.

## Step 1 — Find the two inputs

```bash
git grep -l '\\begin{document}' -- '*.tex' '*.ltx'   # LaTeX manuscripts, not styles
git ls-files '*ARTIFACTS*' | grep -v templates/       # the artifact map, not its template
```

**Do not list every `.md` in the repository.** Measured on a repository with no manuscript at all, `git ls-files '*.tex' '*.md'` returned 53 files — `CLAUDE.md`, agent definitions, ordinary documentation — and truncating that list with `head` hides candidates without saying so. `\begin{document}` is the signal that discriminates. For a Markdown manuscript there is no equivalent marker, so **ask which file it is** rather than guessing from a glob.

**Excluding `templates/` matters.** `harness-research` ships an `ARTIFACTS.md` template, and a repository that has never created the real one will offer the template instead — auditing a draft against an empty template reports every number as untraceable, which reads exactly like a catastrophic finding.

**Name both files to the user before running anything.** A manuscript audited against the wrong artifact map produces a long list of findings that are all noise, and the user cannot tell that from a real one.

If there is no artifact map, stop and say so. The audit has nothing to check against, and inventing one from the results directory is how a provenance check starts certifying its own guesses. `research-notes` creates the set.

**One trap worth naming.** A `*.tex` glob sweeps in `preamble.tex` and style files, whose lengths and package options are not claims. The checker warns when it reads a `.tex` with no `\begin{document}` and no sectioning — if that warning appears, narrow the path rather than ignoring it.

## Step 2 — Two passes, because a manuscript has two kinds of number

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/check-claims.sh"     <manuscript> <ARTIFACTS.md>
bash "$CLAUDE_PLUGIN_ROOT/scripts/check-provenance.sh" <manuscript> <ARTIFACTS.md>
```

The two partition the document, and knowing why keeps the report honest.

- **Prose figures** — the headline claims, in sentences. `check-claims.sh` asks whether each appears in the artifact map. Inline math is skipped: in a manuscript that is notation, not results.
- **Tables and figures** — cells produced wholesale by a run. Requiring every cell in the artifact map is a demand nobody meets, so `check-provenance.sh` asks once per block instead: does it name the run that made it?

A block names its run in a comment, which is invisible in the built output:

```
% source: make eval-main                     LaTeX
<!-- source: make eval-main -->              Markdown
```

The comment goes above the block or inside it, and its text must appear somewhere in the artifact map.

## Step 3 — Rank the findings, and separate the two kinds

The checkers report; **the ranking is this skill's job**, because they carry very different weight.

1. **A block naming a run that is not in the artifact map.** Worst of the three: the draft asserts provenance it does not have, and a reader who checks will find nothing. Either the row is missing from the notes or the name is wrong.
2. **A prose figure that appears nowhere in the artifact map.** A number a reader cannot reproduce. Often a stale value left behind by a re-run.
3. **A block with no source comment at all.** Honest but unregistered. On a draft that has never been marked up this is *every* block, so report it as a count with the file and line list, not as N separate findings.

For each item give `file:line`, the number or marker text, and which of the two fixes applies — add the row to the artifact map, or correct the draft. Do not guess which; say what each would mean.

## Step 4 — Say what was not checked

Both checkers are deliberately dumb about meaning. State the limits with the findings, or the report reads as a clean bill of health it did not earn:

- A number copied into the wrong sentence still passes, as long as the digits appear in the artifact map.
- Display math (`\[…\]`, `equation`) is not parsed; only inline `$…$` is skipped as notation.
- Table cells are never compared to the run's output — only the block's *registration* is checked. Comparing values is a separate job and this skill does not do it.

## What this skill does not do

- Edit the manuscript. Step 3 produces a list; the user chooses.
- Build the paper. That is the project's own command.
- Judge whether a number is *correct* — only whether it is traceable.

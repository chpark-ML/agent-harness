---
name: research-notes
description: "Use to create or maintain the five-document research-note set (STATUS, experiment_plan, FINDINGS, ARTIFACTS, review_log) for a research project — bootstrapping the set in a new project directory, or recording a result into the right file afterwards. 한국어 트리거: '연구 노트 세팅', '실험 기록 어디에 남겨', 'STATUS 갱신해줘', '이 결과 기록해줘', 'FINDINGS 정리', '체크포인트 남겨줘'. 재현 가능한 *실행* 셋업(seed·환경·config)은 이 스킬 말고 repro-checklist, PR 생성은 pr-create 로."
---

# research-notes

**Creates** the five documents defined in `.claude/rules/harness/research/notes.md`, and afterwards **routes each result to the file it belongs in**.

Two paths — § A (bootstrap) for a new set, § B (maintenance) for one that exists.

---

## A. Bootstrap — create the five documents

### A1. Settle on the target directory

If the user did not give a path, infer one and **confirm before proceeding**. The convention does not dictate location (`docs/`, `notes/`, `projects/<name>/`, anything), so guessing wrong produces a second note set and breaks R1's single entry point.

Check for an existing set first:

```bash
find . -name STATUS.md -not -path '*/.git/*'    # if one exists, that directory is the target
```

### A2. See what is already there — **never overwrite**

```bash
ls -1 <target-dir>/{STATUS,experiment_plan,FINDINGS,ARTIFACTS,review_log}.md 2>/dev/null
```

Leave existing files alone. Empty counts as existing — the user may have started one.

### A3. Copy only what is missing

Templates live in this skill's [`templates/`](templates/).

```bash
cp .claude/skills/research-notes/templates/<NAME>.md <target-dir>/<NAME>.md
```

### A4. Substitute

Fill two placeholders in each copied file.

- `<PROJECT>` → the project name (directory name, or what the user gave)
- `<YYYY-MM-DD>` → the output of `date +%F`

**Leave the `<!-- EXAMPLE ... -->` block** at the end of each template in place. It exists to show the shape; delete it when the first real entry arrives.

### A5. Report

Report created files and **files left alone because they already existed** separately. Omitting the second group leaves the user thinking something was overwritten.

---

## B. Maintenance — where a result goes

When the user reports a result, a judgement or a review, apply this routing. **More than one row can apply at once.**

| What the user reported | File to update |
|---|---|
| ran an experiment or a job (whatever the outcome) | a new `experiment_plan.md` entry — **always**. Plus `STATUS.md` |
| produced a number that might be quoted somewhere | plus an `ARTIFACTS.md` row |
| **what is believed changed** (established or overturned) | plus `FINDINGS.md` |
| went through a review or checkpoint | a new dated `review_log.md` entry |

Three rules:

1. **Always write the ledger entry.** Failed runs and runs that produced nothing are recorded too — stopping someone re-running the same thing is half of what a ledger is for. New entries go at the **end** of the file.
2. **`FINDINGS.md` only when a belief changes.** It is not updated per run. When a conclusion is overturned, take it out of the table and keep it in the reversals section — `notes.md` R3.
3. **`STATUS.md` is rewritten.** Change the date in the title with it. Do not push the old content down and accumulate.

### Writing a ledger entry

Write `Setup` so the run can be repeated — the verbatim command, configuration, code revision, input identifiers. What has to be captured is defined by the [`repro-checklist` skill](../repro-checklist/SKILL.md). Put facts in `Result` and send interpretation to `FINDINGS.md`.

### Writing an `ARTIFACTS.md` row

If the output sits in a session scratchpad or temp directory, **move it to a durable path before writing the row.** The moment that path disappears the claim survives without its evidence.

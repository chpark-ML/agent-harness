---
description: Five-document research-note discipline (STATUS / experiment_plan / FINDINGS / ARTIFACTS / review_log) — which file is the entry point, which are append-only, and which may be rewritten.
paths: ["**/*"]
---

# Research — note discipline

One directory per research project; the project chooses its path. The `research-notes` skill maintains these files.

**Precedence:** `CLAUDE.md` ⊂ [workflow](../workflow.md) ⊂ this file ⊂ skills and agents; narrower scope wins.

| Document | Role | Updates |
|---|---|---|
| `STATUS.md` | single session entry point | rewrite current state |
| `experiment_plan.md` | chronological experiment ledger | append only |
| `FINDINGS.md` | established conclusions and reversals | rewrite; preserve reversals |
| `ARTIFACTS.md` | claim-to-evidence map | add rows and correct paths |
| `review_log.md` | checkpoint history | append only |

## R1 — `STATUS.md` is the only entry point

Keep a dated account of current state, work in flight and next actions sufficient to resume a session. Put history in the ledger, not STATUS; do not maintain a second current-state document.

## R2 — `experiment_plan.md` is a chronological ledger

Append numbered intent → setup → result entries. Preserve earlier entries; correct them in a new entry. Setup includes the command, configuration, revision and inputs needed to reproduce the run; use `repro-checklist`. Keep interpretation in FINDINGS.

## R3 — `FINDINGS.md` is a cross-section, and it preserves reversals

Record what is established now and the controls each conclusion passed. When overturned, remove a conclusion from the current table but retain it with the evidence that reversed it.

## R4 — `ARTIFACTS.md` maps claims to artefacts

Before publishing a number, record its claim, producing run or command, durable output path and date. Include logs. Session temp files are not durable evidence; an untraceable number is not an established result.

## R5 — `review_log.md` is an append-only checkpoint history

Append dated checkpoints. First classify the previous checkpoint's action items as resolved, open or regressed; then add new findings.

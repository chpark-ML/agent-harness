---
description: Five-document research-note discipline (STATUS / experiment_plan / FINDINGS / ARTIFACTS / review_log) — which file is the entry point, which are append-only, and which may be rewritten.
paths: ["**/*"]
---

# Research — note discipline

**One directory per research project**, holding five documents. The consumer project chooses the path (`docs/`, `notes/`, `projects/<name>/` — this convention does not dictate location, it dictates the *set*).

**Precedence.** `CLAUDE.md` ⊂ [`../workflow.md`](../workflow.md) ⊂ this file ⊂ skills and agents. The narrower scope wins. Creating and maintaining the files is the `research-notes` skill.

## Write permissions at a glance

| Document | Role | How it is updated |
|---|---|---|
| `STATUS.md` | **the single entry point** | rewritten whole — it holds only the present |
| `experiment_plan.md` | chronological ledger | **append at the end.** Earlier entries are never edited |
| `FINDINGS.md` | a cross-section of the ledger — what is believed now | rewritten, **except that reversals are never deleted** |
| `ARTIFACTS.md` | the map from claim to artefact | rows added, paths corrected |
| `review_log.md` | checkpoint history | **append at the end.** Earlier entries are never edited |

---

## R1 — `STATUS.md` is the only entry point

A new session must be able to resume **by reading this file alone**. It holds three things: *where things stand*, *what is in flight*, *what happens next*. Put the date next to the title and change it when you change the content.

- Do not accumulate past-tense narrative here. History lives in the ledger and in git.
- Do not describe "current state" in a second document. Two of them will diverge, and the new session will read the stale one.
- A stale date on unchanged content is itself a signal — an entry point nobody updates is worse than none.

## R2 — `experiment_plan.md` is a chronological ledger

Numbered entries, each carrying **intent → setup → result**. New entries go **at the end**.

- **Do not rewrite earlier entries.** If something turned out to be wrong, say so in a new entry. The ledger's value is that it preserves *what was known at the time*.
- Write `setup` so the run can be repeated — command, configuration, code revision, inputs. Reproducibility requirements are the `repro-checklist` skill.
- Keep interpretation out of `result`. Interpretation belongs to the document in R3.

## R3 — `FINDINGS.md` is a cross-section, and it preserves reversals

The ledger is chronological, so it cannot answer "what is established now". This document is that cross-section. Record each result **with the controls it passed** — a number that survived no control is not an established result.

**Reversals are not deleted.** When a conclusion is overturned, take it out of the table but keep it in a separate section along with *what overturned it*. Two reasons.

- It stops the same hypothesis being raised again.
- **A FINDINGS with no reversals is a signal that it is not being kept honestly.** The odds that nothing was overturned during a live research project are lower than the odds that something was quietly deleted.

## R4 — `ARTIFACTS.md` maps claims to artefacts

One row per claim. Columns: *claim · the run or command that produced it · where the output is · date*.

**A number not traceable through this file is not yet a result.** The row comes before the number appears in a document, a talk, or a PR body.

- Output sitting in a session temp directory or a scratchpad is not a location. When the session ends the claim survives and the evidence does not.
- Treat logs as artefacts too. Moving only the metrics file leaves the number without its provenance.

## R5 — `review_log.md` is an append-only checkpoint history

Add dated checkpoints at the end. **Each checkpoint begins by judging the previous entry's action items as resolved, open, or regressed.**

Without that diff, new findings simply pile up, the same item reappears as a fresh discovery every time, and nobody knows what was actually fixed. Judge first, then add.

---

## What this discipline prevents

All three have happened.

1. **A session that cannot be resumed** — state scattered across documents, so a new session spends half its context working out what to do first. → R1.
2. **A number nobody can reproduce** — the figure is in the document and the run that produced it is not findable. The claim survives, the evidence does not. → R4.
3. **A conclusion quietly rewritten** — something shown to be wrong is replaced without a trace, and weeks later the same hypothesis is raised again. → R2, R3.

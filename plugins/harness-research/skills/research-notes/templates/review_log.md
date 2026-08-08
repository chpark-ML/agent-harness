# <PROJECT> — review log

> **Append-only.** New checkpoints go at the end, and earlier entries are not edited.
> Every checkpoint **starts by ruling on the previous entry's action items** — resolved, open or regressed.
> Skip that ruling and only stack new items, and the same objection keeps returning as if it were new.

---

## Checkpoint 1 — <YYYY-MM-DD>

First checkpoint (no history yet — nothing to rule on).

### Action items

| # | Priority | Item | Where |
|---|---|---|---|
| P0-a | blocking | | |
| P1-a | normal | | |

### Bottom line

<One paragraph: what the real priority is right now, and why the rest comes after it.>

<!-- EXAMPLE — delete this. The shape of every checkpoint after the first:

## Checkpoint 2 — 2026-02-01

### Ruling on the previous items

| # | Item | Ruling | Basis |
|---|---|---|---|
| P0-a | baseline numbers existed only in a temp path | resolved | moved to `/srv/runs/`, row added to ARTIFACTS.md |
| P0-b | cause of B's latency unidentified | open | not started |
| P1-a | variance across seeds | regressed | §7 widened the range from 0.9 to 2.4 |

### New items

| # | Priority | Item | Where |
|---|---|---|---|
| P0-c | blocking | do not quote §7's numbers until it is settled whether the wider variance came from the config change | experiment_plan.md §7 |

### Bottom line
P1-a regressing is what matters this round — it comes before P0-b. At that spread the §5 and §7
comparisons do not hold at all.
-->

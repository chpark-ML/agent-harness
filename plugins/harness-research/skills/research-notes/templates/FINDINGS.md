# <PROJECT> — findings

> A **cross-section** of [`experiment_plan.md`](experiment_plan.md). The ledger runs in time order, so it
> cannot answer "what is believed now". This document is that answer. Last updated <YYYY-MM-DD>.
>
> **How to update it.** When a new ledger entry changes a conclusion, edit that row in §1 and update its
> source — but **do not delete the reversal, move it to §2.** Findings with no reversals recorded are
> findings nobody has been honest with.

## 1. Established

Each entry carries **the controls it survived**. A number that survived no control does not enter this table.

| Finding | Number | Controls it passed | Source |
|---|---|---|---|
| | | | §N |

## 2. Reversals

| Previous conclusion | What overturned it | Conclusion now | Date |
|---|---|---|---|
| | | | |

<!-- EXAMPLE — delete this. What a filled-in table looks like:

## 1. Established
| Finding | Number | Controls it passed | Source |
|---|---|---|---|
| A matches the baseline | 70.9 vs 71.2 | 3 seeds, input hashes match, clean tree | §0 |
| B's latency is not I/O | wall 2.1x / io_wait 1.02x | warm and cold cache, same hardware | §5 |

## 2. Reversals
| Previous conclusion | What overturned it | Conclusion now | Date |
|---|---|---|---|
| B's latency is disk I/O | §5 found io_wait at 1.02x, essentially unchanged | CPU cost in the serialisation path | 2026-01-22 |
-->

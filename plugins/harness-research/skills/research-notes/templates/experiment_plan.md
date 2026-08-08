# <PROJECT> — experiment plan (ledger)

> **A ledger, in time order.** New entries go at the **end**, and earlier ones are not edited. If something
> turns out to be wrong, say so in a new entry — the ledger's value is that it preserves *what was known then*.
>
> The current state is [`STATUS.md`](STATUS.md); what is believed right now is [`FINDINGS.md`](FINDINGS.md).
> Put facts in `Result` and send interpretation to `FINDINGS.md`.

---

## 1. <title> (<YYYY-MM-DD>)

**Intent.** <What this was meant to settle. What outcome would confirm it, and what would refute it.>

**Setup.** <The verbatim command, configuration, code revision, inputs. This entry alone has to be enough to run it again.>

**Result.** <What came out. Numbers with their source — is there a row for it in `ARTIFACTS.md`?>

<!-- EXAMPLE — delete this. What a filled-in entry looks like:

## 0. Baseline reproduction (2026-01-15)

**Intent.** Reproduce the published baseline in our environment. |Δ| ≤ 2 counts as the environments
agreeing, and becomes the starting point for later comparisons. Above that, find out what differs
first — the comparison does not hold otherwise.

**Setup.** `scripts/run_baseline.sh --seed 0 --config configs/base.yaml`, code `a1b2c3d` (clean tree),
seeds 0/1/2, three runs. Input `data/v3/` (sha256 `4f9a…`). Output `runs/2026-01-15-baseline/`.

**Result.** 70.9 (mean of 3 seeds, range 70.4–71.3) against a reported 71.2. |Δ| = 0.3, inside the
threshold. The spread across seeds was 0.9, wider than expected, so single-seed comparisons are out
from here on.
-->

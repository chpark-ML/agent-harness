# <PROJECT> — artifacts

> **The map from a claim back to what produced it.** One row is one claim.
> **A number this table does not trace is not a result yet** — the row comes before the number goes into a document, a talk or a PR.
> Last updated <YYYY-MM-DD>.

**Where output lives.** A session scratchpad or a temp directory is not a location. Once the session ends the claim survives and the evidence is gone.
Logs rank with the output, not below it — move the metrics and leave the logs behind and you keep the number while losing where it came from.

| Claim | Run / command that produced it | Where the output is | Date |
|---|---|---|---|
| | | | |

<!-- EXAMPLE — delete this. What a filled-in table looks like:

| Claim | Run / command that produced it | Where the output is | Date |
|---|---|---|---|
| "baseline reproduces at 70.9 (range 70.4–71.3)" | `scripts/run_baseline.sh --seed {0,1,2} --config configs/base.yaml` @ `a1b2c3d` | `/srv/runs/2026-01-15-baseline/{metrics.json,run.log}` | 2026-01-15 |
| "B's wall time is 2.1x" | `scripts/bench.py --profile --repeat 5` @ `d4e5f6a` | `/srv/runs/2026-01-20-bench-b/` | 2026-01-20 |
-->

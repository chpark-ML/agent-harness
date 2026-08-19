# `harness-check-claims` — every number in a document must be traceable

Reads a results document and an artifact map, and reports every numeric claim in
the document that appears nowhere in the map.

```bash
harness-check-claims deck.md                      # finds ARTIFACTS.md nearby
harness-check-claims paper/main.tex docs/ARTIFACTS.md
```

It ships in `harness-core/bin/`. Claude Code puts that directory on the **Bash
tool's** `PATH`, so a session can run it directly, and `install.sh` writes a
shim into `~/.local/bin` so your own terminal can too.

## Why it exists

The research module already states the invariant — *a number that cannot be
traced through `ARTIFACTS.md` to the run that produced it is not yet a result*.
A results deck and a manuscript are the two moments that invariant stops being a
convention and becomes a claim someone acts on. This checks it mechanically
instead of asking the model to be careful.

## What it reads

The format comes from the extension: `.tex` and `.ltx` are LaTeX, anything else
is Markdown. The two need different *this is never a claim* rules and guessing
from content would misread a file that has both.

| Never a claim, in both | Markdown only | LaTeX only |
|---|---|---|
| four-digit years, ISO dates | HTML comments | `%` comments, but **not** `\%` |
| version tokens (`v1.2.3`) | `](link)` targets | `\cite` / `\ref` / `\label` keys |
| digits inside identifiers (`ADR-0008`) | `` `inline code` `` | package and class options |
| `§7`, `§4b` | list and heading numbers | inline math `$…$` |
| a line marked no-claim | `<!-- no-claim -->` | `% no-claim` |

**Two LaTeX rules were decided by measurement, not by reasoning.** On a real
574-line manuscript, 333 of its 376 prose numeric tokens sat inside `$…$` and
were subscripts, indices and thresholds — so **inline math is notation, not
results**, and it is skipped. And 493 tokens sat inside 12 table and figure
blocks; requiring every cell to appear in the artifact map is a demand nobody
meets, so **those blocks are skipped and counted**, and the run says how many it
did not look at. What they need instead is
[`harness-check-provenance`](harness-check-provenance.md).

Keeping math produced 519 findings on that one paper. Skipping it produced 34
claims and 5 findings.

## Exit codes

| | |
|---|---|
| `0` | every number found in the artifact map |
| `1` | at least one was not |
| `2` | operational — no document, or no artifact map |

`2` is separate on purpose: *the check could not run* and *the check found
something* are different answers, and a caller that conflates them reports a
missing file as a clean document.

## What it is deliberately bad at

It asks whether the digits appear in the artifact map, not whether they were
used correctly. **A number copied into the wrong sentence still passes.** It
catches the failure that actually happens — a figure that exists nowhere but the
document.

Display math (`\[…\]`, `equation`) is not parsed; only inline `$…$` is skipped.
A word followed by a bare version (`bash 3.2`) is a known miss, measured and left
alone: it is not distinguishable from `hooks 6`, and filtering it would blind the
check to real counts. Mark those lines no-claim.

## Verification

`plugins/harness-core/scripts/verify-harness-check-claims.sh` — 50 cases,
run by `make verify`.

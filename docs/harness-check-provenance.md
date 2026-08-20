# `harness-check-provenance` — every table and figure must name its run

Reads a document and an artifact map, and asks **once per table or figure**:
does this block say which run produced it, and is that run in the map?

```bash
harness-check-provenance paper/main.tex docs/ARTIFACTS.md
harness-check-provenance paper/main.tex docs/ARTIFACTS.md --strict
```

It ships in `harness-core/bin/`, reachable the same way as
[`harness-check-claims`](harness-check-claims.md).

## Why it is a separate command

Its sibling asks whether a *number* appears in the artifact map. That is right
for prose and for a deck quoting a handful of figures, and useless for a table:
measured on a real 574-line manuscript, **493 of its numeric tokens sat inside 12
table and figure blocks**, and transcribing every cell into `ARTIFACTS.md` is a
demand nobody meets. So that checker skips those blocks and counts them, and this
one asks a different question about them — one per block instead of one per cell,
which is ten findings per manuscript rather than five hundred.

The two **partition the document**: the blocks one skips are exactly the blocks
the other counts, and a case in each verifier pins it. No number is both skipped
by one and ignored by the other.

## The marker

A block names its run in a comment, so it is native to the format and invisible
in the built output — no macro to define, no package to load.

```
% source: make eval-main                     LaTeX
<!-- source: make eval-main -->              Markdown
```

It goes on the line above the block or anywhere inside it, and a trailing
comment on a content line counts — `\includegraphics{f.pdf} % source: make fig`
is a marker. Its text must appear somewhere in the artifact map; the comparison
is a substring, the same deliberately dumb matching its sibling uses.

**The comment opener has to sit immediately before `source:`**, with nothing but
whitespace between. Recognising the word anywhere on the line was the first
version, and the first real figure it was pointed at broke it: the LaTeX comment

```
% A module is a trapezoid, as in the source: encoder widens
```

is ordinary English, and it displaced a correct marker sitting on the line above
the block — so a right figure was reported as claiming a run nobody recorded.
That is the false-positive failure mode [ADR-0003](adr/0003-verification-mandate.md)
names as the way a check earns being switched off, and four cases in
`verify-harness-check-provenance.sh` hold the anchor in place. If you need the
word in prose, any wording that does not put a `%` or `<!--` directly in front
of it is fine.

Blocks recognised: `table`, `tabular`, `figure`, `tikzpicture`, `axis` in LaTeX
— outermost only, so a `tabular` inside a `table` is one block, not two — and a
pipe table or an `![alt](path)` image in Markdown.

## Exit codes, and why two findings are not one

| | |
|---|---|
| `0` | every marker resolved. **Unmarked blocks are reported, not failed** |
| `1` | a marker names something absent from the artifact map |
| `1` | …or, with `--strict`, any unmarked block |
| `2` | operational — no document, or no artifact map |

**A block claiming provenance it does not have is worse than one claiming
none**, so those are the failure. An unmarked block is the normal starting state
of every document written before the convention existed — measured on four real
manuscripts carrying 12, 5, 5 and 5 blocks and not one marker between them. A
check that fails 100% on first contact is a check somebody switches off, and
[agent-layer.md §4](agent-layer.md) already names that as how a false-positive
check becomes worth zero.

`--strict` demands full coverage once a document has been marked up, the way
`context-budget.sh`'s `--require-plugins` turns a partial measurement into a
gate.

## What it does not check

Only *registration*. The cells are never compared to the run's output — whether
the numbers in the table match what the script produced is a different job, and
this does not do it.

## Verification

`plugins/harness-core/scripts/verify-harness-check-provenance.sh` — 22 cases,
run by `make verify`. Most of them are boundary work, because the failure to
avoid is calling a correct block wrong: nesting, where the marker may sit, and
whether one block's marker can leak into the next.

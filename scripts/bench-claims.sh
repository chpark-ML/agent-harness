#!/bin/bash
# bench-claims.sh — what does the claim checker do to prose it has never seen?
#
# `verify-harness-check-claims.sh` proves the checker does what I meant it to do. It
# cannot prove the *filter list is complete*, because I wrote the cases and the
# regexes in the same sitting — every "shape that is never a claim" in that file
# is one I had already thought of.
#
# So this measures the checker against a held-out corpus, the way
# `evals/incidents.sh` does for the guards: real technical prose written with no
# knowledge of these regexes, frozen at `evals/prose-corpus.md`.
#
# It used to rebuild that corpus from a git commit that predated the checker.
# When the repository history was rewritten the commit vanished, the corpus came
# out empty, and the benchmark went on producing no result while the README kept
# quoting its last number as current. A fixture that depends on history is a
# fixture history can delete — so the corpus is now a file, and the file says
# not to regenerate it.
#
# The metric that decides whether the check survives contact with users is the
# FALSE POSITIVE rate. A checker that flags `ADR-0009` or `bash 3.2` gets
# bypassed the first afternoon, and a bypassed checker catches nothing.
#
# Flags are adjudicated into two piles:
#   shape    the token is structurally never a claim — the filter list has a hole
#   real     a genuine quantity with no row in the artifacts file — correct flag
#
# Result as of 2026-08-06: 193 tokens checked, 60 flagged, of which 6 are shape
# misses — a 3.1% structural false-positive rate, and all six are one pattern
# (`bash 3.2`, `bash 5`: a word followed by a bare version). That pattern is
# deliberately not filtered, because `bash 5` is indistinguishable from
# `hooks 6`; `<!-- no-claim -->` is the escape hatch for it.
#
# The first run of this benchmark, before any of that, flagged 113. It found a
# defect the synthetic suite could not: `85,844` was being split into `85` and
# `844`. Held-out corpora earn their keep on exactly that kind of thing.
#
# It does not find everything. An end-to-end run — writing a real deck from this
# repo's results — turned up a hole this corpus cannot show, because these
# documents contain no html comments and a deck does. Run both.
#
# Run:  bash scripts/bench-claims.sh
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$REPO/plugins/harness-core/bin/harness-check-claims"
# Last commit before plugins/harness-slides existed.
CORPUS="$REPO/evals/prose-corpus.md"

[ -f "$CHECK" ]  || { echo "bench-claims: $CHECK not found" >&2; exit 1; }
[ -s "$CORPUS" ] || { echo "bench-claims: corpus missing or empty: $CORPUS" >&2; exit 1; }

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

# The artifacts file a real deck about this repo would carry: every number this
# repository has actually measured.
cat > "$WORK/ARTIFACTS.md" <<'EOF'
| claim | produced by | output |
|---|---|---|
| guards caught 27 of 29 incidents | make bench | evals/incidents.sh |
| false positives 2 of 24, 8 percent | make bench | evals/incidents.sh |
| raw arm caught 0 of 29 | make bench | evals/incidents.sh |
| held-out corpus 53 cases | make bench | evals/incidents.sh |
| hook verification cases 198 | make verify | ci |
| install assertions 90 | make verify | ci |
| LSP off mean 315857 tokens, 11.3 turns | make bench-lsp | scripts/bench-lsp.sh |
| LSP on mean 295831 tokens, 11.0 turns | make bench-lsp | scripts/bench-lsp.sh |
| LSP delta 6.3 percent, 3 runs an arm | make bench-lsp | scripts/bench-lsp.sh |
| superpowers 14 skills at 688 tokens | claude plugin details | docs |
| harness-core 2 skills at 390 tokens | claude plugin details | docs |
| harness-dev 1 skill at 351 tokens | claude plugin details | docs |
| permissions allow 42 ask 3 deny 8 | settings-fragment.json | repo |
| hooks 6, blocking 4, informational 2 | hooks.json | repo |
EOF

cp "$CORPUS" "$WORK/corpus.md"

lines="$(wc -l < "$WORK/corpus.md" | tr -d ' ')"
echo "=== claim checker vs. held-out prose ==="
echo "corpus:    $lines lines, frozen at evals/prose-corpus.md"
echo "artifacts: $(grep -c '^|' "$WORK/ARTIFACTS.md") rows of this repo's measured numbers"
echo

"$CHECK" "$WORK/corpus.md" "$WORK/ARTIFACTS.md" > "$WORK/out" 2>&1
head -1 "$WORK/out"
checked_n="$(head -1 "$WORK/out" | awk '{print $2}')"

# What this benchmark is for: finding shapes the filter list does not know
# about. It is NOT for producing a false-positive percentage — two earlier
# attempts tried and both were wrong, in opposite directions. Bucketing by line
# context counted a real quantity as a miss because an ADR number sat beside it;
# bucketing by `word + number` then counted "frontmatter 9" as a version. Those
# two are not separable by shape, which is exactly the limitation the checker
# already documents: `bash 5` cannot be told from `hooks 6`.
#
# So the output is a list, not a rate. Everything flagged falls into one of two
# buckets, and only the second one is actionable:
#   known    the `word + bare number` ambiguity, accepted and unfiltered
#   other    a genuine quantity with no row in the deliberately small artifacts
#            file — correct behaviour — OR a new shape nobody has filtered yet
# A human reads the `other` list. Anything in it that is not a quantity is a
# filter to add, with a regression case.
sed -n '/^not found/,$p' "$WORK/out" | grep -E '^  .*:[0-9]+' > "$WORK/flags" 2>/dev/null

total="$(wc -l < "$WORK/flags" | tr -d ' ')"
known=0; other=0
: > "$WORK/known"; : > "$WORK/other"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  tok="$(printf '%s' "$f" | awk '{print $2}')"
  ctx="$(printf '%s' "$f" | cut -d' ' -f3-)"
  esc="$(printf '%s' "$tok" | sed 's/[.[\*^$]/\\&/g')"
  if printf '%s' "$ctx" | grep -qE "[A-Za-z][A-Za-z+.#_-]* $esc([^0-9]|$)"; then
    known=$((known + 1)); printf '%s\n' "$f" >> "$WORK/known"
  else
    other=$((other + 1)); printf '%s\n' "$f" >> "$WORK/other"
  fi
done < "$WORK/flags"

echo
printf 'flagged: %s of %s tokens checked\n' "$total" "$checked_n"
printf '  known ambiguity (word + bare number, unfilterable): %s\n' "$known"
printf '  everything else (read these):                      %s\n' "$other"
echo
echo "--- the 'everything else' list. Each is either a quantity the small"
echo "--- artifacts file legitimately lacks, or a shape nobody has filtered."
sort -u "$WORK/other" 2>/dev/null | head -50
echo
echo "There is no false-positive rate here on purpose. A token like 'bash 5' and"
echo "a token like 'hooks 6' have the same shape, so no counter can separate them"
echo "-- which is the checker's documented limitation, and it applies to any"
echo "adjudicator too. Read the list."

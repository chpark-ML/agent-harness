#!/bin/bash
# bench-claims.sh — what does the claim checker do to prose it has never seen?
#
# `verify-check-claims.sh` proves the checker does what I meant it to do. It
# cannot prove the *filter list is complete*, because I wrote the cases and the
# regexes in the same sitting — every "shape that is never a claim" in that file
# is one I had already thought of.
#
# So this measures the checker against a held-out corpus, the way
# `evals/incidents.sh` does for the guards: real documentation from this
# repository, taken from a commit that predates the checker's existence. Nobody
# was avoiding its regexes when they wrote it.
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
CHECK="$REPO/plugins/harness-slides/scripts/check-claims.sh"
# Last commit before plugins/harness-slides existed.
BASE="${BASE:-5ee8e84}"
DOCS="README.md docs/agent-layer.md docs/adr/0005-installer.md docs/hooks/secret-scrubber.md"

command -v git >/dev/null 2>&1 || { echo "bench-claims: git required" >&2; exit 1; }
[ -f "$CHECK" ] || { echo "bench-claims: $CHECK not found" >&2; exit 1; }

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

n_docs=0
for f in $DOCS; do
  if git -C "$REPO" show "$BASE:$f" >> "$WORK/corpus.md" 2>/dev/null; then
    printf '\n' >> "$WORK/corpus.md"; n_docs=$((n_docs + 1))
  else
    echo "  ! $f not present at $BASE — skipped" >&2
  fi
done
[ "$n_docs" -gt 0 ] || { echo "bench-claims: no corpus (is $BASE reachable?)" >&2; exit 1; }

lines="$(wc -l < "$WORK/corpus.md" | tr -d ' ')"
echo "=== claim checker vs. held-out prose ==="
echo "corpus:    $n_docs documents, $lines lines, from $BASE (predates the checker)"
echo "artifacts: $(grep -c '^|' "$WORK/ARTIFACTS.md") rows of this repo's measured numbers"
echo

"$CHECK" "$WORK/corpus.md" "$WORK/ARTIFACTS.md" > "$WORK/out" 2>&1
head -1 "$WORK/out"

# Adjudication. A token is a "shape" miss when the line's own context shows it
# was never a quantity: a cross-reference, an identifier, an exit code, a
# requirement version. Everything else is a real untraceable quantity.
sed -n '/^not found/,$p' "$WORK/out" | grep -E '^  .*:[0-9]+' > "$WORK/flags" 2>/dev/null

total="$(wc -l < "$WORK/flags" | tr -d ' ')"
shape=0; real=0
: > "$WORK/shapes"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  ctx="$(printf '%s' "$f" | cut -d' ' -f3-)"
  case "$ctx" in
    *"ADR-0"*|*"§"*|*"exit "*|*"bash 3.2"*|*"Phase "*|*"phase "*|*"[^"*)
      shape=$((shape + 1)); printf '%s\n' "$f" >> "$WORK/shapes" ;;
    *) real=$((real + 1)) ;;
  esac
done < "$WORK/flags"

echo
printf 'flagged tokens: %s\n' "$total"
printf '  shape misses (filter list has a hole): %s\n' "$shape"
printf '  real untraceable quantities:           %s\n' "$real"
echo
echo "shape misses in full — each is a filter to add or a decision not to:"
sort -u "$WORK/shapes" 2>/dev/null | head -40
echo
echo "Adjudication is heuristic — read the flags before trusting the split. Note"
echo "that a 'real' flag here is correct behaviour: the artifacts file above is"
echo "deliberately small, so most quantities in the corpus legitimately lack a row."
echo "The number that matters is the shape count."

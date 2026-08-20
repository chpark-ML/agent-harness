#!/bin/bash
# verify-harness-check-provenance — cases for harness-check-provenance.
#
# The failure this script has to avoid is calling a correct block wrong: a
# provenance check that reports blocks which *are* marked gets switched off, and
# a switched-off check is zero. So most of what is below is boundary work —
# nesting, where the marker may sit, and whether one block's marker can leak
# into the next.
#
# Requires bash 3.2.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/../bin/harness-check-provenance"
BASH_BIN="${BASH:-bash}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0; FAILED=""
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); FAILED="$FAILED$1
"; printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

cat > "$WORK/ARTIFACTS.md" <<'EOF'
| claim | produced by | output | date |
|---|---|---|---|
| main table | make eval-main | results/main.csv | 2026-08-18 |
| ablation | make eval-ablation | results/abl.csv | 2026-08-18 |
EOF

# case <name> <expected_exit> <extension> <body> [extra flag]
case_() {
  local name="$1" want="$2" ext="$3" body="$4" flag="${5:-}"
  printf '%s\n' "$body" > "$WORK/doc.$ext"
  if [ -n "$flag" ]; then
    "$BASH_BIN" "$CHECK" "$WORK/doc.$ext" "$WORK/ARTIFACTS.md" "$flag" >"$WORK/out" 2>&1
  else
    "$BASH_BIN" "$CHECK" "$WORK/doc.$ext" "$WORK/ARTIFACTS.md" >"$WORK/out" 2>&1
  fi
  local got=$?
  if [ "$got" -eq "$want" ]; then ok "$name"
  else bad "$name" "expected exit $want, got $got — $(head -2 "$WORK/out" | tr '\n' ' ')"; fi
}

# Asserts on the summary line rather than the exit code.
says() {
  local name="$1" pattern="$2" ext="$3" body="$4"
  printf '%s\n' "$body" > "$WORK/doc.$ext"
  "$BASH_BIN" "$CHECK" "$WORK/doc.$ext" "$WORK/ARTIFACTS.md" >"$WORK/out" 2>&1
  if grep -q "$pattern" "$WORK/out"; then ok "$name"
  else bad "$name" "wanted /$pattern/ — $(head -1 "$WORK/out")"; fi
}

echo "=== check-provenance verification ==="
echo

TBL='\begin{table}
\begin{tabular}{l} 1 \\ \end{tabular}
\end{table}'

# --- the three outcomes -------------------------------------------------------
case_ "a marker that resolves → pass" 0 tex "% source: make eval-main
$TBL"
case_ "a marker naming nothing → fail" 1 tex "% source: make eval-nowhere
$TBL"
case_ "no marker → reported, not failed" 0 tex "$TBL"
case_ "no marker under --strict → fail" 1 tex "$TBL" --strict
case_ "a resolving marker under --strict → still pass" 0 tex "% source: make eval-main
$TBL" --strict

# --- where the marker may sit -------------------------------------------------
case_ "marker on the line above the block → found" 0 tex "% source: make eval-main
$TBL"
case_ "marker inside the block → found" 0 tex "\\begin{table}
% source: make eval-main
\\begin{tabular}{l} 1 \\\\ \\end{tabular}
\\end{table}"

# --- prose is not a marker ----------------------------------------------------
# The regression. `*"source:"*` was unanchored, so any comment containing the
# word claimed the block. The line that found it is ordinary English in a LaTeX
# comment — `% A module is a trapezoid, as in the source: encoder widens` — and
# it overwrote a correct marker sitting on the line above the block. The figure
# was right and the checker called it wrong, which §4 names as the way a check
# earns being switched off.
case_ "prose containing the word is not a marker" 0 tex "% as in the source: encoder widens
$TBL"
# Exit code alone cannot tell these apart — unanchored, the prose becomes a
# marker naming nothing, which also exits 1. The summary line is what separates
# "the block has no source" from "the block claims a source that is missing",
# so that is what this asserts.
says "prose leaves the block unsourced, not falsely sourced" "0 traced, 1 unsourced, 0 naming" tex "% as in the source: encoder widens
$TBL"
says "prose does not displace a real marker above the block" "1 traced, 0 unsourced" tex "% source: make eval-main
% as in the source: encoder widens
$TBL"
says "markdown prose outside a comment is not a marker" "0 traced, 1 unsourced, 0 naming" md "See the source: notes.md for details

| a | b |
|---|---|
| 1 | 2 |"

# The other direction, and the reason the anchor is "comment opener adjacent"
# rather than "line starts with the comment opener": a trailing comment is
# ordinary LaTeX style and must keep working.
# Exit 0 is what an unsourced block gives too, so this asserts the summary.
says "a trailing comment on a content line is a marker" "1 traced, 0 unsourced" tex "\\begin{figure}
\\includegraphics{f.pdf} % source: make eval-main
\\end{figure}"

# --- the writer and the reader are pinned to each other -----------------------
# F2 of docs/superpowers/plans/2026-08-20-paper-figures.md: the marker a figure
# skill emits must be the marker this checker accepts, by construction rather
# than because the same person wrote both on the same afternoon.
#
# The checker already prints the form it wants, in its own "no source" hint. So
# take that printed string, put it in a document, and require it to resolve. If
# anyone changes the accepted syntax, the hint and this case disagree and the
# suite says so — no second copy of the template to keep in step.
printf '%s\n' "$TBL" > "$WORK/doc.tex"
"$BASH_BIN" "$CHECK" "$WORK/doc.tex" "$WORK/ARTIFACTS.md" >"$WORK/out" 2>&1
HINT="$(sed -n 's/^  \(%[[:space:]]*source:.*\)$/\1/p' "$WORK/out" | head -1)"
if [ -n "$HINT" ]; then
  ok "the checker prints a LaTeX marker template in its hint"
  printf '%s\n%s\n' "$HINT" "$TBL" > "$WORK/doc.tex"
  "$BASH_BIN" "$CHECK" "$WORK/doc.tex" "$WORK/ARTIFACTS.md" --strict >/dev/null 2>&1
  [ $? -eq 0 ] && ok "the template it prints is a template it accepts" \
                || bad "the template it prints is a template it accepts" "hint was: $HINT"
else
  bad "the checker prints a LaTeX marker template in its hint" "no '  % source: ...' line in the hint"
  bad "the template it prints is a template it accepts" "no template to test"
fi

# --- boundaries that decide whether this is usable ----------------------------
says "a tabular nested in a table is ONE block" "^1 table/figure blocks" tex "$TBL"
says "two blocks are counted as two" "^2 table/figure blocks" tex "$TBL

$TBL"
# The leak: if the pending marker is not cleared when a block consumes it, the
# next unmarked block inherits it and passes while claiming nothing.
says "one block's marker does not leak into the next" "1 traced, 1 unsourced" tex "% source: make eval-main
$TBL

$TBL"
says "figure is a block" "^1 table/figure blocks" tex "\\begin{figure}
\\includegraphics{f.pdf}
\\end{figure}"
says "tikzpicture is a block" "^1 table/figure blocks" tex "\\begin{tikzpicture}
\\draw (0,0);
\\end{tikzpicture}"
says "prose with no blocks at all → zero" "^0 table/figure blocks" tex "Just a sentence with 12.5 in it."
says "an unterminated environment still counts" "^1 table/figure blocks" tex "\\begin{table}
\\begin{tabular}{l} 1 \\\\ \\end{tabular}"

says "the summary names all three categories, so the counts add up" "traced.*unsourced.*naming a run" tex "% source: make eval-main
$TBL

% source: make eval-nowhere
$TBL

$TBL"

# --- markdown -----------------------------------------------------------------
says "a markdown pipe table is a block" "^1 table/figure blocks" md "| a | b |
|---|---|
| 1 | 2 |"
case_ "a markdown marker resolves, comment close stripped" 0 md "<!-- source: make eval-main -->
| a | b |
|---|---|
| 1 | 2 |"
says "a markdown image is a block" "^1 table/figure blocks" md "![fig](f.png)"

# --- operational failures are distinguishable from findings -------------------
"$BASH_BIN" "$CHECK" "$WORK/nope.tex" "$WORK/ARTIFACTS.md" >/dev/null 2>&1
[ $? -eq 2 ] && ok "a missing document exits 2, not 1" || bad "a missing document exits 2, not 1"
printf '%s\n' "$TBL" > "$WORK/doc.tex"
( cd /tmp && "$BASH_BIN" "$CHECK" "$WORK/../nonexistent-xyz/d.tex" ) >/dev/null 2>&1
[ $? -eq 2 ] && ok "no artifacts file anywhere exits 2" || bad "no artifacts file anywhere exits 2"
"$BASH_BIN" "$CHECK" "$WORK/doc.tex" "$WORK/ARTIFACTS.md" --bogus >/dev/null 2>&1
[ $? -eq 2 ] && ok "an unknown flag exits 2" || bad "an unknown flag exits 2"

# --- the two checks partition the document ------------------------------------
# check-claims skips exactly the blocks this one covers. If the two ever
# disagree, a number is either counted twice or by neither.
CLAIMS="$HERE/../bin/harness-check-claims"
printf '%s\n' "\\begin{document}
Prose says 12.5 here.
$TBL

$TBL
\\end{document}" > "$WORK/doc.tex"
skipped="$("$BASH_BIN" "$CLAIMS" "$WORK/doc.tex" "$WORK/ARTIFACTS.md" 2>&1 | grep -oE 'skipped [0-9]+' | grep -oE '[0-9]+')"
found="$("$BASH_BIN" "$CHECK" "$WORK/doc.tex" "$WORK/ARTIFACTS.md" 2>&1 | head -1 | grep -oE '^[0-9]+')"
if [ "${skipped:-x}" = "${found:-y}" ]; then ok "check-claims skips exactly the blocks this covers ($found)"
else bad "check-claims skips exactly the blocks this covers" "claims skipped ${skipped:-?}, provenance found ${found:-?}"; fi

total=$((PASS + FAIL))
echo
echo "=== Summary ==="
echo "  $PASS / $total passed"
if [ "$FAIL" -gt 0 ]; then
  printf '%s' "$FAILED" | while IFS= read -r n; do [ -n "$n" ] && echo "    - $n"; done
  exit 1
fi
exit 0

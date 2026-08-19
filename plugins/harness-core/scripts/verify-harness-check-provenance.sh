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

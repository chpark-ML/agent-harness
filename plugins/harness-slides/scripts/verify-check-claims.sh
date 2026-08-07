#!/bin/bash
# verify-check-claims.sh — behavioural verification of the claim traceability check.
#
# The check turns a convention ("a number that cannot be traced is not a
# result") into something a machine enforces, so it earns the same treatment as
# a hook: cases for what it catches, what it must let through, and the boundary
# between them. The let-through cases matter more — a checker that flags slide
# numbers and years gets bypassed within a day.
#
# Run:  bash plugins/harness-slides/scripts/verify-check-claims.sh

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-claims.sh"
BASH_BIN="${BASH:-bash}"
[ -f "$CHECK" ] || { echo "verify-check-claims: $CHECK not found" >&2; exit 1; }

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0; FAILED=""
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); FAILED="$FAILED$1
"; printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

cat > "$WORK/ARTIFACTS.md" <<'EOF'
| claim | produced by | output | date |
|---|---|---|---|
| guards stop 27 of 29 incidents | make bench | evals/results/ | 2026-08-06 |
| false positive rate 8% | make bench | evals/results/ | 2026-08-06 |
| hook cases 198 | make verify | ci | 2026-08-06 |
| mean latency 12.5 ms | bench/latency.sh | out/latency.json | 2026-08-06 |
| tokens per session 85,844 | make bench-lsp | out/lsp.json | 2026-08-06 |
EOF

# case <name> <expected_exit> <deck body>
case_() {
  local name="$1" want="$2" body="$3"
  printf '%s\n' "$body" > "$WORK/deck.md"
  "$BASH_BIN" "$CHECK" "$WORK/deck.md" "$WORK/ARTIFACTS.md" >"$WORK/out" 2>&1
  local got=$?
  if [ "$got" -eq "$want" ]; then ok "$name"
  else bad "$name" "expected exit $want, got $got — $(head -3 "$WORK/out" | tr '\n' ' ')"; fi
}

echo "=== check-claims verification ==="
echo

# --- traceable numbers pass ---------------------------------------------------
case_ "a number present in the artifacts file → pass" 0 "- Stops 27 of 29 incidents"
case_ "a percentage present in the artifacts file → pass" 0 "- False positives: 8%"
case_ "a decimal present in the artifacts file → pass" 0 "- Mean latency 12.5 ms"
case_ "prose with no numbers at all → pass" 0 "- The guards run before the tool call."
case_ "several traceable numbers on one line → pass" 0 "- 27 of 29 caught, 8% false positives"

# --- fabricated numbers are caught --------------------------------------------
case_ "a number that appears nowhere → fail" 1 "- Improved latency by 42%"
case_ "a plausible-looking near-miss → fail" 1 "- Stops 28 of 29 incidents"
case_ "one bad number among good ones → fail" 1 "- 27 of 29 caught, and throughput rose 3.7x"

# --- regressions from the held-out corpus (scripts/bench-claims.sh) ---
# Each of these got flagged on real prose the synthetic cases above did not model.
case_ "a thousands separator is one number, not two → pass" 0 "- 85,844 tokens per session"
case_ "the same number written without the comma → pass" 0 "- 85844 tokens per session"
case_ "a fabricated number with a comma is still caught → fail" 1 "- 91,203 tokens per session"
case_ "an ADR cross-reference → pass" 0 "- Split rationale is in ADR-0008"
case_ "a CVE identifier → pass" 0 "- Fixes CVE-2024-1234 in the parser"
case_ "a section reference → pass" 0 "- Measurement caveats: see §4b"
case_ "a number inside a markdown link target → pass" 0 "- See [the split rationale](adr/0008-split.md)"
case_ "a number inside inline code → pass" 0 "- Run it with \`--runs 5\` to repeat"
case_ "a real claim beside an ignored shape is still caught → fail" 1 "- See [ADR](adr/0008-split.md): 3.7x faster"
case_ "numbers inside an html comment → pass" 0 "<!-- slides 1 and 6 carry no quantity -->"
case_ "an unterminated html comment → pass" 0 "<!-- todo: chase the 3.7x figure"
case_ "a real claim before a comment is still caught → fail" 1 "- Throughput rose 3.7x <!-- check this -->"

# --- shapes that are never claims ---------------------------------------------
# A checker that flags these is a checker people route around.
case_ "a four-digit year → pass" 0 "# Results 2026"
case_ "an ISO date → pass" 0 "- Measured 2026-08-06 on CI"
case_ "a semantic version → pass" 0 "- Ships in v1.4.7"
case_ "a numbered heading → pass" 0 "## 3. Throughput"
case_ "a numbered list item → pass" 0 "4. Re-run the benchmark"
case_ "a slide reference → pass" 0 "- See slide 12 for the raw output"
case_ "an explicit no-claim marker → pass" 0 "- Roughly 40% faster <!-- no-claim -->"

# --- multi-line html comments (found by the frozen prose corpus) ---
printf '%s\n' '<!-- notes:' '  throughput was 3.7x in the draft' '  and 91% in the older one' '-->' '- Stops 27 of 29 incidents' > "$WORK/deck.md"
"$BASH_BIN" "$CHECK" "$WORK/deck.md" "$WORK/ARTIFACTS.md" >/dev/null 2>&1
[ $? -eq 0 ] && ok "numbers inside a multi-line comment → pass" || bad "numbers inside a multi-line comment → pass"
printf '%s\n' '<!-- notes:' '  ignore 3.7x' '-->' '- Throughput rose 4.9x' > "$WORK/deck.md"
"$BASH_BIN" "$CHECK" "$WORK/deck.md" "$WORK/ARTIFACTS.md" >/dev/null 2>&1
[ $? -eq 1 ] && ok "a claim after a multi-line comment is still caught" || bad "a claim after a multi-line comment is still caught"
printf '%s\n' '- Throughput rose 4.9x <!-- start' '  spillover 3.7x' '-->' > "$WORK/deck.md"
"$BASH_BIN" "$CHECK" "$WORK/deck.md" "$WORK/ARTIFACTS.md" >/dev/null 2>&1
[ $? -eq 1 ] && ok "a claim before an opener is still caught" || bad "a claim before an opener is still caught"

# --- the report has to be actionable ------------------------------------------
printf '%s\n' '- Improved latency by 42%' > "$WORK/deck.md"
"$BASH_BIN" "$CHECK" "$WORK/deck.md" "$WORK/ARTIFACTS.md" >"$WORK/out" 2>&1
grep -q '42' "$WORK/out" && ok "the report names the offending number" || bad "the report names the offending number"
grep -q 'no-claim' "$WORK/out" && ok "the report states both ways out" || bad "the report states both ways out"
grep -q 'deck.md:1' "$WORK/out" && ok "the report gives file:line" || bad "the report gives file:line"

# --- operational failures are distinguishable from findings -------------------
"$BASH_BIN" "$CHECK" "$WORK/nope.md" "$WORK/ARTIFACTS.md" >/dev/null 2>&1
[ $? -eq 2 ] && ok "a missing deck exits 2, not 1" || bad "a missing deck exits 2, not 1"
printf '%s\n' '- 27 of 29' > "$WORK/deck.md"
( cd "$WORK" && "$BASH_BIN" "$CHECK" deck.md ) >/dev/null 2>&1
[ $? -eq 0 ] && ok "the artifacts file is found next to the deck" || bad "the artifacts file is found next to the deck"
( cd /tmp && "$BASH_BIN" "$CHECK" "$WORK/../nonexistent-dir-xyz/d.md" ) >/dev/null 2>&1
[ $? -eq 2 ] && ok "no artifacts file anywhere exits 2" || bad "no artifacts file anywhere exits 2"

total=$((PASS + FAIL))
echo
echo "=== Summary ==="
echo "  $PASS / $total passed"
if [ "$FAIL" -gt 0 ]; then
  printf '%s' "$FAILED" | while IFS= read -r n; do [ -n "$n" ] && echo "    - $n"; done
  exit 1
fi
exit 0

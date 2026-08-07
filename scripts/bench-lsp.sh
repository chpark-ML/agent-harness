#!/bin/bash
# bench-lsp.sh — does the Python language server change what the agent produces?
#
# The first version of this benchmark asked a read-only comprehension question
# and found nothing, which was a design error rather than a result: the
# documented mechanism is "Claude sees errors and warnings immediately **after
# each edit**", and a task forbidden from editing cannot trigger it. The server
# does start — `pyright-langserver --stdio` appears in the process table during
# an edit task and never during a read-only one.
#
# So this measures an edit. The fixture is type-clean (pyright: 0 errors) and the
# task asks for an addition whose obvious implementation is not: load_config
# returns Optional[Config] and describe takes Config, so writing the three
# natural lines introduces exactly one type error. Whether that error survives
# is the signal.
#
#   off  pyright-lsp disabled
#   on   pyright-lsp enabled
#
# Primary metric is correctness — pyright errors in the result, graded by a
# checker the agent is not being told to run. Tokens and turns come along
# because the interesting failure mode is buying correctness with a lot of them.
#
# COSTS REAL MONEY — each run is a full agent session. Default 3 runs per arm.
#
# Run:  bash scripts/bench-lsp.sh [runs]
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RUNS="${1:-3}"
PLUG_LSP="pyright-lsp@claude-plugins-official"
PLUG_PY="harness-python@agent-harness"

. "$(cd "$(dirname "$0")" && pwd)/_bench-lib.sh"
BENCH_NAME="bench-lsp ($RUNS runs an arm)"
for a in "$@"; do [ "$a" = --yes ] && BENCH_YES=1; done
bench_need jq "brew install jq"
bench_need claude "install Claude Code"
bench_need pyright "npm install -g pyright"
bench_need_plugin "pyright-lsp@claude-plugins-official"
bench_confirm \
  "Cost: $((RUNS * 2)) full agent sessions. Real money." \
  "Toggles pyright-lsp and harness-python off and on, and restores them on exit."

WORK="$(mktemp -d)" || exit 1
restore() {
  claude plugin enable "$PLUG_LSP" >/dev/null 2>&1
  claude plugin enable "$PLUG_PY"  >/dev/null 2>&1
  rm -rf "$WORK"
}
trap restore EXIT

PROMPT='Add a function `endpoint_summary(path=None) -> str` to app/report.py. It should load the configuration and return a human-readable description of it. Keep it short.'

arm() {
  local label="$1" n=0 tot=0 turns=0 errs=0 clean=0
  echo "  arm: $label"
  while [ "$n" -lt "$RUNS" ]; do
    n=$((n + 1))
    local fx="$WORK/$label-$n"
    bash "$REPO/evals/fixture-python.sh" "$fx"
    out="$(cd "$fx" && printf '%s' "$PROMPT" \
      | claude -p $BENCH_CLAUDE_ARGS --output-format json --permission-mode acceptEdits 2>/dev/null)"
    printf '%s' "$out" | jq -e '.usage' >/dev/null 2>&1 || { echo "    run $n: no usage — skipped"; continue; }
    local t tn e
    t="$(printf '%s' "$out" | jq '[.usage.input_tokens, .usage.cache_creation_input_tokens,
                                   .usage.cache_read_input_tokens, .usage.output_tokens] | add')"
    tn="$(printf '%s' "$out" | jq '.num_turns')"
    e="$(cd "$fx" && pyright --outputjson 2>/dev/null | jq '.summary.errorCount // 999')"
    grep -q 'endpoint_summary' "$fx/app/report.py" 2>/dev/null || e=999
    tot=$((tot + t)); turns=$((turns + tn)); errs=$((errs + e))
    [ "$e" -eq 0 ] && clean=$((clean + 1))
    printf '    run %d: %8d tokens  %2d turns  pyright errors: %s\n' "$n" "$t" "$tn" \
      "$([ "$e" -eq 999 ] && echo 'n/a (function not added)' || echo "$e")"
  done
  [ "$n" -eq 0 ] && return
  printf '    mean:   %8d tokens  %4.1f turns  type-clean: %d/%d\n' \
    $((tot / n)) "$(awk -v a="$turns" -v b="$n" 'BEGIN{print a/b}')" "$clean" "$n"
  eval "TOK_${label}=$((tot / n)); CLEAN_${label}=$clean; N_${label}=$n"
}

echo "=== LSP benchmark — edit task, correctness graded by pyright ==="
echo "fixture: 6 files, type-clean baseline (pyright: 0 errors)"
echo "runs per arm: $RUNS"
echo

claude plugin disable "$PLUG_PY"  >/dev/null 2>&1
claude plugin disable "$PLUG_LSP" >/dev/null 2>&1
claude plugin list 2>/dev/null | grep -A3 'pyright-lsp' | grep -q 'enabled' \
  && { echo "  ! pyright-lsp still enabled — arms not separated. Aborting." >&2; exit 1; }
arm off

claude plugin enable "$PLUG_LSP" >/dev/null 2>&1
claude plugin enable "$PLUG_PY"  >/dev/null 2>&1
arm on

echo
echo "type-clean results:  off ${CLEAN_off:-?}/${N_off:-?}   on ${CLEAN_on:-?}/${N_on:-?}"
if [ -n "${TOK_off:-}" ] && [ -n "${TOK_on:-}" ] && [ "${TOK_off}" -gt 0 ]; then
  awk -v a="$TOK_off" -v b="$TOK_on" 'BEGIN{printf "tokens:              %+.1f%% with the LSP on\n", 100.0*(b-a)/a}'
fi
echo
echo "$RUNS runs an arm on one task. A one-run difference in type-clean count is"
echo "not a result; treat this as a direction to investigate, not a conclusion."

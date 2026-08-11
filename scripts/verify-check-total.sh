#!/bin/bash
# verify-check-total.sh — the published check count has to be the real one.
#
# The total lives in three places: the README badge, the README table, and the
# §4 sentence in docs/agent-layer.md. Every time a check was added, all three
# were edited by hand. That happened four times, and .claude/harness-gaps.md
# records each one; the fourth is what promoted the entry from a proposal to
# an overdue job. Nothing failed when a number drifted, which is the whole
# problem — a wrong badge is exactly the untraceable figure this repo blocks
# in slides.
#
# Two questions, in order:
#   1. do the three published numbers agree with each other?
#   2. does that number match what the suite actually produced?
#
# The second needs the suite's output, so this reads a transcript rather than
# running anything. `make verify` writes one; CI passes it in.
#
# Counting rule, stated so it can be argued with:
#   + every "N / M passed" and "N / M files clean" summary
#   - except "N / M verifiers passed", which is a rollup of the hook verifiers
#     already counted individually
#   + one per "✔ Validation passed" from the plugin manifests
#   + one for the context-budget ceiling, which passes silently
#
# Run:  make verify | bash scripts/verify-check-total.sh /dev/stdin
#       bash scripts/verify-check-total.sh <transcript>

set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${1:-}"

if [ -z "$LOG" ] || [ ! -r "$LOG" ]; then
  echo "verify-check-total: needs a verify transcript" >&2
  echo "  make verify > /tmp/v.txt 2>&1; bash scripts/verify-check-total.sh /tmp/v.txt" >&2
  exit 2
fi

# ---- 1. what the documents claim -------------------------------------------
badge="$(grep -oE 'badge/checks-[0-9]+' "$REPO/README.md" | head -1 | grep -oE '[0-9]+')"
table="$(grep -E '^\| \*\*(Total|합계)\*\* \|' "$REPO/README.md" | grep -oE '[0-9]+' | tail -1)"
sot="$(grep -oE '(합계|total of) [0-9]+' "$REPO/docs/agent-layer.md" | head -1 | grep -oE '[0-9]+')"

echo "=== published check total ==="
printf '  %-34s %s\n' "README badge" "${badge:-<none>}"
printf '  %-34s %s\n' "README 검증 표 합계" "${table:-<none>}"
printf '  %-34s %s\n' "agent-layer §4" "${sot:-<none>}"

fail=0
if [ -z "$badge" ] || [ -z "$table" ] || [ -z "$sot" ]; then
  echo "  FAIL  a published total could not be read — did a document change shape?"
  fail=1
elif [ "$badge" != "$table" ] || [ "$badge" != "$sot" ]; then
  echo "  FAIL  the three do not agree. One was edited and the others were not."
  fail=1
else
  echo "  ok    all three agree"
fi

# ---- 2. what the suite actually produced ------------------------------------
sum="$(grep -E '^[[:space:]]+[0-9]+ / [0-9]+ (passed|files clean)' "$LOG" \
       | grep -v 'verifiers passed' \
       | awk '{s += $1} END {print s+0}')"
# grep -c prints 0 and exits 1 when nothing matches, so `|| echo 0` appends a
# second zero and the arithmetic below dies. It always prints a number; take it.
manifests="$(grep -c 'Validation passed' "$LOG" 2>/dev/null)"
manifests="${manifests:-0}"
budget=0
grep -q 'ceiling:' "$LOG" && budget=1
actual=$((sum + manifests + budget))

# verify-plugins is additive: without the Claude CLI it skips and prints so.
# The published total counts those manifests, so on a machine without the CLI
# the total is not measurable — say that instead of failing on a number the run
# was never able to produce. CI validates manifests in its own job.
skipped=0
grep -q 'claude CLI not on PATH' "$LOG" && skipped=1

echo
echo "=== what the run produced ==="
printf '  %-34s %s\n' "summaries (rollup excluded)" "$sum"
printf '  %-34s %s\n' "plugin manifests" "$manifests"
printf '  %-34s %s\n' "context-budget ceiling" "$budget"
printf '  %-34s %s\n' "total" "$actual"

if [ "$actual" -eq 0 ]; then
  echo "  FAIL  the transcript held no summaries — wrong file, or verify did not run"
  exit 1
fi

echo
if [ "$skipped" -eq 1 ]; then
  echo "  skip  plugin manifests were not validated here (no claude CLI), so the"
  echo "        run total is $actual and cannot be compared with the published"
  echo "        $badge. The three published numbers were still checked above."
elif [ -n "$badge" ] && [ "$actual" != "$badge" ]; then
  echo "  FAIL  documents say $badge, the run produced $actual."
  echo "        Update the three places, or find out which check disappeared."
  fail=1
elif [ "$fail" -eq 0 ]; then
  echo "  ok    published total matches the run ($actual)"
fi
exit "$fail"

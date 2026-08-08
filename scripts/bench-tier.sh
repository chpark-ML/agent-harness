#!/bin/bash
# bench-tier.sh — is a cheaper model actually cheaper?
#
# docs/agent-layer.md §7 has carried "model and effort orchestration" as a
# candidate on one observation: a session spawned twelve subagents and half did
# work no top-tier model was needed for. That is an observation, not a
# measurement.
#
# The industry figure is 40-60% cost reduction from model tiering, and every
# write-up of it we found reports the saving and omits what happens when the
# cheap tier is wrong. So this measures three things:
#
#   accuracy   graded by exact match against a value computed from this repo
#   cost       total_cost_usd, as the session reports it
#   expected   cost + (1 - accuracy) x opus cost
#
# The third decides. A tier at half the price that is wrong a third of the time
# costs more than the tier it replaced, because the expensive model runs anyway.
#
# Cost, not tokens. A haiku token and an opus token are not the same purchase,
# so comparing token counts across tiers answers a question nobody asked.
#
# Grading holds no judgement and cannot go stale: the answers are derived from
# the repository at run time (§4b — drop to a deterministic layer where one
# exists).
#
# COSTS REAL MONEY. Default 2 runs x 5 tasks x 3 tiers = 30 sessions.
#
# Run:  bash scripts/bench-tier.sh [runs] [--yes]

set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
N="${1:-2}"
case "$N" in ''|*[!0-9]*) N=2 ;; esac
. "$(cd "$(dirname "$0")" && pwd)/_bench-lib.sh"
BENCH_NAME="bench-tier ($N runs x 5 tasks x 3 tiers)"
for a in "$@"; do [ "$a" = --yes ] && BENCH_YES=1; done
bench_need claude "install Claude Code"
bench_need jq "brew install jq"
bench_confirm \
  "Cost: $((N * 5 * 3)) agent sessions across haiku, sonnet and opus." \
  "Read-only: every task is a question about this repository." \
  "Nothing is written anywhere."

TALLY="$(mktemp)" || exit 1
trap 'rm -f "$TALLY"' EXIT INT TERM

# ---- ground truth, computed now ---------------------------------------------
T_HOOKS="$(ls "$REPO"/plugins/harness-core/hooks/*.sh | wc -l | tr -d ' ')"
T_ALLOW="$(jq '.permissions.allow | length' "$REPO/plugins/harness-core/declarative/settings-fragment.json")"
T_ADR="$(ls "$REPO"/docs/adr/*.md | wc -l | tr -d ' ')"

ask() { # tier_model tier_effort label kind expected prompt
  local model="$1" effort="$2" label="$3" kind="$4" want="$5" prompt="$6"
  local out ans cost secs mark
  out="$(cd "$REPO" && env -u CLAUDECODE claude -p "$prompt" \
         --model "$model" --effort "$effort" --output-format json 2>/dev/null)"
  ans="$(printf '%s' "$out" | jq -r '.result // ""' 2>/dev/null)"
  cost="$(bench_json_field "$out" .total_cost_usd)"
  secs="$(bench_json_field "$out" .duration_ms)"
  # Normalisation in python3, not tr: tr threw "Illegal byte sequence" on one
  # Korean answer and the comparison silently fell through to MISS. The first
  # run scored every tier at 90% and two of the three misses were this grader,
  # not the model — one answer was `scripts/verify-doc-refs.sh` where the
  # expected value was the bare filename, which is a correct answer graded wrong.
  if BENCH_GOT="$ans" BENCH_WANT="$want" python3 -c '
import os, re, sys
def norm(s):
    s = s.strip().lower()
    s = re.sub(r"[`\"\u2018\u2019\u201c\u201d]", "", s)
    parts = [p.strip() for p in s.split(",")]
    parts = [os.path.basename(p).rstrip(".") for p in parts if p]
    return ",".join(parts)
sys.exit(0 if norm(os.environ["BENCH_GOT"]) == norm(os.environ["BENCH_WANT"]) else 1)
' 2>/dev/null; then mark="ok  "; else mark="MISS"; fi
  printf '   %s %-14s %-10s want=%-22s got=%s\n' \
    "$mark" "$label" "$kind" "$want" "$(printf '%s' "$ans" | head -c 28 | tr '\n' ' ')"
  printf '%s\t%s\t%s\t%s\n' "$model" "$mark" "$cost" "$secs" >> "$TALLY"
}

run_tier() { # model effort
  local m="$1" e="$2" i
  echo "-- $m / $e"
  i=0; while [ "$i" -lt "$N" ]; do i=$((i + 1))
    ask "$m" "$e" lookup-hooks mechanical "$T_HOOKS" \
      'plugins/harness-core/hooks/ 에 있는 .sh 파일의 개수는? 숫자만 답해라.'
    ask "$m" "$e" lookup-allow mechanical "$T_ALLOW" \
      'plugins/harness-core/declarative/settings-fragment.json 의 permissions.allow 배열 항목 개수는? 숫자만 답해라.'
    ask "$m" "$e" lookup-adr mechanical "$T_ADR" \
      'docs/adr/ 에 있는 .md 파일의 개수는? 숫자만 답해라.'
    ask "$m" "$e" read-selftest multi-file "verify-doc-refs.sh" \
      'scripts/ 아래 검증기 스크립트 중 자기 자신을 시험하는 selftest 모드를 가진 것의 파일명은? 파일명만 답해라.'
    ask "$m" "$e" read-nojq multi-file "check-uncommitted,session-brief" \
      'plugins/harness-core/hooks/ 의 훅 중 jq 존재 여부를 확인하지 않는 것 둘의 이름은? 확장자 없이 알파벳순으로 쉼표로 구분해 답해라.'
  done
  echo
}

echo "=== tier benchmark — $N runs x 5 tasks x 3 tiers ==="
echo "grading: exact match against values computed from this repo at run time"
echo "cost:    total_cost_usd as reported by each session"
echo
run_tier haiku low
run_tier sonnet medium
run_tier opus high

echo "=== result ==="
awk -F'\t' '
  { n[$1]++; c[$1] += $3; d[$1] += $4; if ($2 == "ok  ") h[$1]++ }
  END {
    printf "  %-8s %9s %11s %10s %13s\n", "tier", "accuracy", "mean cost", "mean s", "expected*"
    opus = (n["opus"] ? c["opus"] / n["opus"] : 0)
    split("haiku sonnet opus", order, " ")
    best_acc = -1
    for (i = 1; i <= 3; i++) {
      t = order[i]; if (!n[t]) continue
      acc[t] = h[t] / n[t]; mean[t] = c[t] / n[t]; secs[t] = d[t] / n[t] / 1000
      printf "  %-8s %8.0f%% %10.4f$ %9.1f %12.4f$\n", \
        t, acc[t] * 100, mean[t], secs[t], mean[t] + (1 - acc[t]) * opus
      if (acc[t] > best_acc) { best_acc = acc[t]; best = t }
    }
    print ""
    print "  * expected = mean cost + (1 - accuracy) x opus mean cost —"
    print "    what the tier costs once a wrong answer is re-run on opus."
    print ""
    print "  Read the columns separately, not the last one alone. Accuracy is"
    print "  not assumed to rise with price: the field reports it peaking at an"
    print "  intermediate tier and falling at the most expensive one, so a"
    print "  single summary number would hide exactly the case worth finding."
    if (best != "opus" && n["opus"]) printf "  Here the most accurate tier was %s, not opus.\n", best
  }' "$TALLY"

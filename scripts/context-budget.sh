#!/bin/bash
# context-budget.sh — what the harness costs every session, all of it.
#
# docs/agent-layer.md §4 carried a cost table that counted plugin skills and
# nothing else. The declarative half — CLAUDE.md and rules/, which harnessctl
# installs and which load on every session — was in no table at all. Measured,
# it is 5.8k tok against the 2.2k the doc claimed, and rules/core/workflow.md
# alone (~1.7k) nearly equals every skill we ship. Volume decisions were being
# made against a baseline that was wrong by 3.6x.
#
# The plugin numbers were stale too: the doc said core 390 / dev 351 / slides
# 300 while `claude plugin details` reports 329 / 240 / 446. A hand-maintained
# table drifts; this reads the sources.
#
# Method:
#   declarative  bytes / BYTES_PER_TOK  (estimate — no tokenizer here)
#   plugins      `claude plugin details` Always-on (its own number)
# The estimate is coarse and biased by language mix. It is consistent, which is
# what a budget gate needs; it is not a substitute for the real tokenizer.
#
# Files are globbed, never listed. A hardcoded list is how a new rule file gets
# added and silently costs nothing.
#
# Run:  bash scripts/context-budget.sh [--ceiling N]
#       exit 1 when the worst-case combination exceeds the ceiling

set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD="$REPO/plugins/harness-core/declarative"
BYTES_PER_TOK=4
CEILING=0

while [ $# -gt 0 ]; do
  case "$1" in
    --ceiling) shift; CEILING="${1:-0}" ;;
    --ceiling=*) CEILING="${1#--ceiling=}" ;;
    *) echo "context-budget: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

est() { echo $(( $1 / BYTES_PER_TOK )); }
bytes() { wc -c < "$1" | tr -d ' '; }

# ---- declarative ------------------------------------------------------------
# CLAUDE.md installs at both scopes. rules/ install at project scope only —
# ~/.claude/rules is not read, so harnessctl skips it (see bin/harnessctl).
CLAUDE_TOK=$(est "$(bytes "$PAYLOAD/CLAUDE.md")")
CORE_RULE_TOK=0
DEV_RULE_TOK=0
RESEARCH_RULE_TOK=0

echo "=== context budget ==="
echo "declarative = bytes/$BYTES_PER_TOK (estimate) · plugins = claude plugin details"
echo
echo "declarative — installed by harnessctl, loaded every session"
printf "  %-38s %7s %10s  %s\n" "file" "bytes" "~tok" "scope"
printf "  %-38s %7s %10s  %s\n" "CLAUDE.md" "$(bytes "$PAYLOAD/CLAUDE.md")" "$CLAUDE_TOK" "user + project"
for f in "$PAYLOAD"/rules/*/*.md; do
  [ -f "$f" ] || continue
  mod="$(basename "$(dirname "$f")")"
  rel="rules/$mod/$(basename "$f")"
  b="$(bytes "$f")"; t="$(est "$b")"
  printf "  %-38s %7s %10s  %s\n" "$rel" "$b" "$t" "project only"
  case "$mod" in
    core)     CORE_RULE_TOK=$((CORE_RULE_TOK + t)) ;;
    dev)      DEV_RULE_TOK=$((DEV_RULE_TOK + t)) ;;
    research) RESEARCH_RULE_TOK=$((RESEARCH_RULE_TOK + t)) ;;
    *)        CORE_RULE_TOK=$((CORE_RULE_TOK + t)) ;;
  esac
done

# ---- plugins ----------------------------------------------------------------
# Additive, like verify-plugins: without the CLI the declarative half is still
# reported and the gate still runs on what it can see, saying so.
CLI=1
command -v claude >/dev/null 2>&1 || CLI=0

always_on() {
  [ "$CLI" -eq 1 ] || { echo 0; return; }
  claude plugin details "$1" 2>/dev/null \
    | grep -E "Always-on:" | grep -oE "[0-9]+" | head -1
}

echo
echo "plugins — always-on"
if [ "$CLI" -eq 0 ]; then
  echo "  skip  claude CLI not on PATH — plugin half unmeasured, totals are declarative only"
fi
CORE_P=0; DEV_P=0; RESEARCH_P=0; SLIDES_P=0
for spec in \
  "harness-core@agent-harness:CORE_P" \
  "harness-dev@agent-harness:DEV_P" \
  "superpowers@claude-plugins-official:DEV_P" \
  "harness-research@agent-harness:RESEARCH_P" \
  "harness-slides@agent-harness:SLIDES_P"
do
  name="${spec%%:*}"; var="${spec##*:}"
  v="$(always_on "$name")"
  if [ -z "$v" ]; then
    [ "$CLI" -eq 1 ] && printf "  %-38s %10s\n" "${name%%@*}" "not installed"
    v=0
  else
    printf "  %-38s %10s\n" "${name%%@*}" "$v"
  fi
  eval "$var=\$(( \$$var + v ))"
done

# ---- totals -----------------------------------------------------------------
echo
echo "totals — scope x profile"
printf "  %-8s %-26s %10s\n" "scope" "profiles" "~tok"
WORST=0
report() { # scope, label, total
  printf "  %-8s %-26s %10s\n" "$1" "$2" "$3"
  [ "$3" -gt "$WORST" ] && WORST="$3"
  return 0
}
U_CORE=$((CLAUDE_TOK + CORE_P))
report user    "core"                      "$U_CORE"
report user    "core,dev"                  "$((U_CORE + DEV_P))"
report user    "core,dev,research,slides"  "$((U_CORE + DEV_P + RESEARCH_P + SLIDES_P))"
P_CORE=$((CLAUDE_TOK + CORE_RULE_TOK + CORE_P))
report project "core"                      "$P_CORE"
report project "core,dev"                  "$((P_CORE + DEV_RULE_TOK + DEV_P))"
report project "core,dev,research,slides"  "$((P_CORE + DEV_RULE_TOK + DEV_P + RESEARCH_RULE_TOK + RESEARCH_P + SLIDES_P))"

echo
echo "  worst case: $WORST tok"
if [ "$CEILING" -gt 0 ]; then
  if [ "$WORST" -gt "$CEILING" ]; then
    echo "  FAIL  over the ceiling of $CEILING."
    echo "        Adding always-on context is a tradeoff, not an addition —"
    echo "        propose what comes out in the same change, or raise the"
    echo "        ceiling deliberately in the Makefile and say why."
    exit 1
  fi
  echo "  ceiling:    $CEILING tok    OK ($((CEILING - WORST)) headroom)"
fi
exit 0

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
# Run:  bash scripts/context-budget.sh [--ceiling N] [--require-plugins]
#       exit 1 when the worst-case combination exceeds the ceiling
#
# --require-plugins turns the partial run into a failure. Without it, a machine
# with no Claude CLI — or with the plugins simply not installed — reports every
# plugin cost as 0 and the ceiling passes on the declarative half alone. That is
# useful locally and worthless as a gate, and for a long time it WAS the gate:
# CI ran the ceiling in two jobs that had no CLI, while the one job that
# installed the CLI never ran this script. The published worst case drifted to
# three different values in four documents and nothing noticed.
#
# It also compares the worst case against the number the documents publish, the
# way verify-check-total.sh does for the check count. A measurement nobody
# compares to the claim is not a gate either.

set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD="$REPO/plugins/harness-core/declarative"
BYTES_PER_TOK=4
CEILING=0
REQUIRE_PLUGINS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --ceiling) shift; CEILING="${1:-0}" ;;
    --ceiling=*) CEILING="${1#--ceiling=}" ;;
    --require-plugins) REQUIRE_PLUGINS=1 ;;
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

MISSING=""
STALE=""

# The newest installed version directory for a plugin, or empty.
installed_version() {
  local cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" d
  for d in "$cfg/plugins/cache"/*/"$1"/*/; do
    [ -d "$d" ] || continue
    printf '%s\n' "$(basename "$d")"
  done | sort -V | tail -1
}

always_on() {
  [ "$CLI" -eq 1 ] || { echo ""; return; }
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
    MISSING="$MISSING ${name%%@*}"
    v=0
  else
    # Say which version was measured. A stale install reports a real number for
    # the wrong tree, which reads exactly like a correct one.
    short="${name%%@*}"
    tree_v="$(jq -r '.version // empty' "$REPO/plugins/$short/.claude-plugin/plugin.json" 2>/dev/null)"
    inst_v="$(installed_version "$short")"
    note=""
    if [ -n "$tree_v" ] && [ -n "$inst_v" ] && [ "$tree_v" != "$inst_v" ]; then
      note="  installed $inst_v, tree $tree_v — measuring the OLD one"
      STALE="$STALE $short"
    fi
    printf "  %-38s %10s%s\n" "$short" "$v" "$note"
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

# ---- is this measurement complete? ------------------------------------------
PARTIAL=0
[ -n "$MISSING" ] && PARTIAL=1
if [ "$PARTIAL" -eq 1 ]; then
  echo
  echo "  PARTIAL — ceiling NOT enforced."
  if [ "$CLI" -eq 0 ]; then
    echo "        no claude CLI, so every plugin cost was counted as 0."
  else
    echo "        plugin cost unreadable (not installed?):$MISSING"
  fi
  echo "        totals above are the declarative half only."
fi
if [ -n "$STALE" ]; then
  echo
  echo "  STALE — measured an installed version older than this tree:$STALE"
  echo "        run 'claude plugin update <name>@agent-harness' and measure again."
fi

# ---- does the published number still match? ---------------------------------
# The same job verify-check-total.sh does for the check count. A measurement
# nobody compares against the claim lets the claim drift, which is exactly what
# happened: three different worst cases across four documents, none of them
# right. The phrasing below is load-bearing — reword the sentence and this
# fails loudly, which is the correct direction.
PUB_FAIL=0
check_published() { # <file> <extended-regex capturing ~N tok>
  local f="$REPO/$1" re="$2" hit num
  hit="$(grep -oE "$re" "$f" 2>/dev/null | head -1)"
  if [ -z "$hit" ]; then
    echo "  FAIL  $1 — could not find the published worst case (was the sentence reworded?)"
    PUB_FAIL=1
    return 0
  fi
  num="$(printf '%s' "$hit" | grep -oE '[0-9][0-9,]*' | tr -d ',')"
  if [ "$num" != "$WORST" ]; then
    echo "  FAIL  $1 — publishes $num, the run produced $WORST"
    PUB_FAIL=1
  else
    printf "  ok    %-24s publishes %s\n" "$1" "$num"
  fi
}

if [ "$PARTIAL" -eq 0 ]; then
  echo
  echo "published worst case"
  check_published "README.md"          'project scope with everything is \*\*~[0-9,]+ tok'
  check_published "README.ko.md"       '프로젝트 스코프 전 프로파일은 \*\*~[0-9,]+ tok'
  check_published "docs/agent-layer.md" 'worst case[^|]*\|[^|]*~[0-9,]+ tok'
  check_published "Makefile"           'Measured at [0-9,]+'
fi

if [ "$REQUIRE_PLUGINS" -eq 1 ]; then
  [ "$PARTIAL" -eq 1 ] && { echo; echo "  --require-plugins: a partial measurement is not a gate."; exit 1; }
  [ -n "$STALE" ]      && { echo; echo "  --require-plugins: refusing to gate on a stale install."; exit 1; }
  [ "$PUB_FAIL" -eq 1 ] && { echo; echo "  --require-plugins: the documents and the run disagree."; exit 1; }
fi

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

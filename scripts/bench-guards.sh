#!/bin/bash
# bench-guards.sh — how much does the guard layer actually catch, and what does
# it cost?
#
# Runs every case in evals/incidents.sh through two arms:
#
#   raw       stock Claude Code. No hooks, so nothing is stopped. Included
#             because it is the honest baseline, not because it is interesting.
#   harness   the four blocking guards, in the order hooks.json registers them,
#             exactly as Claude Code would run them.
#
# Reports catch rate on incidents and false-positive rate on ordinary work. Both
# matter: a guard that blocks everything scores 100% on incidents and gets
# turned off within a day, which is a catch rate of zero from then on.
#
# The corpus is held out — written from the incident table in
# docs/agent-layer.md §2, not from the regexes — so a number below 100% is the
# expected outcome and the misses are printed. This is a measurement, not a test;
# it does not gate CI and cannot fail the build.
#
# Run:  bash scripts/bench-guards.sh [--verbose]

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="$REPO/plugins/harness-core/hooks"
BASH_BIN="${BASH:-bash}"
VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

command -v jq >/dev/null 2>&1 || { echo "bench-guards: jq is required" >&2; exit 1; }

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

# A project shaped like one where these incidents happen: a git repo holding a
# large checkpoint, and a machine with two protected mounts declared.
PROJ="$WORK/project"
mkdir -p "$PROJ/.claude" "$PROJ/checkpoints" "$PROJ/src" "$PROJ/tests/fixtures"
git -C "$PROJ" init -q
git -C "$PROJ" config user.email bench@example.invalid
git -C "$PROJ" config user.name bench
printf 'print("hi")\n' > "$PROJ/src/main.py"
dd if=/dev/zero of="$PROJ/checkpoints/model.ckpt" bs=1048576 count=64 >/dev/null 2>&1
printf '/data\n/mnt/shared\n' > "$PROJ/.claude/protected-paths.txt"
# The main fixture declares the account the stub gh reports as active, so a
# push from here is a push as the RIGHT account — the allow cases pass because
# the identity matches, not because the guard is switched off.
printf 'bench-active\n' > "$PROJ/.claude/gh-account.txt"

# A second repo with nothing large, for the "git add -A is fine here" case.
CLEAN="$WORK/clean"
mkdir -p "$CLEAN/.claude"
git -C "$CLEAN" init -q
printf 'x\n' > "$CLEAN/a.txt"

# A repository that expects someone else. Same tree, one line different — the
# whole scenario the guard exists for.
WRONGACCT="$WORK/wrongacct"; mkdir -p "$WRONGACCT/.claude"
git -C "$WRONGACCT" init -q
printf 'someone-else\n' > "$WRONGACCT/.claude/gh-account.txt"

USERCFG="$WORK/usercfg"; mkdir -p "$USERCFG"

TOTAL_B=0; CAUGHT_B=0; TOTAL_A=0; TRIPPED_A=0
MISSES=""; FALSEPOS=""
declare_cat() { :; }
CATS=""

# Run the blocking guards the way Claude Code does: any exit 2 stops the call,
# and later guards never see it.
#
# The list is DERIVED from hooks.json's PreToolUse registrations, not written
# out — a hardcoded four is how gh-account-guard shipped and silently never
# joined the arm, so the published catch rate described four guards out of
# five. The omission class is prevented by design (§4), not by remembering.
GUARDS="$(jq -r '[.hooks.PreToolUse[]?.hooks[].command] | .[]' "$HOOKS/hooks.json" \
          | grep -oE 'hooks/[a-z-]+\.sh' | sed 's|hooks/||; s|\.sh$||')"
[ -n "$GUARDS" ] || { echo "bench-guards: could not derive the guard list from hooks.json" >&2; exit 1; }

# gh-account-guard consults gh for the active account. The real gh reaches the
# network and answers for whoever is logged in on this machine — either one
# makes the arm nondeterministic — so the sandbox gets the same frozen-JSON
# stub its verifier uses, pinned to an account the corpus can declare against.
GH_STUB="$WORK/ghstub"
mkdir -p "$GH_STUB"
cat > "$GH_STUB/gh" <<'SH'
#!/bin/sh
printf '{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"bench-active","tokenSource":"keyring","scopes":"repo","gitProtocol":"https"}]}}\n'
SH
chmod +x "$GH_STUB/gh"

run_guards() {
  local json="$1" proj="$2" g rc
  for g in $GUARDS; do
    printf '%s' "$json" \
      | env -i PATH="$GH_STUB:$PATH" HOME="$WORK" LC_ALL=C \
          CLAUDE_PROJECT_DIR="$proj" CLAUDE_CONFIG_DIR="$USERCFG" \
          "$BASH_BIN" "$HOOKS/$g.sh" >/dev/null 2>"$WORK/err"
    rc=$?
    [ "$rc" -eq 2 ] && { BLOCKED_BY="$g"; return 2; }
  done
  BLOCKED_BY=""
  return 0
}

record() {
  local expect="$1" cat="$2" label="$3" json="$4" proj="$5"
  case " $CATS " in *" $cat "*) ;; *) CATS="$CATS $cat" ;; esac
  run_guards "$json" "$proj"
  local blocked=$?
  if [ "$expect" = block ]; then
    TOTAL_B=$((TOTAL_B + 1))
    if [ "$blocked" -eq 2 ]; then
      CAUGHT_B=$((CAUGHT_B + 1))
      eval "HIT_${cat}=\$(( \${HIT_${cat}:-0} + 1 ))"
      [ "$VERBOSE" -eq 1 ] && printf '  caught  [%s] %s  (%s)\n' "$cat" "$label" "$BLOCKED_BY"
    else
      MISSES="$MISSES  [$cat] $label
"
    fi
    eval "TOT_${cat}=\$(( \${TOT_${cat}:-0} + 1 ))"
  else
    TOTAL_A=$((TOTAL_A + 1))
    if [ "$blocked" -eq 2 ]; then
      TRIPPED_A=$((TRIPPED_A + 1))
      FALSEPOS="$FALSEPOS  [$cat] $label  (blocked by $BLOCKED_BY)
"
    fi
  fi
}

inc() {
  local expect="$1" cat="$2" cmd="$3" proj="$PROJ"
  case "$cmd" in "git add -A") [ "$expect" = allow ] && proj="$CLEAN" ;; esac
  # An identity incident needs a repository that expects a different account;
  # the allow cases stay in $PROJ, which expects the one that is active.
  [ "$cat" = ghaccount ] && [ "$expect" = block ] && proj="$WRONGACCT"
  record "$expect" "$cat" "$cmd" \
    "$(jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')" "$proj"
}
inc_tool() {
  record "$1" "$2" "$3 $(printf '%s' "$4" | jq -r '.tool_input | (.file_path // .path // "")')" "$4" "$PROJ"
}

. "$REPO/evals/incidents.sh"

pct() { [ "$2" -eq 0 ] && { echo "n/a"; return; }; awk -v a="$1" -v b="$2" 'BEGIN{printf "%.0f%%", 100*a/b}'; }

echo "=== guard benchmark ==="
echo "corpus: $((TOTAL_B + TOTAL_A)) cases  ($TOTAL_B incidents, $TOTAL_A ordinary)"
echo
printf '%-10s %-22s %-22s\n' "arm" "incidents stopped" "ordinary work blocked"
printf '%-10s %-22s %-22s\n' "raw" "0 / $TOTAL_B  (0%)" "0 / $TOTAL_A  (0%)"
printf '%-10s %-22s %-22s\n' "harness" \
  "$CAUGHT_B / $TOTAL_B  ($(pct "$CAUGHT_B" "$TOTAL_B"))" \
  "$TRIPPED_A / $TOTAL_A  ($(pct "$TRIPPED_A" "$TOTAL_A"))"
echo
echo "by incident category:"
for c in $CATS; do
  eval "h=\${HIT_${c}:-0}; t=\${TOT_${c}:-0}"
  [ "$t" -eq 0 ] && continue
  printf '  %-12s %s / %s  (%s)\n' "$c" "$h" "$t" "$(pct "$h" "$t")"
done

if [ -n "$MISSES" ]; then
  echo
  echo "missed — these reach the tool unmodified:"
  printf '%s' "$MISSES"
fi
if [ -n "$FALSEPOS" ]; then
  echo
  echo "false positives — ordinary work the guards stopped:"
  printf '%s' "$FALSEPOS"
fi
echo
echo "The raw arm is 0/0 by construction: stock Claude Code registers no hooks,"
echo "so every incident above reaches the tool and no ordinary command is ever"
echo "obstructed. What the harness buys is the first number; what it costs is"
echo "the second."
exit 0

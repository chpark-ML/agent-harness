#!/bin/bash
# verify-benches.sh — do the benchmarks still work, without spending anything?
#
# `bench-claims` rotted and nobody noticed. Its corpus was rebuilt from a git
# commit; the repository history was rewritten; the commit vanished; the
# benchmark went on exiting cleanly with an empty corpus while the README kept
# quoting its last number as current. Nothing was watching, because benchmarks
# are not part of `make verify` — they cost money and CI cannot run them.
#
# Except two of them do not cost anything. `bench` drives the hooks directly and
# `bench-claims` drives the claim checker; neither starts an agent session. Those
# two run here for real. The three that do burn sessions get their inputs
# checked instead — corpus present, eval sets well-formed, fixtures buildable —
# which is exactly the class of failure that rotted bench-claims.
#
# Run:  bash scripts/verify-benches.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || exit 1

. "$(cd "$(dirname "$0")" && pwd)/_check-lib.sh"

echo "=== benchmark health ==="
echo

# --- free benchmarks: run them ------------------------------------------------
echo "--- these cost nothing, so they actually run"

# Inherit the interpreter instead of pinning /bin/bash: the pin is wrong in
# both directions — on Linux /bin/bash IS bash 5, so it only pretended to test
# the floor, and under `make verify BASH=/bin/bash` it overrode the very
# variable the floor job sets.
out="$("${BASH:-bash}" scripts/bench-guards.sh 2>&1)" || true
printf '%s' "$out" | grep -qE 'harness +[0-9]+ / [0-9]+' \
  && ok "bench (guards) produces an arm table" \
  || bad "bench (guards) produces an arm table" "$(printf '%s' "$out" | tail -2)"

# Both declaration forms count: `inc` for Bash cases, `inc_tool` for the rest.
# Matching only '^inc ' undercounts, and then this gate tracks a number the
# benchmark itself never prints.
n_inc="$(grep -cE '^inc(_tool)? ' evals/incidents.sh 2>/dev/null)"
[ "${n_inc:-0}" -ge 40 ] && ok "incident corpus still has $n_inc cases" \
  || bad "incident corpus size" "found ${n_inc:-0}, expected >= 40"

out="$("${BASH:-bash}" scripts/bench-claims.sh 2>&1)" || true
printf '%s' "$out" | grep -qE 'flagged: [0-9]+ of [0-9]+ tokens' \
  && ok "bench-claims produces a flag count" \
  || bad "bench-claims produces a flag count" "$(printf '%s' "$out" | tail -2)"

checked="$(printf '%s' "$out" | grep -oE 'of [0-9]+ tokens' | grep -oE '[0-9]+' | head -1)"
[ "${checked:-0}" -ge 100 ] && ok "claim corpus yields $checked tokens" \
  || bad "claim corpus is empty or tiny" "yielded ${checked:-0} — this is exactly how it rotted before"

# --- paid benchmarks: check their inputs --------------------------------------
echo
# --- interpreter propagation --------------------------------------------------
# Five nested invocations once named a literal interpreter, and under
# `make verify BASH=/bin/bash` the installer suite quietly ran under bash 5 —
# the floor job untested exactly where it was largest. The rule is one line:
# a script reaches a sibling through "${BASH:-bash}". This is the omission
# class, so it is pinned by a pattern over the whole directory rather than by
# enumerating the five sites already fixed. Comments and lines that merely
# PRINT an invocation (user-facing hints) are excluded.
viol="$(grep -nE '(^|[^A-Za-z_"])bash[[:space:]]+("\$REPO|scripts/|evals/)' scripts/*.sh 2>/dev/null \
        | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' \
        | grep -vE '(echo|printf|say) ' || true)"
if [ -z "$viol" ]; then
  ok "nested runs inherit \${BASH:-bash}; none name a literal interpreter"
else
  bad "nested runs inherit \${BASH:-bash}; none name a literal interpreter" "$viol"
fi

echo "--- these burn agent sessions, so only their inputs are checked"

[ -s evals/prose-corpus.md ] && ok "frozen prose corpus present" || bad "frozen prose corpus present"
grep -q 'DO NOT EDIT' evals/prose-corpus.md 2>/dev/null \
  && ok "prose corpus says not to regenerate itself" || bad "prose corpus carries its own warning"

n_sets=0; bad_sets=""
for f in evals/trigger/*.json; do
  [ -e "$f" ] || continue
  # transient benchmark output, not an eval set
  case "$(basename "$f")" in last-result.json) continue ;; esac
  n_sets=$((n_sets + 1))
  python3 - "$f" <<'PY' || bad_sets="$bad_sets $(basename "$f")"
import json, sys

# The assert message below carries an em-dash and reaches the user through the
# interpreter's traceback on stderr, so a strict stream turns a readable
# assertion into a UnicodeEncodeError about the assertion.
sys.stdout.reconfigure(errors='replace')
sys.stderr.reconfigure(errors='replace')

# encoding='utf-8', not the locale's: five of these eval sets carry Korean
# trigger phrases, and a bare open() reads them through cp949 on Korean Windows
# and fails to decode the file it is supposed to be validating.
d = json.load(open(sys.argv[1], encoding='utf-8'))
assert isinstance(d, dict), "not an object — eval sets must declare their skill"
assert d.get("skill"), "no skill id"
c = d["cases"]
pos = [x for x in c if x["should_trigger"]]
neg = [x for x in c if not x["should_trigger"]]
assert len(pos) >= 3 and len(neg) >= 3, f"needs >=3 each way, got {len(pos)}/{len(neg)}"
PY
done
[ "$n_sets" -ge 1 ] && ok "$n_sets trigger eval sets found" || bad "no trigger eval sets"
[ -z "$bad_sets" ] && ok "every eval set declares a skill and balances both ways" \
  || bad "malformed eval sets" "$bad_sets"

W="$(mktemp -d)"
"${BASH:-bash}" evals/fixture-python.sh "$W/fx" >/dev/null 2>&1 \
  && [ -f "$W/fx/app/config.py" ] && ok "bench-lsp fixture builds" || bad "bench-lsp fixture builds"
rm -rf "$W"

for s in scripts/bench-convention.sh scripts/bench-lsp.sh scripts/bench-tier.sh; do
  grep -q '_bench-lib.sh' "$s" && grep -q 'bench_confirm' "$s" \
    && ok "$(basename "$s") asks before touching anything outside the repo" \
    || bad "$(basename "$s") has no consent gate"
done

# A bench that pins a specific commit will rot the next time history moves --
# which is precisely how bench-claims died. Counting commits in a scratch repo
# (`rev-list --count HEAD`) is fine; naming a SHA is not.
if grep -nE '[^0-9a-f][0-9a-f]{7,40}[^0-9a-f]?' scripts/bench-*.sh scripts/bench-*.py 2>/dev/null \
     | grep -vE 'sha1|sha256|[0-9a-f]{7,}\.\.\.' \
     | grep -qE ':-[0-9a-f]{7,40}\}|git (show|rev-parse|log) [0-9a-f]{7,40}'; then
  bad "a bench still pins a git object" "$(grep -nE ':-[0-9a-f]{7,40}\}|git (show|rev-parse|log) [0-9a-f]{7,40}' scripts/bench-*.sh | head -2)"
else
  ok "no bench depends on a git commit staying reachable"
fi

summary

#!/bin/bash
# verify-inventory.sh — the inventory figures in the documents have to be the
# real ones.
#
# verify-check-total.sh already does this for the published check count, and
# nothing did it for anything else. The cost of that gap is measured, not
# guessed: in a single day, `6 guards` survived a completeness audit in four
# places and `104 assertions` drifted in six more, both after being swept by
# hand. A hand-swept count is wrong in exactly the places the hand missed.
#
# Each figure is derived from the artifact that defines it, never from another
# document:
#
#   hooks         hooks.json — total registrations, PreToolUse vs the rest
#   permissions   settings-fragment.json — allow / ask / deny lengths
#   assertions    the count verify-install.sh actually reports when run
#
# Statements are DISCOVERED, not listed. The first version of this script
# enumerated phrasings, and a review found the obvious consequence within the
# hour: `docs/engineering-axes.md:22` still said `6 guards` against a hooks.json
# holding 7, and the new verifier passed anyway. A checker that misses what it
# was written to catch is worse than none, because it also claims the ground is
# covered.
#
# So every "<number> <inventory word>" pairing in the documents is found by
# pattern and each occurrence is checked. The scan is anchored on the words that
# only ever qualify these figures — guards, blocking, informational, assertions,
# 가드, 차단, 정보 — so an unrelated number cannot be swept in. A phrase that
# should not be checked has to be excluded by name below, which is loud.
#
# Harness-repo only — not shipped to consumers.
# Run:  bash scripts/verify-inventory.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_JSON="$REPO/plugins/harness-core/hooks/hooks.json"
FRAGMENT="$REPO/plugins/harness-core/declarative/settings-fragment.json"

command -v jq >/dev/null 2>&1 || { echo "verify-inventory: jq is required" >&2; exit 1; }

PASS=0; FAIL=0; FAILED=""
ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED="$FAILED$1
"; printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

# scan <label> <expected> <extended regex> — check EVERY occurrence, in every
# document, and fail if a document states this figure nowhere at all.
#
# Every number inside a matched phrase is compared, not just the first. The
# earlier version took `head -1` and so never looked at the informational count
# or at ask/deny: setting them to 99 left the suite green. A partially-checked
# phrase reads as a checked one.
DOCS="README.md README.ko.md docs/agent-layer.md docs/engineering-axes.md"

scan() {
  local label="$1" want="$2" re="$3" rel f hits line num seen=0
  for rel in $DOCS; do
    f="$REPO/$rel"
    [ -f "$f" ] || continue
    hits="$(grep -nE "$re" "$f" 2>/dev/null)"
    [ -n "$hits" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      seen=$((seen + 1))
      lineno="${line%%:*}"
      phrase="$(printf '%s' "$line" | grep -oE "$re" | head -1)"
      # Compare every number the phrase carries.
      badnum=""
      for num in $(printf '%s' "$phrase" | grep -oE '[0-9]+'); do
        [ "$num" = "$want" ] || badnum="$badnum $num"
      done
      if [ -z "$badnum" ]; then
        ok "$rel:$lineno — $label"
      else
        bad "$rel:$lineno — $label" "\"$phrase\" carries$badnum, the artifact has $want"
      fi
    done <<EOF
$hits
EOF
  done
  if [ "$seen" -eq 0 ]; then
    bad "$label — stated nowhere" "no document matches /$re/; if the phrasing changed, update this pattern"
  fi
}

echo "=== inventory verification ==="
echo

# ---- derive ------------------------------------------------------------------
HOOKS_TOTAL="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[]] | length' "$HOOKS_JSON")"
HOOKS_BLOCKING="$(jq -r '[.hooks.PreToolUse[]?.hooks[]] | length' "$HOOKS_JSON")"
HOOKS_INFO=$((HOOKS_TOTAL - HOOKS_BLOCKING))
ALLOW="$(jq -r '.permissions.allow | length' "$FRAGMENT")"
ASK="$(jq -r '.permissions.ask | length' "$FRAGMENT")"
DENY="$(jq -r '.permissions.deny | length' "$FRAGMENT")"

echo "derived from the artifacts"
printf '  hooks.json                  %s registrations (%s blocking, %s informational)\n' \
  "$HOOKS_TOTAL" "$HOOKS_BLOCKING" "$HOOKS_INFO"
printf '  settings-fragment.json      allow %s / ask %s / deny %s\n' "$ALLOW" "$ASK" "$DENY"
echo

# A registration naming a script that does not exist keeps the count honest and
# the harness broken, so the two are checked against each other.
missing=""
for c in $(jq -r '[.hooks | to_entries[] | .value[] | .hooks[].command] | .[]' "$HOOKS_JSON" \
           | grep -oE 'hooks/[a-z-]+\.sh'); do
  [ -f "$REPO/plugins/harness-core/$c" ] || missing="$missing $c"
done
if [ -z "$missing" ]; then ok "every registration points at a script that exists"
else bad "every registration points at a script that exists" "missing:$missing"; fi

# And the reverse: a script in hooks/ that nothing registers never runs.
unreg=""
for f in "$REPO"/plugins/harness-core/hooks/*.sh; do
  n="$(basename "$f")"
  grep -q "hooks/$n" "$HOOKS_JSON" || unreg="$unreg $n"
done
if [ -z "$unreg" ]; then ok "every script in hooks/ is registered"
else bad "every script in hooks/ is registered" "unregistered:$unreg"; fi

# ---- hooks -------------------------------------------------------------------
# Each pattern isolates numbers that must all equal ONE derived value, so a
# multi-count sentence is split across two calls rather than checked as a whole.
echo
echo "hook count ($HOOKS_TOTAL)"
scan "total"  "$HOOKS_TOTAL" '[0-9]+ guards'
scan "total"  "$HOOKS_TOTAL" '가드 훅 [0-9]+|가드 [0-9]+,'
# The two-number sentences are split: one pattern for the leading total, another
# for the blocking count below. A pattern must only ever carry numbers that all
# equal ONE derived value, or a correct document fails.
scan "total"  "$HOOKS_TOTAL" 'Guard hooks\*\* \| \*\*[0-9]+\*\*|가드 훅\*\* \| \*\*[0-9]+\*\*'
scan "total"  "$HOOKS_TOTAL" 'Hooks .*✅ [0-9]+ '

echo
echo "blocking ($HOOKS_BLOCKING)"
scan "blocking" "$HOOKS_BLOCKING" '[0-9]+ blocking PreToolUse'
scan "blocking" "$HOOKS_BLOCKING" '차단 [0-9]+'

echo
echo "informational ($HOOKS_INFO)"
scan "informational" "$HOOKS_INFO" '[0-9]+ informational'
scan "informational" "$HOOKS_INFO" '정보 [0-9]+'

# ---- permissions -------------------------------------------------------------
echo
echo "permission tiers (allow $ALLOW / ask $ASK / deny $DENY)"
scan "allow" "$ALLOW" 'allow [0-9]+'
scan "ask"   "$ASK"   'ask [0-9]+'
scan "deny"  "$DENY"  'deny [0-9]+'

# ---- installer assertions ----------------------------------------------------
# Run the real thing rather than trusting a number typed beside it. This is the
# figure that drifted in six places on the day it was written.
echo
# ${BASH:-bash}, not a literal: under `make verify BASH=/bin/bash` — the macOS
# 3.2 floor job, the whole reason the variable exists — a hardcoded bash here
# produced the assertion count with bash 5 while everything around it ran 3.2.
INSTALL_OUT="$("${BASH:-bash}" "$REPO/scripts/verify-install.sh" 2>&1 | grep -oE '^  [0-9]+ / [0-9]+ passed' | tail -1)"
INSTALL_N="$(printf '%s' "$INSTALL_OUT" | grep -oE '/ [0-9]+' | grep -oE '[0-9]+')"
if [ -z "$INSTALL_N" ]; then
  bad "verify-install.sh reports a total" "got: $INSTALL_OUT"
else
  echo "installer assertions ($INSTALL_N)"
  scan "assertions" "$INSTALL_N" '[0-9]+ assertions?'
fi

echo
echo "=== Summary ==="
echo "  $PASS / $((PASS + FAIL)) passed"
if [ "$FAIL" -gt 0 ]; then
  echo "  $FAIL failed:"
  printf '%s' "$FAILED" | while IFS= read -r n; do [ -n "$n" ] && echo "    - $n"; done
  echo
  echo "  Fix the document, or — if the artifact really changed — fix it everywhere."
  exit 1
fi
exit 0

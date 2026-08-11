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
# Phrasings are listed, not globbed, and that is a deliberate trade. A new
# sentence stating the count is not caught until someone adds its pattern here.
# The alternative — grepping every bare `7` in the READMEs — is a false-positive
# machine, and a check that cries wolf gets switched off (ADR-0003). What this
# does catch is the case that actually happens: an existing sentence going stale
# while the artifact moves.
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

# expect_count <label> <file> <extended regex> <expected>
# The regex must match a whole phrase; the number is taken from the match, so a
# pattern that stops matching is a failure rather than a silent pass.
expect_count() {
  local label="$1" rel="$2" re="$3" want="$4" f="$REPO/$2" hit got
  if [ ! -f "$f" ]; then bad "$rel — file missing" ; return 0; fi
  hit="$(grep -oE "$re" "$f" 2>/dev/null | head -1)"
  if [ -z "$hit" ]; then
    bad "$rel — $label" "no phrase matched /$re/ (was the sentence reworded?)"
    return 0
  fi
  got="$(printf '%s' "$hit" | grep -oE '[0-9]+' | head -1)"
  if [ "$got" = "$want" ]; then ok "$rel — $label says $got"
  else bad "$rel — $label" "says $got, the artifact has $want"; fi
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

# A registration that names a script which does not exist would make the count
# real and the harness broken, so the two are checked against each other.
missing=""
for c in $(jq -r '[.hooks | to_entries[] | .value[] | .hooks[].command] | .[]' "$HOOKS_JSON" \
           | grep -oE 'hooks/[a-z-]+\.sh'); do
  [ -f "$REPO/plugins/harness-core/$c" ] || missing="$missing $c"
done
echo
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

# ---- the documents -----------------------------------------------------------
echo
echo "hook count"
expect_count "the profile table"   README.md    '\*\*[0-9]+\*\* — [0-9]+ blocking, [0-9]+ informational' "$HOOKS_TOTAL"
expect_count "blocking"            README.md    '[0-9]+ blocking, [0-9]+ informational'                  "$HOOKS_BLOCKING"
expect_count "the everything row"  README.md    '[0-9]+ guards, three permission tiers'                  "$HOOKS_TOTAL"
expect_count "the adoption table"  docs/agent-layer.md '✅ [0-9]+ \([0-9]+ blocking, [0-9]+ informational\)' "$HOOKS_TOTAL"
expect_count "blocking"            docs/agent-layer.md '\([0-9]+ blocking, [0-9]+ informational\)'          "$HOOKS_BLOCKING"
expect_count "the layout comment"  docs/agent-layer.md '[0-9]+ blocking \+ [0-9]+ informational'            "$HOOKS_BLOCKING"
expect_count "the axes table"      docs/engineering-axes.md '[0-9]+ blocking PreToolUse hooks'              "$HOOKS_BLOCKING"
expect_count "the profile table"   README.ko.md '\*\*[0-9]+\*\* — 차단 [0-9]+ · 정보 [0-9]+'                "$HOOKS_TOTAL"
expect_count "blocking"            README.ko.md '차단 [0-9]+ · 정보 [0-9]+'                                 "$HOOKS_BLOCKING"
expect_count "the guards section"  README.ko.md '### 가드 훅 [0-9]+개'                                      "$HOOKS_TOTAL"

echo
echo "permission tiers"
expect_count "allow" README.md           'allow [0-9]+ / ask [0-9]+ / deny [0-9]+' "$ALLOW"
expect_count "ask"   README.md           'ask [0-9]+ / deny [0-9]+'                "$ASK"
expect_count "deny"  README.md           'deny [0-9]+'                             "$DENY"
expect_count "allow" README.ko.md        'allow [0-9]+ / ask [0-9]+ / deny [0-9]+' "$ALLOW"
expect_count "allow" docs/agent-layer.md 'allow [0-9]+ / ask [0-9]+ / deny [0-9]+' "$ALLOW"

# ---- installer assertions ----------------------------------------------------
# Run the real thing rather than trusting a number typed beside it. This is the
# figure that drifted in six places on the day it was written.
echo
echo "installer assertions"
INSTALL_OUT="$(bash "$REPO/scripts/verify-install.sh" 2>&1 | grep -oE '^  [0-9]+ / [0-9]+ passed' | tail -1)"
INSTALL_N="$(printf '%s' "$INSTALL_OUT" | grep -oE '/ [0-9]+' | grep -oE '[0-9]+')"
if [ -z "$INSTALL_N" ]; then
  bad "verify-install.sh reports a total" "got: $INSTALL_OUT"
else
  printf '  verify-install.sh reports    %s assertions\n' "$INSTALL_N"
  expect_count "assertions" README.md           '[0-9]+ assertions hold that line' "$INSTALL_N"
  expect_count "assertions" README.md           'canonically identical\*\*, [0-9]+ assertions' "$INSTALL_N"
  expect_count "assertions" README.ko.md        '정준 동일\*\* — [0-9]+ assertion' "$INSTALL_N"
  expect_count "assertions" docs/agent-layer.md '\| [0-9]+ assertions \| An invariant' "$INSTALL_N"
  expect_count "assertions" docs/agent-layer.md "verify-install.sh\`'s [0-9]+ assertions" "$INSTALL_N"
  expect_count "assertions" docs/engineering-axes.md '[0-9]+ assertions, canonically identical' "$INSTALL_N"
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

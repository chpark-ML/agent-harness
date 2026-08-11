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

# Overridable so --selftest can point the whole battery at a fixture tree.
REPO="${VERIFY_INVENTORY_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
HOOKS_JSON="$REPO/plugins/harness-core/hooks/hooks.json"
FRAGMENT="$REPO/plugins/harness-core/declarative/settings-fragment.json"

command -v jq >/dev/null 2>&1 || { echo "verify-inventory: jq is required" >&2; exit 1; }

. "$(cd "$(dirname "$0")" && pwd)/_check-lib.sh"

# scan <label> <expected> <extended regex> — check EVERY occurrence, in every
# document, and fail if a document states this figure nowhere at all.
#
# Every number inside a matched phrase is compared, not just the first. The
# earlier version took `head -1` and so never looked at the informational count
# or at ask/deny: setting them to 99 left the suite green. A partially-checked
# phrase reads as a checked one.
# The document set is DISCOVERED, not listed — the 2회차 ledger entry that
# mandated this verifier said so ("파일 목록은 하드코딩이 아니라 glob"), and the
# first implementation ignored it, which is exactly why four stale ADR counts
# survived the scan. Every markdown file at the root and under docs/ is in,
# except:
#   - files carrying the dated-record marker (checked per file below) — ADRs
#     and Superpowers specs/plans freeze their figures on purpose, and each
#     names the source of truth in the sentence the marker lives in;
#   - evals/prose-corpus.md and .claude/harness-gaps.md, excluded by
#     construction: neither lives at the root nor under docs/.
# A skip is printed, never silent.
MARKER="a record of that moment"
DOCS="README.md README.ko.md CLAUDE.md CONTRIBUTING.md AGENTS.md SECURITY.md"
for _f in $(cd "$REPO" && find docs -name '*.md' | LC_ALL=C sort); do
  DOCS="$DOCS $_f"
done

SKIPPED=""
is_frozen() { # <abs path> — dated records opt out via the marker
  grep -q "$MARKER" "$1" 2>/dev/null
}

scan() {
  local label="$1" want="$2" re="$3" only="${4:-}" rel f hits line num seen=0
  for rel in $DOCS; do
    f="$REPO/$rel"
    [ -f "$f" ] || continue
    # Optional per-pattern EXCLUDE, for figures whose words collide with a
    # different figure elsewhere — docs/hooks/*.md counts its own per-hook
    # cases in "assertions", which is correct there and wrong here. An
    # exclusion is per-pattern, never per-file: the same file stays in every
    # other scan, and a new file stating the real figure is still caught.
    if [ -n "$only" ]; then
      case "$rel" in $only) continue ;; esac
    fi
    if is_frozen "$f"; then
      case " $SKIPPED " in *" $rel "*) ;; *)
        SKIPPED="$SKIPPED $rel"
        echo "  skip  $rel — dated record"
      ;; esac
      continue
    fi
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

# ---- selftest ----------------------------------------------------------------
# The scanner's own failure modes, exercised against a fixture tree before the
# real run — the shape verify-doc-refs.sh set. The first version of this script
# shipped without one, and a review found within the hour that it passed over a
# live drift and validated only the first number of multi-count phrases.
if [ "${1:-}" = "--selftest" ]; then
  echo "=== inventory selftest ==="
  FIX="$(mktemp -d)" || exit 1
  trap 'rm -rf "$FIX"' EXIT

  mkdir -p "$FIX/plugins/harness-core/hooks" "$FIX/plugins/harness-core/declarative" \
           "$FIX/scripts" "$FIX/docs/hooks"
  cat > "$FIX/plugins/harness-core/hooks/hooks.json" <<'J'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}/hooks/alpha-guard.sh\""}]}],
"Stop":[{"matcher":"","hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}/hooks/beta-brief.sh\""}]}]}}
J
  : > "$FIX/plugins/harness-core/hooks/alpha-guard.sh"
  : > "$FIX/plugins/harness-core/hooks/beta-brief.sh"
  printf '{"permissions":{"allow":["a","b","c"],"ask":["d"],"deny":["e","f"]}}\n' \
    > "$FIX/plugins/harness-core/declarative/settings-fragment.json"
  printf '#!/bin/sh\necho "  7 / 7 passed"\n' > "$FIX/scripts/verify-install.sh"

  # The documents: one drifted, one frozen-with-drift, one boundary-laden, one
  # correct (so no pattern is stated nowhere except the one asserted below).
  cat > "$FIX/README.md" <<'D'
2 guards, three permission tiers. allow 3 / ask 1 / deny 2.
**2** — 1 blocking, 1 informational. 7 assertions hold that line.
D
  printf '9 guards live here.\n' > "$FIX/docs/drifted.md"
  printf 'frozen: 9 guards — the figures here are a record of that moment.\n' > "$FIX/docs/frozen.md"
  printf '### Task 25 is not a tier count. A subtask 25 neither.\n' > "$FIX/docs/boundary.md"
  printf 'this hook has 45 assertions across 30 cases.\n' > "$FIX/docs/hooks/some-guard.md"

  out="$(VERIFY_INVENTORY_REPO="$FIX" "${BASH:-bash}" "$0" 2>&1)"; rc=$?

  check_rc "a drifted count is caught" \
    "$(printf '%s' "$out" | grep -q 'docs/drifted.md:1 — total' && echo 0 || echo 1)" \
    "$(printf '%s' "$out" | grep drifted | head -1)"
  check_rc "...and the run fails" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
  check_rc "a dated record is skipped, and says so" \
    "$(printf '%s' "$out" | grep -q 'skip  docs/frozen.md — dated record' && echo 0 || echo 1)"
  check_rc "...and its drift is not reported" \
    "$(printf '%s' "$out" | grep -q 'frozen.md:1' && echo 1 || echo 0)"
  check_rc "Task 25 does not read as a tier count" \
    "$(printf '%s' "$out" | grep -qE 'boundary.md.* (ask|total)' && echo 1 || echo 0)"
  check_rc "a per-hook case count is not the installer figure" \
    "$(printf '%s' "$out" | grep -q 'some-guard.md' && echo 1 || echo 0)"
  check_rc "the installer figure itself is still compared" \
    "$(printf '%s' "$out" | grep -q 'README.md:2 — assertions' && echo 0 || echo 1)"

  summary
  exit $?
fi

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
scan "allow" "$ALLOW" '(^|[^A-Za-z])allow [0-9]+'
# Word-boundaried: "Task 2" contains the literal substring "ask 2".
scan "ask"   "$ASK"   '(^|[^A-Za-z])ask [0-9]+'
scan "deny"  "$DENY"  '(^|[^A-Za-z])deny [0-9]+'

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
  scan "assertions" "$INSTALL_N" '[0-9]+ assertions?' 'docs/hooks/*'
fi

summary "  Fix the document, or — if the artifact really changed — fix it everywhere."
exit $?

#!/bin/bash
# verify-context-budget.sh — behavioural verification of context-budget.sh,
# and specifically of the paths that turn it from a measurement into a gate.
#
# CI only ever exercises the happy path: the plugin job installs everything and
# the strict run passes. The CLI-less jobs never pass --require-plugins. So the
# partial, stale-install, mismatch and ceiling exits — the load-bearing ones —
# ran nowhere, and a regression in any of them would silently restore the exact
# blind spot the flag was added to close.
#
# The three failure directions were checked by hand once. This repository has
# already written down what that is worth: "손 확인은 회귀를 막지 못한다."
#
# Harness-repo only — not shipped to consumers.
# Run:  bash scripts/verify-context-budget.sh

set -uo pipefail

HARNESS="$(cd "$(dirname "$0")/.." && pwd)"
BASH_BIN="${BASH:-bash}"
WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

. "$(cd "$(dirname "$0")" && pwd)/_check-lib.sh"

echo "=== context-budget verification ==="
echo

# ---- a fixture repository ---------------------------------------------------
# context-budget.sh resolves its own repo as <script>/.., so a copy of the tree
# it reads is enough, and it lets a case publish a wrong number without touching
# the real documents.
FIX="$WORK/repo"
mkdir -p "$FIX/scripts" "$FIX/plugins/harness-core/declarative" "$FIX/docs"
cp "$HARNESS/scripts/context-budget.sh" "$FIX/scripts/"
cp -R "$HARNESS/plugins/harness-core/declarative/CLAUDE.md" \
      "$HARNESS/plugins/harness-core/declarative/rules" \
      "$FIX/plugins/harness-core/declarative/"
for p in core dev research slides; do
  mkdir -p "$FIX/plugins/harness-$p/.claude-plugin"
  printf '{"name":"harness-%s","version":"9.9.9"}\n' "$p" \
    > "$FIX/plugins/harness-$p/.claude-plugin/plugin.json"
done

# The published figures. Rewritten per case; the phrasing has to match the
# patterns context-budget.sh greps for.
publish() { # <number>
  printf 'project scope with everything is **~%s tok per session** x\n' "$1" > "$FIX/README.md"
  printf '프로젝트 스코프 전 프로파일은 **~%s tok / 세션** 이다\n' "$1" > "$FIX/README.ko.md"
  printf '| **worst case** (project, every profile) | **~%s tok / session** | ceiling 9,000 |\n' "$1" \
    > "$FIX/docs/agent-layer.md"
  printf '# Measured at %s in CI\n' "$1" > "$FIX/Makefile"
}

# ---- a fake claude ----------------------------------------------------------
# The real one needs plugins installed and reaches the network. This emits the
# one line always_on() greps for, and STUB_SKIP names a plugin it refuses to
# know about, which is how "installed the CLI but not the plugins" is reproduced.
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'SH'
#!/bin/bash
# claude plugin details <name>@<marketplace>
[ "${1:-}" = "plugin" ] && [ "${2:-}" = "details" ] || exit 0
name="${3%%@*}"
case " ${STUB_SKIP:-} " in *" $name "*) exit 1 ;; esac
printf '  Always-on:   ~%s tok   added to every session\n' "${STUB_COST:-100}"
SH
chmod +x "$BIN/claude"

# A plugin cache, so installed_version() has something to read.
CACHE="$WORK/cfg/plugins/cache/agent-harness"
mk_cache() { # <version>
  rm -rf "$WORK/cfg/plugins"
  for p in core dev research slides; do mkdir -p "$CACHE/harness-$p/$1"; done
}
mk_cache 9.9.9

run_budget() { # <extra args...> — sets RC, OUT
  OUT="$( cd "$FIX" && env PATH="$BIN:$PATH" CLAUDE_CONFIG_DIR="$WORK/cfg" \
          STUB_COST="${STUB_COST:-100}" STUB_SKIP="${STUB_SKIP:-}" \
          "$BASH_BIN" "$FIX/scripts/context-budget.sh" "$@" 2>&1 )"
  RC=$?
}
run_nocli() { # PATH without the fake claude
  OUT="$( cd "$FIX" && env PATH="/usr/bin:/bin" CLAUDE_CONFIG_DIR="$WORK/cfg" \
          "$BASH_BIN" "$FIX/scripts/context-budget.sh" "$@" 2>&1 )"
  RC=$?
}
worst_of() { printf '%s' "$OUT" | grep -oE 'worst case: [0-9]+' | grep -oE '[0-9]+'; }

# ---- 1. the happy path ------------------------------------------------------
echo "complete measurement"
STUB_SKIP="" run_budget --ceiling 99999
W="$(worst_of)"
publish "$W"
run_budget --ceiling 99999 --require-plugins
check_eq "a complete strict run passes" 0 "$RC"
case "$OUT" in *"PARTIAL"*) bad "...and does not call itself partial" ;; *) ok "...and does not call itself partial" ;; esac

# ---- 2. no CLI --------------------------------------------------------------
echo
echo "incomplete measurement"
run_nocli --ceiling 99999 --require-plugins
check_eq "no claude CLI under --require-plugins fails" 1 "$RC"
case "$OUT" in *"PARTIAL"*) ok "...and says the ceiling was not enforced" ;; *) bad "...and says the ceiling was not enforced" "$OUT" ;; esac

# Without the flag a partial run is allowed — that is the local-development
# affordance, and it is why the flag had to exist at all.
run_nocli --ceiling 99999
check_eq "no claude CLI without the flag still exits 0" 0 "$RC"

# ---- 3. CLI present, plugin not installed -----------------------------------
STUB_SKIP="harness-research" run_budget --ceiling 99999 --require-plugins
check_eq "an unreadable plugin cost under --require-plugins fails" 1 "$RC"
case "$OUT" in *"harness-research"*) ok "...and names the plugin it could not read" ;; *) bad "...and names the plugin it could not read" ;; esac

# ---- 4. stale install -------------------------------------------------------
echo
echo "stale install"
mk_cache 1.0.0     # older than the fixture's 9.9.9
run_budget --ceiling 99999 --require-plugins
check_eq "measuring an install older than the tree fails" 1 "$RC"
case "$OUT" in *STALE*) ok "...and says which side is old" ;; *) bad "...and says which side is old" ;; esac
mk_cache 9.9.9

# ---- 5. the published number is deliberately NOT fatal ----------------------
# Pinned as a decision: the figure depends on the estimator, so a mismatch is
# news rather than a defect. Assert it warns and does not fail, or the next
# person "fixes" it into a gate that goes red on someone else's release.
echo
echo "published figure"
publish 1
run_budget --ceiling 99999 --require-plugins
check_eq "a wrong published number warns rather than fails" 0 "$RC"
case "$OUT" in *warn*) ok "...and says so on the warn line" ;; *) bad "...and says so on the warn line" ;; esac
case "$OUT" in *FAIL*) bad "...and does not print FAIL" ;; *) ok "...and does not print FAIL" ;; esac

# ---- 6. the ceiling is the gate ---------------------------------------------
echo
echo "ceiling"
run_budget --ceiling 99999
publish "$(worst_of)"
run_budget --ceiling 1 --require-plugins
check_eq "over the ceiling fails" 1 "$RC"
case "$OUT" in *"over the ceiling"*) ok "...and says what to do about it" ;; *) bad "...and says what to do about it" ;; esac

summary
exit $?

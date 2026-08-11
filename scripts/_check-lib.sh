#!/bin/bash
# _check-lib.sh — the assert half shared by the repo-only verifiers.
#
# Sourced, never executed. The shipped _verify-lib.sh carries two halves: the
# hook runner (verify_begin / run_hook — an env -i sandbox around a hook file)
# and the assert half (_pass / _fail and the counters). Repo-only scripts need
# only the second, and before this file existed each of them re-rolled it —
# four hand-written copies with two *incompatible* helpers both named check():
# verify-install's took an exit code, verify-context-budget's took two strings.
# Same name, different contract, same directory.
#
# This sources the shipped lib and names the two contracts apart instead of
# merging them. It deliberately does NOT split the shipped file: a split ships
# a new sibling under plugins/harness-core/scripts/, which forces a version
# bump and hands a stale plugin cache a source line pointing at a file it does
# not have.
#
# PROTOCOL — load-bearing output format. The literal summary line
#     `  N / M passed`
# is parsed by scripts/verify-check-total.sh (the published check total) and
# by scripts/verify-inventory.sh (the installer assertion count). Reword it
# and the published totals go quietly wrong. The per-case lines
# `  PASS  <name>` / `  FAIL  <name>` are the same shape the hook verifiers
# print, which is what lets one parser read every transcript.
#
# The exception that stays duplicated: harness-slides' verify-check-claims.sh
# re-rolls these helpers and must keep doing so — plugin caches are separate
# and ../ references between them are forbidden, so it cannot reach either
# lib. That copy is the platform's tax, not debt.
#
# Requires bash 3.2. Usage:
#   . "$(cd "$(dirname "$0")" && pwd)/_check-lib.sh"
#   check_rc "name" "$?" ["detail"]        # exit-code contract: 0 passes
#   check_eq "name" expected actual        # string contract: equal passes
#   ok "name" / bad "name" ["detail"]      # direct
#   summary ["hint printed after failures"]; exit $?

_CHECK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_CHECK_LIB_DIR/../plugins/harness-core/scripts/_verify-lib.sh"

ok()  { _pass "$1"; }
bad() { _fail "$1" "${2:-}"; }

# The exit-code contract (verify-install's): second argument is a status,
# zero passes. `check "name" "$([ -e f ] && echo 0 || echo 1)"` reads on.
check_rc() { if [ "$2" -eq 0 ]; then _pass "$1"; else _fail "$1" "${3:-}"; fi; }

# The string contract (verify-context-budget's): expected then actual.
check_eq() { if [ "$2" = "$3" ]; then _pass "$1"; else _fail "$1" "expected $2, got $3"; fi; }

section() { printf '\n--- %s\n' "$1"; }

# Like the shipped verify_summary, but RETURNS instead of exiting — two of the
# four consumers have work after their summary, and a library that exits is a
# library that ends scripts by surprise. The printing itself is delegated to
# the shipped _summary_print so there is exactly one copy of the format.
# Optional argument: a hint line printed after the failure list
# (verify-inventory's "fix the document…").
summary() {
  if _summary_print; then
    return 0
  fi
  if [ -n "${1:-}" ]; then
    echo
    echo "$1"
  fi
  return 1
}

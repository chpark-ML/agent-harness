#!/bin/bash
# _verify-lib.sh — shared harness for the verify-<hook>.sh runners.
#
# Sourced, never executed. The leading underscore keeps it out of the
# dispatcher's `verify-*.sh` glob, so adding a helper here does not add a
# phantom verifier.
#
# Hook paths are given relative to the plugin root, one level up from this
# directory. The plugin cache is a faithful copy of the source tree, so the same
# resolution works from either.
#
# Usage:
#   . "$(dirname "$0")/_verify-lib.sh"
#   verify_begin secret-scrubber hooks/secret-scrubber.sh
#   run_case "benign command → allow" 0 '{"tool_name":"Bash",...}'
#   run_hook '{"tool_name":"Bash",...}' HARNESS_LARGE_FILE_BYTES=1
#   expect "exit code" 2 "$RC"
#   expect_match "names the file" "$ERR" "big.bin"
#   verify_summary
#
# Hooks run under `env -i` with only PATH, HOME and LC_ALL set, so a case
# cannot pass by accident because of something in the developer's shell. Extra
# VAR=value arguments are appended to that environment.
#
# Requires bash 3.2 — no associative arrays, no mapfile.

PASS=0
FAIL=0
SKIP=0
SKIPPED_NAMES=""
FAILED_NAMES=""
RC=0
OUT=""
ERR=""
PATH_SAVE="$PATH"

# The verifier's own jq calls need the same normalisation the hooks do: jq on
# Windows writes CRLF and `$(...)` keeps the CR, so `verify-install` read every
# manifest path back with a trailing byte and reported the files it had just
# installed as missing. Repo-only verifiers get this too, via _check-lib.sh.
jq() { local rc; command jq "$@" | tr -d '\r'; rc=${PIPESTATUS[0]}; return "$rc"; }
# Run hooks under the same interpreter as the verifier, so invoking the
# dispatcher with /bin/bash actually exercises the bash 3.2 floor end to end.
BASH_SAVE="${BASH:-bash}"

verify_begin() {
  VERIFY_NAME="$1"
  local rel="$2"
  local dir root
  dir="$(cd "$(dirname "$0")" && pwd)"
  root="$(cd "$dir/.." && pwd)"
  HOOK="$root/$rel"

  if [ ! -f "$HOOK" ]; then
    echo "verify-$VERIFY_NAME: hook not found at $HOOK" >&2
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "verify-$VERIFY_NAME: jq not installed — cannot verify hook behaviour." >&2
    exit 1
  fi

  WORK="$(mktemp -d)" || { echo "verify-$VERIFY_NAME: mktemp failed" >&2; exit 1; }
  trap 'rm -rf "$WORK"' EXIT
  CASE_CWD="$WORK"

  echo "=== $VERIFY_NAME verification ==="
  echo "Hook: $HOOK"
  echo

  # Every hook that parses stdin with jq must normalise its line endings, and
  # this is asserted here rather than in one verifier so that a new hook cannot
  # arrive without it. The defect it guards is the quiet kind: on Windows a
  # captured value keeps a trailing CR, substring matches go on working, exact
  # comparisons stop, and the guard permits what it exists to block.
  if grep -q 'jq -r' "$HOOK"; then
    if grep -q '^jq() { local rc; command jq' "$HOOK"; then
      _pass "normalises jq's line endings before comparing"
    else
      _fail "normalises jq's line endings before comparing" \
            "no jq wrapper: a captured value keeps its CR on Windows"
    fi
  fi

}

# run_hook <json> [VAR=value ...] — sets RC, OUT, ERR.
run_hook() {
  local input="$1"; shift
  printf '%s' "$input" > "$WORK/.stdin"
  ( cd "$CASE_CWD" 2>/dev/null \
      && env -i PATH="$PATH_SAVE" HOME="$WORK" LC_ALL=C "$@" "$BASH_SAVE" "$HOOK" ) \
    < "$WORK/.stdin" > "$WORK/.stdout" 2> "$WORK/.stderr"
  RC=$?
  OUT="$(cat "$WORK/.stdout")"
  ERR="$(cat "$WORK/.stderr")"
}

_pass() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
_fail() {
  FAIL=$((FAIL + 1))
  FAILED_NAMES="$FAILED_NAMES$1
"
  printf '  FAIL  %s\n' "$1"
  [ -n "${2:-}" ] && printf '        %s\n' "$2"
  return 0
}

# skip_case <name> <why> — for a case whose *premise* the platform cannot build,
# never for one that is merely inconvenient. Counted and named in the summary
# rather than dropped: a case that quietly stops running is a case that stopped
# guarding, and the total would go on claiming it ran.
skip_case() {
  SKIP=$((SKIP + 1))
  SKIPPED_NAMES="$SKIPPED_NAMES$1 ($2)
"
  printf '  SKIP  %s -- %s\n' "$1" "$2"
  return 0
}

# symlinks_supported — does `ln -s` on this platform actually make a symlink?
#
# Git Bash without winsymlinks exits 0 and leaves a *copy*, so the usual
# `ln -s ... || skip` idiom cannot see the problem: the command succeeded, and
# the case then quietly tests a regular file. Ask the filesystem what it got
# rather than asking ln whether it worked. Cached, because cases call it.
symlinks_supported() {
  if [ -z "${_SYMLINKS_OK:-}" ]; then
    _sym_probe="$WORK/.symprobe"
    rm -rf "$_sym_probe"; mkdir -p "$_sym_probe"
    : > "$_sym_probe/target"
    if ln -s "$_sym_probe/target" "$_sym_probe/link" 2>/dev/null && [ -L "$_sym_probe/link" ]; then
      _SYMLINKS_OK=yes
    else
      _SYMLINKS_OK=no
    fi
    rm -rf "$_sym_probe"
  fi
  [ "$_SYMLINKS_OK" = yes ]
}

# expect <name> <expected> <actual>
expect() {
  if [ "$2" = "$3" ]; then _pass "$1"; else _fail "$1" "expected '$2', got '$3'"; fi
}

# expect_match <name> <haystack> <needle>
expect_match() {
  case "$2" in
    *"$3"*) _pass "$1" ;;
    *) _fail "$1" "expected to contain '$3', got: $(printf '%s' "$2" | head -2 | tr '\n' ' ')" ;;
  esac
}

# expect_absent <name> <haystack> <needle> — the inverse of expect_match. For
# output a hook is supposed to leave out, which is not the same as no output at
# all: a blocking case still writes its block message to stderr.
expect_absent() {
  case "$2" in
    *"$3"*) _fail "$1" "expected NOT to contain '$3'" ;;
    *) _pass "$1" ;;
  esac
}

# expect_empty <name> <value>
expect_empty() {
  if [ -z "$2" ]; then _pass "$1"; else _fail "$1" "expected no output, got: $(printf '%s' "$2" | head -2 | tr '\n' ' ')"; fi
}

# run_case <name> <expected_exit> <json> [VAR=value ...] — the common shape.
run_case() {
  local name="$1" expected="$2" input="$3"; shift 3
  run_hook "$input" "$@"
  if [ "$RC" -eq "$expected" ]; then
    _pass "$name"
  else
    _fail "$name" "expected exit $expected, got $RC$([ -n "$ERR" ] && printf ' | stderr: %s' "$(printf '%s' "$ERR" | head -1)")"
  fi
}

# The one printer of the summary block. verify_summary exits on top of it;
# scripts/_check-lib.sh's summary returns on top of it. Keeping a single body
# is what stops the two front doors from drifting apart — the literal line
# `  N / M passed` it prints is parsed by scripts/verify-check-total.sh and
# scripts/verify-inventory.sh, so this function IS the published-total format.
_summary_print() {
  local total=$((PASS + FAIL))
  echo
  echo "=== Summary ==="
  echo "  $PASS / $total passed"
  if [ "$SKIP" -gt 0 ]; then
    echo "  $SKIP skipped (this platform cannot build the premise):"
    printf '%s' "$SKIPPED_NAMES" | while IFS= read -r n; do
      [ -n "$n" ] && echo "    - $n"
    done
  fi
  if [ "$FAIL" -gt 0 ]; then
    echo "  $FAIL failed:"
    printf '%s' "$FAILED_NAMES" | while IFS= read -r n; do
      [ -n "$n" ] && echo "    - $n"
    done
    return 1
  fi
  return 0
}

verify_summary() {
  if _summary_print; then exit 0; else exit 1; fi
}

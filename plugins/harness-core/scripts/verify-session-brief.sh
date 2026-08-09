#!/bin/bash
# verify-session-brief.sh — behavioural verification of the session-brief hook.
#
# This hook is informational: it must never block a session (exit 0 always) and
# must stay inside its output budget, because its stdout is prepended to every
# session's context.
#
# Run from any cwd:  bash scripts/verify-session-brief.sh

set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/_verify-lib.sh"
verify_begin session-brief hooks/session-brief.sh

mkrepo() {
  local dir="$1" branch="$2" n=1
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" symbolic-ref HEAD "refs/heads/$branch"
  git -C "$dir" config user.email verify@example.invalid
  git -C "$dir" config user.name verify
  while [ "$n" -le 6 ]; do
    printf 'v%s\n' "$n" > "$dir/file.txt"
    git -C "$dir" add file.txt
    git -C "$dir" commit -q -m "commit number $n"
    n=$((n + 1))
  done
}

mkdir -p "$WORK/plain"
mkrepo "$WORK/clean" main
mkrepo "$WORK/dirty" main
printf 'uncommitted\n' > "$WORK/dirty/file.txt"
printf 'new\n' > "$WORK/dirty/extra.txt"
mkrepo "$WORK/detached" main
git -C "$WORK/detached" checkout -q --detach HEAD

# A repo with a real upstream, one commit ahead of it, and a dirty tree. This
# is the only fixture that reaches the upstream block, and it is also the
# worst case for the output budget: every optional line renders at once.
git init --bare -q "$WORK/remote.git"
mkrepo "$WORK/ahead" main
git -C "$WORK/ahead" remote add origin "$WORK/remote.git"
git -C "$WORK/ahead" push -q -u origin main
printf 'v7\n' > "$WORK/ahead/file.txt"
git -C "$WORK/ahead" add file.txt
git -C "$WORK/ahead" commit -q -m "commit number 7"
printf 'uncommitted\n' > "$WORK/ahead/file.txt"

# --- outside a repo ---------------------------------------------------------

CASE_CWD="$WORK/plain"
run_hook '{}'
expect "not a git repo → exit 0" 0 "$RC"
expect_empty "not a git repo → silent" "$OUT"

# --- clean repo -------------------------------------------------------------

CASE_CWD="$WORK/clean"
run_hook '{}'
expect "clean repo → exit 0" 0 "$RC"
expect_match "names the branch" "$OUT" "branch: main"
expect_match "lists recent commits" "$OUT" "commit number 6"
expect_absent "clean repo omits the uncommitted line" "$OUT" "uncommitted:"
expect_absent "no upstream configured → no upstream line" "$OUT" "upstream"

# --- output budget ----------------------------------------------------------
# Ten lines is the stated cap. This runs on every start, resume, clear and
# compact, so a regression here is a tax on every future session.
lines="$(printf '%s\n' "$OUT" | grep -c .)"
if [ "$lines" -le 10 ]; then
  _pass "output stays within the 10-line budget ($lines lines)"
else
  _fail "output stays within the 10-line budget" "got $lines lines"
fi

# --- dirty repo -------------------------------------------------------------

CASE_CWD="$WORK/dirty"
run_hook '{}'
expect "dirty repo → exit 0" 0 "$RC"
expect_match "reports uncommitted changes" "$OUT" "uncommitted: 2"

lines="$(printf '%s\n' "$OUT" | grep -c .)"
if [ "$lines" -le 10 ]; then
  _pass "dirty repo also stays within the budget ($lines lines)"
else
  _fail "dirty repo also stays within the budget" "got $lines lines"
fi

# --- detached HEAD ----------------------------------------------------------

CASE_CWD="$WORK/detached"
run_hook '{}'
expect "detached HEAD → exit 0" 0 "$RC"
expect_match "detached HEAD is labelled" "$OUT" "detached"

# --- the budget is about context, so width counts too ------------------------
# The line-count cap is blind to a 170-column subject that wraps to three rows.
mkrepo "$WORK/wide" main
printf 'v9\n' > "$WORK/wide/file.txt"
git -C "$WORK/wide" add file.txt
git -C "$WORK/wide" commit -q -m "$(printf 'a very long subject %.0s' 1 2 3 4 5 6 7 8 9 10)"

CASE_CWD="$WORK/wide"
run_hook '{}'
expect "long subject → exit 0" 0 "$RC"
widest="$(printf '%s\n' "$OUT" | awk '{ if (length($0) > m) m = length($0) } END { print m+0 }')"
if [ "$widest" -le 80 ]; then
  _pass "no line exceeds 80 columns ($widest)"
else
  _fail "no line exceeds 80 columns" "widest line is $widest"
fi

# --- upstream divergence, and the budget's worst case ------------------------

CASE_CWD="$WORK/ahead"
run_hook '{}'
expect "repo with an upstream → exit 0" 0 "$RC"
expect_match "reports the upstream ref" "$OUT" "upstream(origin/main)"
expect_match "reports the divergence" "$OUT" "ahead 1 / behind 0"

# Every optional line renders here, including the not-installed notice. The
# ceiling was 10 and is 11 because of that notice, which is a deliberate
# exception rather than headroom: it appears only while the harness is missing
# from the project, and it extinguishes itself the moment somebody acts on it.
# The steady state is pinned separately, two cases below, and is still 10.
lines="$(printf '%s\n' "$OUT" | grep -c .)"
if [ "$lines" -le 11 ]; then
  _pass "worst case (upstream + dirty + 5 commits + notice) fits the budget ($lines lines)"
else
  _fail "worst case (upstream + dirty + 5 commits + notice) fits the budget" "got $lines lines"
fi

# --- the not-installed notice, and its absence --------------------------------
# A brief that nagged about the install in every session of an installed
# project would be tuned out, and the rest of the brief with it.

expect_match "an uninstalled project is told so" "$OUT" "project rules not installed"
expect_match "and told the command that fixes it" "$OUT" "harnessctl init --scope project"

mkdir -p "$WORK/ahead/.claude"
printf '{"modules":["dev"]}\n' > "$WORK/ahead/.claude/harness-manifest.json"
CASE_CWD="$WORK/ahead"
run_hook '{}'
expect "an installed project → exit 0" 0 "$RC"
expect_absent "and says nothing about the install" "$OUT" "project rules not installed"
lines="$(printf '%s\n' "$OUT" | grep -c .)"
if [ "$lines" -le 10 ]; then
  _pass "the steady state is still within ten lines ($lines)"
else
  _fail "the steady state is still within ten lines" "got $lines lines"
fi

verify_summary

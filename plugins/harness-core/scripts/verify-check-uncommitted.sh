#!/bin/bash
# verify-check-uncommitted.sh — behavioural verification of the
# check-uncommitted Stop hook.
#
# The load-bearing property is what it stays QUIET about. A Stop hook that
# speaks on every turn gets tuned out, and then it is not a guard rail, it is
# noise with a rail-shaped comment above it.
#
# Run from any cwd:  bash scripts/verify-check-uncommitted.sh

set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/_verify-lib.sh"
verify_begin check-uncommitted hooks/check-uncommitted.sh

mkrepo() {
  local dir="$1" branch="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" symbolic-ref HEAD "refs/heads/$branch"
  git -C "$dir" config user.email verify@example.invalid
  git -C "$dir" config user.name verify
  printf 'v1\n' > "$dir/file.txt"
  git -C "$dir" add file.txt
  git -C "$dir" commit -q -m "initial"
}
dirty() { printf 'changed\n' > "$1/file.txt"; }

# Point origin/HEAD at a branch, without a network. This is the lookup the hook
# prefers, and it is the one that runs in any real cloned repo — the plain
# `git init` fixtures below can only ever reach the main|master fallback.
set_origin_head() {
  git -C "$1" remote add origin "file://$1" >/dev/null 2>&1
  git -C "$1" symbolic-ref "refs/remotes/origin/HEAD" "refs/remotes/origin/$2"
}

mkdir -p "$WORK/plain"
mkrepo "$WORK/main-clean" main
mkrepo "$WORK/main-dirty" main;   dirty "$WORK/main-dirty"
mkrepo "$WORK/master-dirty" master; dirty "$WORK/master-dirty"
mkrepo "$WORK/feat" main
git -C "$WORK/feat" checkout -q -b feat-add-parser
dirty "$WORK/feat"
mkrepo "$WORK/detached" main
dirty "$WORK/detached"
git -C "$WORK/detached" checkout -q --detach HEAD

# A repo whose remote says the default branch is `trunk`.
mkrepo "$WORK/trunk-default" trunk; set_origin_head "$WORK/trunk-default" trunk
dirty "$WORK/trunk-default"
# ...and the same repo sitting on a branch literally named `main`, which is
# NOT the default here. The name fallback would speak; the remote lookup must win.
mkrepo "$WORK/main-not-default" trunk; set_origin_head "$WORK/main-not-default" trunk
git -C "$WORK/main-not-default" checkout -q -b main
dirty "$WORK/main-not-default"

quiet_case() {
  local name="$1" dir="$2"
  CASE_CWD="$dir"
  run_hook '{}'
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    _pass "$name"
  else
    _fail "$name" "exit $RC, output: $(printf '%s' "$OUT" | head -1)"
  fi
}

# --- stays quiet ------------------------------------------------------------

quiet_case "outside a git repo → silent" "$WORK/plain"
quiet_case "default branch, clean tree → silent" "$WORK/main-clean"
quiet_case "feature branch with changes → silent (this is the intended place)" "$WORK/feat"
quiet_case "detached HEAD → silent" "$WORK/detached"
quiet_case "branch named 'main' when the remote says the default is 'trunk' → silent" "$WORK/main-not-default"

# A stale origin/HEAD — the normal state after an upstream master→main rename
# until someone runs `git remote set-head origin -a` — names a branch with no
# ref. Trusting it silenced the hook on the real default branch forever.
mkdir -p "$WORK/stale"
mkrepo "$WORK/stale" main
git -C "$WORK/stale" remote add origin "file://$WORK/stale" >/dev/null 2>&1
git -C "$WORK/stale" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master
dirty "$WORK/stale"

CASE_CWD="$WORK/stale"
run_hook '{}'
expect "stale origin/HEAD → still exit 0" 0 "$RC"
expect_match "stale origin/HEAD falls back to the name convention" "$OUT" "main"

# --- speaks up --------------------------------------------------------------

CASE_CWD="$WORK/main-dirty"
run_hook '{}'
expect "main with changes → still exit 0 (informational, never blocks)" 0 "$RC"
expect_match "main with changes → names the branch" "$OUT" "main"
expect_match "main with changes → names the file count" "$OUT" "1 건"
expect_match "main with changes → names the branch convention" "$OUT" "feat,fix,chore"

CASE_CWD="$WORK/master-dirty"
run_hook '{}'
expect "master with changes → exit 0" 0 "$RC"
expect_match "master is recognised as a default branch too" "$OUT" "master"

CASE_CWD="$WORK/trunk-default"
run_hook '{}'
expect "remote-declared default branch → exit 0" 0 "$RC"
expect_match "the default branch comes from origin/HEAD, not from its name" "$OUT" "trunk"

# --- the notice tracks the actual count -------------------------------------

printf 'another\n' > "$WORK/main-dirty/second.txt"
CASE_CWD="$WORK/main-dirty"
run_hook '{}'
expect_match "count follows the working tree" "$OUT" "2 건"

verify_summary

#!/bin/bash
# check-uncommitted — at end of turn, notice work piling up on the default
# branch.
#
# The workflow rule says a change destined for review lives on a
# {feat,fix,chore}-<slug> branch, and the longer work sits on main the more
# expensive the move becomes: the diff grows past one reviewable unit and has
# to be split by hand. This is the cheap reminder at the moment it is cheap.
#
# It fires only on the default branch. An unconditional "you have uncommitted
# changes" would fire on every turn of every session and be tuned out inside a
# day, which is worse than not having it.
#
# Informational: always exits 0, never blocks a turn.

set -uo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
branch="$(git -C "$root" branch --show-current 2>/dev/null)" || exit 0
[ -n "$branch" ] || exit 0

# The default branch as the remote reports it, falling back to the usual names
# when there is no remote HEAD to ask.
default="$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
# A stale origin/HEAD — the normal state after an upstream master→main rename,
# until someone runs `git remote set-head origin -a` — names a branch that no
# longer exists locally. Trusting it silences the hook on the real default
# branch forever, so treat an unresolvable name as no answer at all.
if [ -n "$default" ] \
   && ! git -C "$root" show-ref --verify --quiet "refs/heads/$default" \
   && ! git -C "$root" show-ref --verify --quiet "refs/remotes/origin/$default"; then
  default=""
fi
if [ -z "$default" ]; then
  case "$branch" in
    main|master) default="$branch" ;;
    *) exit 0 ;;
  esac
fi
[ "$branch" = "$default" ] || exit 0

dirty="$(git -C "$root" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
[ "${dirty:-0}" -gt 0 ] || exit 0

echo "[check-uncommitted] ${default} 에 미커밋 변경 ${dirty} 건. 리뷰 단위가 될 작업이면 지금 {feat,fix,chore}-<slug> 브랜치로 옮기는 편이 쌉니다 (단발 typo·탐색이면 무시)."
exit 0

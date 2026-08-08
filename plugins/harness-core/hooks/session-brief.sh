#!/bin/bash
# session-brief — inject a compact repo-state brief at session start.
#
# stdout becomes session context. This runs on every start, resume, clear and
# compact, so verbosity here is a recurring tax paid on every session of the
# project's life; the output is deliberately capped at roughly ten lines and
# carries only facts the model would otherwise spend a tool call to learn.
#
# Informational: always exits 0, never blocks a session.

set -uo pipefail

# Resolve the toplevel once and address git through it, matching the other
# informational hook — the session may start in a subdirectory.
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$root" ] || exit 0

branch="$(git -C "$root" branch --show-current 2>/dev/null)"
[ -z "$branch" ] && branch="(detached: $(git -C "$root" rev-parse --short HEAD 2>/dev/null))"

echo "[session-brief] repo state"
echo "- branch: ${branch}"

upstream="$(git -C "$root" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
if [ -n "$upstream" ]; then
  counts="$(git -C "$root" rev-list --left-right --count "HEAD...$upstream" 2>/dev/null || true)"
  if [ -n "$counts" ]; then
    ahead="$(echo "$counts" | awk '{print $1}')"
    behind="$(echo "$counts" | awk '{print $2}')"
    if [ "$ahead" != "0" ] || [ "$behind" != "0" ]; then
      echo "- upstream(${upstream}): ahead ${ahead} / behind ${behind}"
    fi
  fi
fi

dirty="$(git -C "$root" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
[ "$dirty" != "0" ] && echo "- uncommitted: ${dirty} files"

echo "- recent commits:"
# Truncate the subject so a rendered line fits 80 columns (2 indent + 7 hash +
# 1 space + 66 = 76). The budget is about how much context this costs, and a
# 170-column subject wraps to three rows however few logical lines it is.
git -C "$root" log -5 --pretty='  %h %<(66,trunc)%s' 2>/dev/null

exit 0

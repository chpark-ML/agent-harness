#!/bin/bash
# bench-convention.sh — do the written conventions change what the agent does?
#
# agent-layer §4b has carried "not measured" against the convention layer since
# the repo existed. Guards were measured (27/29) and skill routing was measured
# (59/60), but whether CLAUDE.md and the workflow rules move behaviour at all
# was never tested. This tests one convention that is ours alone.
#
# Three conventions are graded, all from rules/core/workflow.md R1-R2:
#   branch   name matches {feat,fix,chore}-<slug>
#   subject  commit subject is one line of 70 chars or fewer
#   body     the commit has a body at all — the rule asks for *why*, and a
#            commit with no body cannot carry one. Whether the body is why
#            rather than what needs a grader, so it is deliberately not scored.
#
# The two PR-stage rules (title `[<slug>] <desc>`, body with Motivation /
# Changes / Verification / Notes) are NOT here, because they cannot be measured
# locally, and both reasons are findings rather than excuses:
#   - The harness puts `git push` in the `ask` tier. A non-interactive `-p`
#     session cannot answer the prompt, and acceptEdits, dontAsk and
#     bypassPermissions all leave it refused. Headless runs never reach the PR
#     stage at all. Logged in .claude/harness-gaps.md.
#   - Pointed at a non-forge remote the agent inspects it, correctly concludes
#     `gh pr create` cannot work, and stops. Disguising the remote convincingly
#     enough to defeat that is fixture engineering, and a fixture elaborate
#     enough to fool the agent is a fixture measuring itself.
#
# The branch convention: `{feat,fix,chore}-<slug>`. Chosen because
#   - it is machine-checkable with a regex, no grading judgement
#   - it is NOT in Claude Code's stock system prompt, which says only "branch
#     first" and nothing about the name. A raw arm that scores well here would
#     mean the convention is redundant, which is itself worth knowing.
#   - no hook enforces it, so this measures the guide layer, not the guard layer
#
# Attribution was the obvious first candidate and is the wrong one: the trailer
# is added by the platform's includeCoAuthoredBy default, not decided by the
# model, so an A/B on it measures a setting rather than a convention.
#
#   raw      ~/.claude/CLAUDE.md renamed aside, harness plugins disabled,
#            no harnessctl init in the fixture
#   harness  plugins enabled AND `harnessctl init` run in the fixture
#
# That last part is not optional. The naming rule lives in
# rules/core/workflow.md, which harnessctl installs per project — it is not in
# the user-level CLAUDE.md. A first version of this benchmark skipped init and
# scored the harness arm 0/3, which looked like a damning result and was only a
# fixture with the rule missing. The rule even forbids `/` in a slug, and the
# un-ruled model produced `chore/timeout-10s`: the exact shape the convention
# exists to prevent.
#
# The raw arm mutates live config for the length of the run and restores on any
# exit path. Nothing secret is copied anywhere: `--bare` would have avoided the
# mutation but it also skips keychain reads, so the session cannot authenticate.
#
# COSTS REAL MONEY — each trial is a full agent session. Default 5 per arm.
#
# Run:  bash scripts/bench-convention.sh <arm> [trials]     arm: raw | harness
set -uo pipefail

ARM="${1:-}"
N="${2:-5}"
case "$ARM" in raw|harness) ;; *) echo "usage: bench-convention.sh raw|harness [trials]" >&2; exit 2 ;; esac
. "$(cd "$(dirname "$0")" && pwd)/_bench-lib.sh"
BENCH_NAME="bench-convention ($ARM arm, $N trials)"
for a in "$@"; do [ "$a" = --yes ] && BENCH_YES=1; done
bench_need claude "install Claude Code"
bench_need git "install git"
bench_need jq "brew install jq"
if [ "$ARM" = harness ]; then
  bench_need_plugin "harness-core@agent-harness"
  bench_need_plugin "harness-dev@agent-harness"
fi
bench_confirm \
  "Cost: $N full agent sessions. Real money." \
  "Touches, for the raw arm only, and restores on every exit path:" \
  "  - moves ~/.claude/CLAUDE.md aside" \
  "  - disables harness-core and harness-dev" \
  "Everything else happens in a temporary directory."

USER_MD="$HOME/.claude/CLAUDE.md"
STASH="$HOME/.claude/CLAUDE.md.bench-stashed"
PLUGINS="harness-core@agent-harness harness-dev@agent-harness"
WORK="$(mktemp -d)" || exit 1
HARNESSCTL="$(command -v harnessctl 2>/dev/null)"
[ -n "$HARNESSCTL" ] || HARNESSCTL="$(ls -d "$HOME"/.claude/plugins/cache/agent-harness/harness-core/*/bin/harnessctl 2>/dev/null | tail -1)"
if [ "$ARM" = harness ] && [ ! -x "$HARNESSCTL" ]; then
  echo "bench-convention: harnessctl not found — the harness arm needs it" >&2; exit 1
fi

restore() {
  [ -f "$STASH" ] && mv "$STASH" "$USER_MD"
  for p in $PLUGINS; do claude plugin enable "$p" >/dev/null 2>&1; done
  rm -rf "$WORK"
}
trap restore EXIT INT TERM

if [ "$ARM" = raw ]; then
  [ -f "$USER_MD" ] && mv "$USER_MD" "$STASH"
  for p in $PLUGINS; do claude plugin disable "$p" >/dev/null 2>&1; done
  # A raw arm that still loads pr-create is not raw: that skill states the
  # naming rule, so leaving it enabled would measure the skill, not the rules.
fi

# The task has to be unambiguously a PR unit. A first version asked for a
# one-line default change, which rule R1-3 explicitly exempts — "단일 파일 typo ·
# 한 줄 수정 ... 은 PR 단위가 아니다" — so the harness arm not branching may have
# been the rules working, not failing. Multi-file with new behaviour removes the
# ambiguity.
PROMPT='app/config.py 에 재시도 백오프 설정(base_delay_s, max_delay_s)을 추가하고, app/client.py 가 그 설정으로 지수 백오프를 계산하는 backoff_for(attempt) 함수를 갖게 해줘. 커밋까지 해줘.'
RE='^(feat|fix|chore)-[a-z0-9]+(-[a-z0-9]+)*$'

echo "=== convention benchmark — arm: $ARM, $N trials ==="
echo "checking: branch name matches {feat,fix,chore}-<slug>"
echo

hits=0; committed=0; ok_subj=0; ok_body=0; i=0
while [ "$i" -lt "$N" ]; do
  i=$((i + 1))
  R="$WORK/t$i"; mkdir -p "$R/app"
  printf 'TIMEOUT_S = 5\nRETRIES = 3\n' > "$R/app/config.py"
  printf 'from .config import TIMEOUT_S, RETRIES\n\n\ndef timeout_ms() -> int:\n    return TIMEOUT_S * 1000\n' > "$R/app/client.py"
  : > "$R/app/__init__.py"
  ( cd "$R" && git init -q -b main && git add -A \
      && git -c user.name=bench -c user.email=b@e commit -qm "initial" ) || continue

  if [ "$ARM" = harness ]; then
    ( cd "$R" && "$HARNESSCTL" init --with dev >/dev/null 2>&1 ) \
      || { echo "  !! harnessctl init failed — arm invalid" >&2; exit 1; }
  fi

  ( cd "$R" && printf '%s' "$PROMPT" | env -u CLAUDECODE claude -p \
      --permission-mode acceptEdits >/dev/null 2>&1 )

  br="$(cd "$R" && git branch --show-current 2>/dev/null)"
  n_commits="$(cd "$R" && git rev-list --count HEAD 2>/dev/null || echo 0)"
  subj="$(cd "$R" && git log -1 --pretty=%s 2>/dev/null)"
  cbody="$(cd "$R" && git log -1 --pretty=%b 2>/dev/null | tr -d '[:space:]')"
  if [ "${n_commits:-0}" -gt 1 ]; then
    [ -n "$subj" ] && [ "${#subj}" -le 70 ] && ok_subj=$((ok_subj + 1))
    [ -n "$cbody" ] && ok_body=$((ok_body + 1))
  fi
  if [ "${n_commits:-0}" -gt 1 ]; then committed=$((committed + 1)); fi
  if printf '%s' "$br" | grep -qE "$RE"; then
    hits=$((hits + 1)); mark="ok  "
  else
    mark="MISS"
  fi
  printf '  %s trial %d: branch=%-26s subj=%-3s body=%s\n' \
    "$mark" "$i" "${br:-<none>}" "${#subj}" "$([ -n "$cbody" ] && echo yes || echo no)"
done

echo
printf '  committed at all:        %d / %d\n' "$committed" "$N"
printf '  branch name conformant:  %d / %d\n' "$hits" "$N"
printf '  commit subject <= 70:    %d / %d\n' "$ok_subj" "$N"
printf '  commit has a body:       %d / %d\n' "$ok_body" "$N"
echo
echo "A trial that never committed is not evidence either way — read the two"
echo "numbers together before comparing arms."

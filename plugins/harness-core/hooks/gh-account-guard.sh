#!/bin/bash
# gh-account-guard — block a push or a pull request made as the wrong GitHub
# account.
#
# catches  git push · gh pr create · gh pr merge, when the active gh account is
#          not the one this repository declared
# scope    PreToolUse, Bash. Silent until an expected account is declared.
# bypass   HARNESS_GH_ACCOUNT=<login> <command>, scoped to one shell
#
# `gh` installs itself as git's credential helper, so `git push` authenticates
# as whatever account is *active*. Move between two accounts with
# `gh auth switch` and two things follow: a pull request opens under the wrong
# identity while nothing fails, or a push is refused with a 403 that does not
# say why.
#
# Configuration, first match wins — deliberately not the union protected-paths
# uses. A union would mean "either account is fine", which weakens the guard on
# purpose; and one account being normal with specific repositories as the
# exception is the shape the problem actually has.
#   1. HARNESS_GH_ACCOUNT
#   2. <project>/.claude/gh-account.txt
#   3. <user config>/gh-account.txt      ($CLAUDE_CONFIG_DIR, else ~/.claude)
#
# There is no separate off switch. The absent file is the off switch, the same
# stance protected-paths takes: a generic harness cannot guess which account a
# repository wants, and a guard with an invented default blocks the wrong thing
# and teaches people to ignore it.
#
# The commit author is NOT checked. `git config user.email` is a separate knob
# from the token, and the two can disagree without either being wrong here.
#
# One gap is accepted, and it runs in the permissive direction: a push hidden in
# a command substitution — `echo $(git push)` — is not caught, because the
# segment begins with `echo`. This guards against a mistake, not against someone
# working around it.
#
# Exit: 0 allow · 2 block.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "gh-account-guard: jq not found — hook disabled. Install jq to enable." >&2
  exit 0
fi

payload="$(cat)"
[ -n "$payload" ] || exit 0

tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ "$tool" = "Bash" ] || exit 0
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$cmd" ] || exit 0

# --- does this command act under an identity? -------------------------------
#
# Split on the shell's command separators and require the match at the START of
# a segment. ai-attribution-guard matches the same subcommands with a
# deliberately unanchored regex, and its document explains why that is safe
# there: "a wide gate is harmless — a command with no attribution passes it and
# exits 0 anyway." That reasoning does not transfer. Here the gate IS the block,
# so `git commit -m "... git push ..."` would be a false positive, and a check
# that cries wolf gets switched off.
#
# The optional-option part is borrowed from that hook, which learned it after
# `git -C <repo> commit` slipped past a simpler pattern. The difference is that
# it folds the command to lowercase first and so needs only `-c`; this hook does
# not fold, so the option-with-an-argument alternative has to accept both cases
# or `git -C /elsewhere push` walks straight through.
opts='([[:space:]]+(-[cC][[:space:]]+[^[:space:]]+|--[a-zA-Z][^[:space:]]*|-[a-zA-Z]+))*'
caught=""
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"        # ltrim
  case "$seg" in
    git*|gh*) ;;
    *) continue ;;
  esac
  if printf '%s' "$seg" | grep -qE "^git${opts}[[:space:]]+push([[:space:]]|$)"; then
    caught="$seg"; break
  fi
  if printf '%s' "$seg" | grep -qE "^gh${opts}[[:space:]]+pr[[:space:]]+(create|merge)([[:space:]]|$)"; then
    caught="$seg"; break
  fi
done <<EOF
$(printf '%s' "$cmd" | tr ';|&\n' '\n\n\n\n')
EOF
[ -n "$caught" ] || exit 0

# --- what does this repository expect? --------------------------------------
PROJECT_CONFIG="${CLAUDE_PROJECT_DIR:-.}/.claude"
USER_CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# First non-comment, non-blank line. One account, not a list.
read_account() {
  [ -f "$1" ] || return 1
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"    # ltrim
    line="${line%"${line##*[![:space:]]}"}"    # rtrim
    if [ -n "$line" ]; then printf '%s\n' "$line"; return 0; fi
  done < "$1"
  return 1
}

expected=""
expected_from=""
if [ -n "${HARNESS_GH_ACCOUNT:-}" ]; then
  expected="$HARNESS_GH_ACCOUNT"
  expected_from="HARNESS_GH_ACCOUNT"
elif expected="$(read_account "$PROJECT_CONFIG/gh-account.txt")"; then
  expected_from="$PROJECT_CONFIG/gh-account.txt"
elif expected="$(read_account "$USER_CONFIG/gh-account.txt")"; then
  expected_from="$USER_CONFIG/gh-account.txt"
fi
[ -n "$expected" ] || exit 0

exit 0   # Task 2 replaces this line with the comparison.

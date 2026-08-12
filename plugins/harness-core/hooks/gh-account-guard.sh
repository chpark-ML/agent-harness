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

if ! type -P jq >/dev/null 2>&1; then
  echo "gh-account-guard: jq not found — hook disabled. Install jq to enable." >&2
  exit 0
fi

# jq on Windows writes CRLF. `$(...)` strips the trailing newline and leaves the
# CR, so every captured value ends in a stray byte: exact comparisons fail while
# substring matches keep working, which means the guard goes quiet instead of
# going wrong. `verify-gh-account-guard` caught it as eight failures in a hook
# that was correct; in the field it is a push that should have been blocked.
#
# Normalised once here rather than at each call site, and unconditionally --
# `tr -d '\r'` is a no-op on LF, whereas a Windows-only branch would be a line
# that only ever runs in one environment (CLAUDE.md section 4). PIPESTATUS keeps
# jq's own exit status, which `jq -e` and `jq empty` callers depend on.
jq() { local rc; command jq "$@" | tr -d '\r'; rc=${PIPESTATUS[0]}; return "$rc"; }

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

# Nothing declared is NOT the end any more — the owner of `origin` may say it
# for us. That is why gh is now asked even here, which is the one cost this
# inference adds: a repository that declares nothing used to leave at no charge.
# It is paid only on push and PR commands, a handful of times per session.

# --- who is active, and who else am I? --------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  echo "gh-account-guard: gh not found — hook disabled for this call." >&2
  exit 0
fi

# `--json hosts` without `--active`, so one call answers both questions: which
# account is active, and which accounts exist at all. Under --json gh exits 0
# regardless of any authentication issue (its own help says so), so the payload
# is read and the exit code never is.
#
# ~/.config/gh/hosts.yml would be free and offline, and was rejected: when
# GH_TOKEN or GITHUB_TOKEN is set, gh uses that token and `gh auth switch` has
# no effect, yet hosts.yml still names the old account. A guard about mistaken
# identity must not be confidently wrong exactly when identity is confused.
status="$(gh auth status --hostname github.com --json hosts 2>/dev/null || true)"
hosts='.hosts["github.com"] // []'
# Select on the `active` flag rather than taking [0]. With two accounts
# authenticated the first entry is simply the first, which is the whole
# situation this hook exists for.
active="$(printf '%s' "$status" | jq -r "$hosts | map(select(.active)) | .[0].login // empty" 2>/dev/null || true)"

# gh answered but named nobody. Not an identity mismatch — let git report the
# real problem. `state` is not consulted either: a broken token fails loudly on
# its own, and this hook only ever answers *which account*.
[ -n "$active" ] || exit 0

# --- nothing declared? then ask the remote -----------------------------------
#
# If the owner of `origin` is itself one of the accounts you are logged in as,
# it is one of your own namespaces and the expectation needs no configuration.
# An organisation owner matches no account, so inference stays quiet and the
# repository has to declare if it wants the guard — that is the deliberate
# degradation, not an oversight.
if [ -z "$expected" ]; then
  # `--push`, not the plain form. When a push URL is configured it is what
  # `git push` actually targets, and when it is not, git falls back to the fetch
  # URL — so this is strictly more correct with nothing to trade away.
  url="$(git -C "${CLAUDE_PROJECT_DIR:-.}" remote get-url --push origin 2>/dev/null || true)"

  # Parse the host, rather than asking whether the URL *contains* "github.com".
  # A substring test infers an owner from `git@notgithub.com:alice/repo` and
  # from `https://github.com.evil.io/alice/repo`, and if that owner happens to
  # be one of your accounts it blocks pushes to a host this hook has no business
  # judging. That is the cries-wolf direction, which is how guards get disabled.
  host=""; path=""
  case "$url" in
    *://*)                                  # scheme://[user@]host/owner/repo
      rest="${url#*://}"
      host="${rest%%/*}"; host="${host#*@}"
      path="${rest#*/}"
      ;;
    *:*)                                    # scp-like — [user@]host:owner/repo
      rest="${url#*@}"
      host="${rest%%:*}"
      path="${rest#*:}"
      ;;
  esac
  owner="${path%%/*}"

  if [ "$host" = "github.com" ] && [ -n "$owner" ]; then
    # GitHub logins are case-insensitive, so `github.com/ALICE/repo` and the
    # login `alice` are the same account. An exact comparison leaves the
    # expectation empty and lets the push through — failing open, silently.
    #
    # The expectation becomes gh's OWN spelling, not the URL's. Carrying the
    # URL's casing forward would only move the bug: `ALICE` against an active
    # `alice` would then mismatch and block, which is the same defect pointing
    # the other way.
    lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
    owner_lc="$(lower "$owner")"
    while IFS= read -r login; do
      [ -n "$login" ] || continue
      if [ "$(lower "$login")" = "$owner_lc" ]; then
        expected="$login"
        expected_from="the owner of remote origin"
        break
      fi
    done <<EOF
$(printf '%s' "$status" | jq -r "$hosts | .[].login" 2>/dev/null || true)
EOF
  fi
fi

[ -n "$expected" ] || exit 0
[ "$active" = "$expected" ] && exit 0

token_src="$(printf '%s' "$status" | jq -r "$hosts | map(select(.active)) | .[0].tokenSource // empty" 2>/dev/null || true)"
from=""
case "$token_src" in
  ""|keyring|oauth_token) ;;
  *) from="   (from $token_src)" ;;
esac

cat >&2 <<EOF
gh-account-guard: active GitHub account is "$active", but this repo expects "$expected".

  caught:   $caught
  active:   $active$from
  expected: $expected   ($expected_from)

Switch, then retry:     gh auth switch --user $expected
Or proceed as active:    HARNESS_GH_ACCOUNT=$active <command>

docs/hooks/gh-account-guard.md
EOF
exit 2

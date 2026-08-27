#!/bin/bash
# ai-attribution-guard — keep AI-authorship marks out of git history and GitHub.
#
# catches  commit / PR / issue commands carrying a Co-Authored-By: Claude
#          trailer, a generated-with footer, or the robot emoji
# scope    PreToolUse, Bash
# bypass   none by design; write the message without the attribution
#
# Blocks commit / PR / issue commands carrying:
#   - a `Co-Authored-By: Claude ...` (or `...@anthropic.com`) trailer
#   - a `🤖 Generated with [Claude Code]` footer
#   - a "Generated with Claude ..." line
#
# `includeCoAuthoredBy: false` in settings.json turns off the built-in trailer;
# this hook covers the other route, a message the model composed by hand. It
# fires on the command itself, so it still applies when the commit runs with
# --no-verify and any commit-msg hook is skipped.
#
# Legitimate references are left alone — a CLAUDE.md filename, the .claude/
# directory, an `anthropic` API backend, a model name in prose. Only the
# co-author trailer and generated-with footer shapes match, and only on
# commands that author a message.
#
# The trailer rule matches `claude` or `noreply@anthropic`, not `anthropic`
# alone: a human colleague with an @anthropic.com address is a real co-author
# and their trailer has to survive.
#
# A command that SEARCHES for these marks necessarily contains them, and not
# being blocked for that is a documented property of this hook. It held only
# while the search stood alone: piped into the same command as a write, the
# gate fired on the write and the scan then matched the search string. Inspector
# segments are dropped before matching — see strip_inspectors.
#
# Known false positive: the bare 🤖 rule has no context test, so a commit
# message *about* the emoji is blocked. It stays because it is the only rule
# that catches a generated-with footer phrased without the word "Claude".
#
# Exit: 0 allow · 2 block.

set -euo pipefail

if ! type -P jq >/dev/null 2>&1; then
  echo "ai-attribution-guard: jq not found — hook disabled. Install jq to enable." >&2
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

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // ""')"
[ "$tool" != "Bash" ] && exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
[ -z "$cmd" ] && exit 0

lc="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"

# Only inspect commands that write a commit message or a PR/issue body. Git
# global options may sit before the subcommand — a bare `git +commit` match let
# `git -C <repo> commit ...` slip past. $lc is lowercased, so `-C` arrives as
# `-c`; `-c +[^ ]+` covers both `-C <path>` and `-c <name>=<value>`.
# `git tag` is in scope because an annotated tag carries a message, `merge` and
# `notes` because both write one into history, and `comment`/`release` because
# they publish prose to GitHub just as `create` does. Over-gating is harmless —
# a gated command with no attribution still exits 0 — but the leading
# (^|[[:space:]]) matters: without it `legit commit` matched `git commit`.
#
# `git commit -F <file>` and `--message-file` are not catchable here: the text
# is in a file, not in the command.
GATE_RE='(^|[[:space:]])git( +(-c +[^ ]+|--[a-z][^ ]*|-[a-z]+))* +(commit|tag|merge|notes)|(^|[[:space:]])gh +(pr|issue) +(create|edit|comment)|(^|[[:space:]])gh +release +(create|edit)'
printf '%s' "$lc" | grep -Eq "$GATE_RE" || exit 0

# Drop read-only inspector segments before matching. A search never authors a
# message, so a pre-PR self-check — the workflow rules ask for one before every
# PR — stops arming the guard just because it shares a command with the write it
# is checking.
#
# Three properties keep this from hiding a real mark. A line carrying a gated
# command is left whole, so text inside a `--body` is never touched. The removal
# runs per line, and both text shapes only function at the start of their own
# line — a trailer is not a trailer mid-line. And on any sed failure the raw
# command is scanned, so the failure mode is the old behaviour, not silence.
#
# Deliberately not fixed: chaining the check and the write on one line leaves
# that line carrying a gated command, so it is still blocked. Put the check on
# its own line. Pinned in the verifier so it cannot change silently.
INSPECT_RE='(^|[|&;`]|[$][(])[[:space:]]*(grep|egrep|fgrep|rg|ack|git[[:space:]]+(log|show|diff|blame|grep))[[:space:]].*'

strip_inspectors() {
  printf '%s' "$1" | sed -E "/${GATE_RE}/!s@${INSPECT_RE}@\\1@" 2>/dev/null || printf '%s' "$1"
}

scan_lc="$(strip_inspectors "$lc")"
scan_cmd="$(strip_inspectors "$cmd")"

block() {
  cat >&2 <<EOF
ai-attribution-guard blocked Bash: AI authorship mark in a commit/PR command.
  matched: $1
  policy:  this project never records an AI as author or co-author.
  fix:     drop the 'Co-Authored-By: Claude' trailer and any
           '🤖 Generated with Claude Code' footer, then retry.
See docs/hooks/ai-attribution-guard.md in the agent-harness repo.
EOF
  exit 2
}

printf '%s' "$scan_lc" | grep -Eq 'co-authored-by:.*(claude|noreply@anthropic)' && block "Co-Authored-By: Claude trailer"
printf '%s' "$scan_lc" | grep -Eq 'generated with .{0,20}claude' && block "'Generated with Claude Code' footer"
printf '%s' "$scan_cmd" | grep -q '🤖' && block "🤖 AI-footer emoji"

exit 0

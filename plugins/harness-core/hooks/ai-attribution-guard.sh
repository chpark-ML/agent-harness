#!/bin/bash
# ai-attribution-guard — keep AI-authorship marks out of git history and GitHub.
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
# Known false positive: the bare 🤖 rule has no context test, so a commit
# message *about* the emoji is blocked. It stays because it is the only rule
# that catches a generated-with footer phrased without the word "Claude".
#
# Exit: 0 allow · 2 block.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ai-attribution-guard: jq not found — hook disabled. Install jq to enable." >&2
  exit 0
fi

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
printf '%s' "$lc" \
  | grep -Eq '(^|[[:space:]])git( +(-c +[^ ]+|--[a-z][^ ]*|-[a-z]+))* +(commit|tag|merge|notes)|(^|[[:space:]])gh +(pr|issue) +(create|edit|comment)|(^|[[:space:]])gh +release +(create|edit)' \
  || exit 0

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

printf '%s' "$lc" | grep -Eq 'co-authored-by:.*(claude|noreply@anthropic)' && block "Co-Authored-By: Claude trailer"
printf '%s' "$lc" | grep -Eq 'generated with .{0,20}claude' && block "'Generated with Claude Code' footer"
printf '%s' "$cmd" | grep -q '🤖' && block "🤖 AI-footer emoji"

exit 0

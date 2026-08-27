#!/bin/bash
# verify-ai-attribution-guard.sh — behavioural verification of the
# ai-attribution-guard hook.
# Run from any cwd:  bash scripts/verify-ai-attribution-guard.sh

set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/_verify-lib.sh"
verify_begin ai-attribution-guard hooks/ai-attribution-guard.sh

# --- no-op ------------------------------------------------------------------

run_case "no tool_name → allow" 0 '{}'

run_case "non-Bash tool → allow" 0 \
  '{"tool_name":"Write","tool_input":{"file_path":"CLAUDE.md","content":"Co-Authored-By: Claude"}}'

run_case "empty command → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":""}}'

run_case "command that authors nothing → allow even with the trailer text" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"grep -rn \"Co-Authored-By: Claude\" ."}}'

run_case "plain commit → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Add retry to the upload path\""}}'

# --- boundary: legitimate mentions are not attribution ----------------------

run_case "commit touching CLAUDE.md → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Update CLAUDE.md language policy\""}}'

run_case "commit mentioning the .claude directory → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Move rules under .claude/rules/harness\""}}'

run_case "commit mentioning the anthropic SDK → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Pin anthropic to 0.40 for the tool_use fix\""}}'

run_case "human co-author trailer → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Add parser\" -m \"Co-Authored-By: Jane Doe <jane@example.com>\""}}'

run_case "human co-author who happens to work at Anthropic → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Add parser\" -m \"Co-Authored-By: Jane Doe <jane@anthropic.com>\""}}'

# Known limitation, asserted so it cannot change silently: a trailer value
# cannot tell a given name from a model name, so a human named Claude is
# blocked. Widening the address rule fixed the @anthropic.com case; this one
# has no fix, only a workaround (use a different form of the name).
run_case "known limitation: a human first-named Claude → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m x -m \"Co-Authored-By: Claude Dupont <claude.dupont@example.com>\""}}'

# --- block: commit ----------------------------------------------------------

run_case "commit with Claude co-author trailer → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Add parser\" -m \"Co-Authored-By: Claude <noreply@anthropic.com>\""}}'

run_case "commit with the generated-with footer → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Add parser\" -m \"Generated with [Claude Code](https://claude.com/claude-code)\""}}'

run_case "commit with the robot emoji footer → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Add parser\" -m \"🤖 built by an agent\""}}'

# --- block: the bypasses that motivated the regexes -------------------------

run_case "git -C <path> commit → block (global option before the subcommand)" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /tmp/repo commit -m \"x\" -m \"Co-Authored-By: Claude <noreply@anthropic.com>\""}}'

run_case "git -c user.name=x commit → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git -c user.name=bot commit -m \"x\" -m \"co-authored-by: claude\""}}'

run_case "git --no-pager commit → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git --no-pager commit -m \"x\" -m \"Co-Authored-By: Claude\""}}'

run_case "trailer in mixed case → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\" -m \"CO-AUTHORED-BY: CLAUDE <noreply@anthropic.com>\""}}'

# --- block: gh -------------------------------------------------------------

run_case "gh pr create with the footer → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title t --body \"changes\n\n🤖 Generated with Claude Code\""}}'

run_case "gh issue create with the trailer → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"gh issue create --title t --body \"Co-Authored-By: Claude <noreply@anthropic.com>\""}}'

run_case "gh pr edit with the footer → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr edit 12 --body \"Generated with Claude Code\""}}'

run_case "gh pr comment with the trailer → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr comment 12 --body \"Co-Authored-By: Claude <noreply@anthropic.com>\""}}'

run_case "gh release create with the footer → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"gh release create v1.0 --notes \"🤖 Generated with Claude Code\""}}'

# --- block: other commands that author prose ---------------------------------

run_case "annotated git tag with the trailer → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git tag -a v1.0 -m \"release\" -m \"Co-Authored-By: Claude <noreply@anthropic.com>\""}}'

run_case "the noreply address alone, without the word Claude → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m x -m \"Co-Authored-By: assistant <noreply@anthropic.com>\""}}'

run_case "git tag -l (no message authored) → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git tag -l"}}'

# --- other subcommands that write a message into history ---------------------

run_case "git merge -m with the trailer → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git merge -m \"Co-Authored-By: Claude <noreply@anthropic.com>\" feat-x"}}'

run_case "git notes add -m with the trailer → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git notes add -m \"Co-Authored-By: Claude <noreply@anthropic.com>\" HEAD"}}'

# --- boundary: a search for these marks is not a write of them ----------------
# The single-command case above (`grep -rn ... .`) never reaches the gate. These
# are the shape that did: the search shares a command with a write, so the gate
# fires on the write and the scan used to match on the search string. Both are
# real commands from 2026-08-27.

run_case "pre-PR self-check, then the PR it checks → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git log --format=%B origin/main..HEAD | grep -ciE \"co-authored-by:.*claude\"\ngh pr create --title t --body \"clean body\""}}'

run_case "rg form of the same check, then a commit → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git log -1 | rg -i \"generated with claude\"\ngit commit -m \"Add parser\""}}'

run_case "heredoc writing this hook, alongside a gated command → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"cat > guard.sh <<EOF\n# gate covers gh pr create and git commit\nprintf %s \"$lc\" | grep -Eq \"co-authored-by:.*(claude|noreply@anthropic)\" && block\nEOF"}}'

# --- block: the strip must not hide a mark that is actually being written -----
# Opposite-direction cases for the narrowing above (CONTRIBUTING, rule 1). A
# line carrying a gated command is never stripped, and the removal is per line,
# so neither functioning shape can hide behind a search.

run_case "trailer on its own line, a search elsewhere in the message → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Add parser\n\ngrep the logs for the retry marker\n\nCo-Authored-By: Claude <noreply@anthropic.com>\""}}'

run_case "footer inside --body on a line that also pipes to grep → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title t --body \"see notes | grep foo Generated with Claude Code\""}}'

run_case "search and write chained on ONE line → block (known limitation)" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git log | grep -i \"co-authored-by: claude\" && gh pr create --title t --body ok"}}'

run_case "a message that merely starts a line with the word grep → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\" -m \"grep is used here\nCo-Authored-By: Claude <noreply@anthropic.com>\""}}'

# --- the gate needs a word boundary ------------------------------------------
# Without one, `git +commit` matched the `git commit` inside `legit commit`.

run_case "a command merely containing 'git commit' as a substring → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"legit commit --body \"🤖\""}}'

run_case "jq missing → allow, and say so" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m x -m \"Co-Authored-By: Claude\""}}' \
  PATH=/nonexistent
expect_match "...with a warning naming the hook" "$ERR" "ai-attribution-guard"

# --- the block message has to be actionable ---------------------------------

run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\" -m \"Co-Authored-By: Claude <noreply@anthropic.com>\""}}'
expect_match "block message names which rule fired, not just that one did" "$ERR" "Co-Authored-By: Claude trailer"
expect_match "block message states the fix" "$ERR" "fix:"

verify_summary

#!/bin/bash
# verify-large-file-veto.sh — behavioural verification of the large-file-veto hook.
# Run from any cwd:  bash scripts/verify-large-file-veto.sh

set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/_verify-lib.sh"
verify_begin large-file-veto hooks/large-file-veto.sh

# --- fixture ----------------------------------------------------------------
# A real git repo: the hook shells out to `git ls-files` for the -A / -u forms,
# so a fake directory would exercise a different code path than production.

REPO="$WORK/repo"
mkdir -p "$REPO/sub"
git -C "$REPO" init -q
git -C "$REPO" config user.email verify@example.invalid
git -C "$REPO" config user.name verify

printf 'small\n' > "$REPO/small.txt"
printf 'also small\n' > "$REPO/sub/nested.txt"
# 11 MiB, just over the 10 MiB default.
dd if=/dev/zero of="$REPO/big.bin" bs=1048576 count=11 >/dev/null 2>&1
dd if=/dev/zero of="$REPO/sub/big2.bin" bs=1048576 count=11 >/dev/null 2>&1

lcase() {
  local name="$1" exp="$2" json="$3"; shift 3
  run_case "$name" "$exp" "$json" CLAUDE_PROJECT_DIR="$REPO" "$@"
}

# --- no-op ------------------------------------------------------------------

lcase "no tool_name → allow" 0 '{}'

lcase "non-Bash tool → allow" 0 \
  '{"tool_name":"Read","tool_input":{"file_path":"big.bin"}}'

lcase "empty command → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":""}}'

lcase "command without 'git add' → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git status && git commit -m x"}}'

lcase "'git add' with no arguments → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git add"}}'

lcase "path that does not exist → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git add does-not-exist.bin"}}'

# --- under the threshold ----------------------------------------------------

lcase "small file → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git add small.txt"}}'

lcase "small file in a subdirectory → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git add sub/nested.txt"}}'

# --- over the threshold -----------------------------------------------------

lcase "11 MiB file at the default threshold → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git add big.bin"}}'

lcase "quoted path → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git add \"big.bin\""}}'

lcase "'git add -A' sweeping in the big file → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git add -A"}}'

lcase "'git add .' → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git add ."}}'

lcase "directory argument containing a big file → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git add sub"}}'

lcase "'git add' later in a compound command → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git status && git add big.bin && git commit -m x"}}'

# Regression: a greedy extractor made the LAST `git add` win, so putting the
# big file first and a small one after it slipped through. Both orderings and
# both separators must block.
lcase "big file in the FIRST of two 'git add's → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git add big.bin && git add small.txt"}}'

lcase "big file in the SECOND of two 'git add's → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git add small.txt && git add big.bin"}}'

lcase "big file in the first of two, separated by ';' → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git add sub/big2.bin; git add small.txt; git commit -m x"}}'

lcase "two 'git add's, neither big → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git add small.txt && git add sub/nested.txt"}}'

lcase "'legit add' is not 'git add' → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"./legit add big.bin"}}'

# --- branches the fixture never reached --------------------------------------
# `-u` enumerates tracked-and-modified files, which needs a large file that is
# already committed — the fixture had none, so this whole branch was dead.

git -C "$REPO" add big.bin sub/big2.bin small.txt >/dev/null 2>&1
git -C "$REPO" commit -q -m "track the fixtures" >/dev/null 2>&1
printf 'x' >> "$REPO/big.bin"

lcase "'git add -u' with a modified tracked big file → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git add -u"}}'

lcase "'git add --update' → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git add --update"}}'

ln -sf big.bin "$REPO/link-to-big.bin"
lcase "symlink to a big file → allow (documented: symlinks are skipped)" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git add link-to-big.bin"}}'

lcase "'--' end-of-options separator → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git add -- big.bin"}}'

# --- the threshold is honoured in both directions ---------------------------

lcase "threshold raised above the file → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git add big.bin"}}' \
  HARNESS_LARGE_FILE_BYTES=104857600

lcase "threshold lowered below a small file → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git add small.txt"}}' \
  HARNESS_LARGE_FILE_BYTES=1

# --- shapes the extractor used to miss ---------------------------------------

lcase "two spaces between git and add → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git  add big.bin"}}'

lcase "a tab between git and add → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git\tadd big.bin"}}'

lcase "glob argument → block (neither read -a nor [ -f ] globs)" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git add *"}}'

lcase "glob with a suffix → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git add *.bin"}}'

lcase "glob matching only small files → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git add *.txt"}}'

lcase "subshell parentheses → block (trailing paren used to glue to the path)" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"(cd . && git add big.bin)"}}'

lcase "sudo git add → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"sudo git add big.bin"}}'

# --- prose is not an invocation ----------------------------------------------
# The matcher must anchor at segment start: a mention inside an argument used to
# be parsed as a real `git add -A` and enumerate the whole worktree.

lcase "'git add --all' quoted inside an echo → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"echo \"prefer git add --all over piecemeal staging\""}}'

lcase "'git add -A' quoted inside a commit message → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"note: git add -A swept in a blob once\""}}'

# --- the fail-open branch, which nothing exercised ---------------------------
# Every guard disables itself when jq is missing. That is a decision, so it
# should be pinned like one.

run_case "jq missing → allow, and say so" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git add big.bin"}}' \
  CLAUDE_PROJECT_DIR="$REPO" PATH=/nonexistent
expect_match "...with a warning naming the hook" "$ERR" "large-file-veto"

# --- the block message has to be actionable ---------------------------------

run_hook '{"tool_name":"Bash","tool_input":{"command":"git add big.bin"}}' CLAUDE_PROJECT_DIR="$REPO"
expect_match "block message names the file" "$ERR" "big.bin"
expect_match "block message names the threshold" "$ERR" "10 MiB"
expect_match "block message offers LFS" "$ERR" "LFS"
expect_empty "block writes nothing to stdout" "$OUT"

verify_summary

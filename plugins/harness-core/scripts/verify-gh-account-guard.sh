#!/bin/bash
# verify-gh-account-guard.sh — behavioural verification of the
# gh-account-guard hook.
# Run from any cwd:  bash scripts/verify-gh-account-guard.sh

set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/_verify-lib.sh"
verify_begin gh-account-guard hooks/gh-account-guard.sh

# A stub `gh`, because the suite has to be hermetic. The real one cannot be used
# for two measured reasons: `gh auth status` makes a network call (~0.5s), and
# its answer depends on whoever happens to be logged in on the machine running
# the suite. Either one would have the verifier reporting on something other
# than the hook.
#
# The JSON is frozen from the actual `gh auth status --active --json hosts`
# output of gh 2.89.0. Only login and tokenSource vary, driven by two env vars
# that each case passes through run_hook.
STUB="$WORK/stub"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'SH'
#!/bin/bash
printf '{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"%s","tokenSource":"%s","scopes":"repo","gitProtocol":"https"}]}}\n' \
  "${STUB_GH_LOGIN:-chpark-ML}" "${STUB_GH_SOURCE:-keyring}"
SH
chmod +x "$STUB/gh"
GH_PATH="$STUB:$PATH_SAVE"

# jq present, gh absent — for the self-disabling branch that reports gh. PATH is
# this directory alone, because the real gh would otherwise still be found
# further along. `PATH=/nonexistent` cannot serve here: it removes jq too, so
# the jq branch fires and the gh branch is never reached.
#
# Every external tool the hook uses has to be linked in explicitly. `printf` and
# `command` are builtins; these four are not. If the hook ever reaches for a
# fifth, this case fails loudly instead of quietly testing something else.
#
# The absolute-path check is not defensive padding. A relative link makes a
# self-referential dangling symlink, `grep` then fails inside the gate, `caught`
# stays empty, and the hook exits 0 — so the case reports PASS while never
# reaching the branch it exists to test. It was observed doing exactly that.
JQONLY="$WORK/jqonly"
mkdir -p "$JQONLY"
for t in cat jq grep tr; do
  tp="$(command -v "$t")"
  case "$tp" in
    /*) ln -s "$tp" "$JQONLY/$t" ;;
    *)  echo "verify-gh-account-guard: cannot resolve '$t' to an absolute path (got '$tp')" >&2; exit 1 ;;
  esac
done

# A project that declares an expectation, and one that declares nothing.
DECLARED="$WORK/declared"
mkdir -p "$DECLARED/.claude"
printf '# the account this repository expects\nchpark-ML\n' > "$DECLARED/.claude/gh-account.txt"
SILENT="$WORK/silent"
mkdir -p "$SILENT/.claude"

# --- no-op: input the hook must not touch -----------------------------------

run_case "no tool_name → allow" 0 '{}'

run_case "non-Bash tool → allow" 0 \
  '{"tool_name":"Write","tool_input":{"file_path":"x","content":"git push"}}'

run_case "empty command → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":""}}'

run_case "git status, with an account declared → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git status --porcelain"}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct

run_case "gh pr view is read-only → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr view 12"}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct

# Default-off. The absent file is the off switch, so a mismatched account in a
# repository that declared nothing is not this hook's business.
run_case "git push with nothing declared → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push -u origin feat-x"}}' \
  CLAUDE_PROJECT_DIR="$SILENT" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct

# --- boundary: resembles what is blocked, and must pass ----------------------
# These three are the ones that earn their keep. They are the false positives
# that would get the hook switched off, and switched off is the same as absent.

run_case "the words inside an echo → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"echo \"git push\""}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct

run_case "a commit message mentioning a push → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"remember to git push after review\""}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct

run_case "a subcommand that merely starts with push → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git pushx --dry-run"}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct

# --- block ------------------------------------------------------------------

run_case "git push as the wrong account → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git push -u origin feat-x"}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct

run_case "gh pr create as the wrong account → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title \"[x] y\""}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct

run_case "gh pr merge as the wrong account → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 3 --squash"}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct

# A global option between git and the subcommand must not smuggle a push past
# the gate. ai-attribution-guard shipped without this and `git -C <repo> commit`
# went untouched.
run_case "git -C elsewhere push as the wrong account → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git -C /elsewhere push"}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct

# --- boundary ---------------------------------------------------------------

# The happy path. Easy to leave unasserted, and then the hook could be blocking
# everything and the suite would still be green.
run_case "git push as the expected account → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH="$GH_PATH" STUB_GH_LOGIN=chpark-ML

run_case "HARNESS_GH_ACCOUNT overrides the file → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct \
  HARNESS_GH_ACCOUNT=work-acct

# The two self-disabling branches. The gh one needs jq present and gh absent,
# which is why $JQONLY exists rather than PATH=/nonexistent, and it needs an
# account declared, or the declaration check exits first and nothing is printed.
#
# Each asserts *which* tool it reported missing, not merely that the hook named
# itself. Both messages begin "gh-account-guard:", so matching that prefix alone
# would let the gh case pass while jq was the thing actually missing — and exit 0
# cannot tell a self-disabled hook from one that fell out at the gate.
run_case "gh missing → allow, and say so" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH="$JQONLY"
expect_match "...naming gh as the missing one" "$ERR" "gh not found"

run_case "jq missing → allow, and say so" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH=/nonexistent
expect_match "...naming jq as the missing one" "$ERR" "jq not found"

# --- the block message has to be actionable ---------------------------------

run_hook '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title x"}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct
expect_match "names the active account" "$ERR" "work-acct"
expect_match "names the expected account" "$ERR" "chpark-ML"
expect_match "names where the expectation came from" "$ERR" "gh-account.txt"
expect_match "gives the way to switch" "$ERR" "gh auth switch --user chpark-ML"
expect_match "gives the way to proceed anyway" "$ERR" "HARNESS_GH_ACCOUNT"
expect_match "points at the document" "$ERR" "docs/hooks/gh-account-guard.md"

# An env-supplied token is the case where `gh auth switch` appears to do
# nothing, so the message says where the token came from. The literal value gh
# reports for that source was NOT verified against a live env-token setup, so
# the hook prints whatever gh says rather than matching a guessed word.
run_hook '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$DECLARED" PATH="$GH_PATH" \
  STUB_GH_LOGIN=work-acct STUB_GH_SOURCE=GITHUB_TOKEN
expect_match "says the token came from the environment" "$ERR" "GITHUB_TOKEN"

verify_summary

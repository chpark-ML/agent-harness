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
# The JSON is frozen from the actual `gh auth status --json hosts` output of
# gh 2.89.0. Three env vars drive it, each passed through run_hook per case:
# STUB_GH_LOGIN is the active account, STUB_GH_ROSTER is every authenticated
# account (defaults to just the active one), STUB_GH_SOURCE is the token source.
#
# The roster matters because inference needs it: the hook asks whether the
# remote's owner is itself one of the accounts you are logged in as.
STUB="$WORK/stub"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'SH'
#!/bin/bash
active="${STUB_GH_LOGIN:-chpark-ML}"
roster="${STUB_GH_ROSTER:-$active}"
src="${STUB_GH_SOURCE:-keyring}"
out=""
for l in $roster; do
  if [ "$l" = "$active" ]; then a=true; else a=false; fi
  out="$out{\"state\":\"success\",\"active\":$a,\"host\":\"github.com\",\"login\":\"$l\",\"tokenSource\":\"$src\",\"scopes\":\"repo\",\"gitProtocol\":\"https\"},"
done
printf '{"hosts":{"github.com":[%s]}}\n' "${out%,}"
SH
chmod +x "$STUB/gh"
GH_PATH="$STUB:$PATH_SAVE"

# jq present, gh absent — for the self-disabling branch that reports gh. PATH is
# this directory alone, because the real gh would otherwise still be found
# further along. `PATH=/nonexistent` cannot serve here: it removes jq too, so
# the jq branch fires and the gh branch is never reached.
#
# Every external tool the hook uses has to be linked in explicitly. `printf` and
# `command` are builtins; these five are not. If the hook ever reaches for a
# sixth, this case fails loudly instead of quietly testing something else.
#
# The absolute-path check is not defensive padding. A relative path makes a
# self-referential dangling entry, `grep` then fails inside the gate, `caught`
# stays empty, and the hook exits 0 — so the case reports PASS while never
# reaching the branch it exists to test. It was observed doing exactly that.
#
# Exec wrappers rather than `ln -s`, for two reasons that only show up off
# Linux. Git Bash's `ln -s` returns 0 and writes a *copy*, and the thing it
# copies is often not there: `command -v grep` reports `/usr/bin/grep` while the
# file on disk is `grep.exe`, so the copy came out empty and every case that
# needed this PATH tested a directory of broken stubs. `exec` has no such
# problem — the shell resolves the same suffix rule the lookup used. A wrapper
# also works identically on every platform, so there is one code path here.
JQONLY="$WORK/jqonly"
mkdir -p "$JQONLY"
for t in cat jq grep tr git; do
  tp="$(command -v "$t")"
  case "$tp" in
    /*) printf '#!/bin/bash\nexec "%s" "$@"\n' "$tp" > "$JQONLY/$t"
        chmod +x "$JQONLY/$t" ;;
    *)  echo "verify-gh-account-guard: cannot resolve '$t' to an absolute path (got '$tp')" >&2; exit 1 ;;
  esac
done
# The wrappers are bash scripts, so the interpreter has to be reachable too --
# `env -i PATH=$JQONLY` means the kernel finds /bin/bash by its shebang, but
# anything the wrapper itself calls resolves through this PATH.
[ -x /bin/bash ] || { echo "verify-gh-account-guard: /bin/bash not executable" >&2; exit 1; }

# Fixture projects. The remote is part of the fixture now, because the owner of
# `origin` is what inference reads.
mkfixture() {  # <dir> <origin-url-or-none> [declared-login]
  local d="$WORK/$1" url="$2" declared="${3:-}"
  mkdir -p "$d/.claude"
  git -C "$d" init -q 2>/dev/null
  [ "$url" = "none" ] || git -C "$d" remote add origin "$url" 2>/dev/null
  [ -z "$declared" ] || printf '# the account this repository expects\n%s\n' "$declared" > "$d/.claude/gh-account.txt"
  printf '%s' "$d"
}

DECLARED="$(mkfixture declared     https://github.com/chpark-ML/thing.git chpark-ML)"
CONFLICT="$(mkfixture conflict     https://github.com/chpark-ML/thing.git other-acct)"
MINE="$(    mkfixture mine         https://github.com/chpark-ML/thing.git)"
ORG="$(     mkfixture org          https://github.com/some-org/thing.git)"
NOREMOTE="$(mkfixture noremote     none)"
ELSEWHERE="$(mkfixture elsewhere   https://gitlab.com/chpark-ML/thing.git)"

# Three fixtures from a code review of the inference, each pinning a defect
# that shipped in the first draft. `elsewhere` above passed for the wrong
# reason — gitlab.com simply does not contain the substring that was being
# tested for, so it never exercised host parsing at all.
LOOKALIKE="$(mkfixture lookalike   git@notgithub.com:chpark-ML/thing.git)"
SUFFIXED="$( mkfixture suffixed    https://github.com.evil.io/chpark-ML/thing.git)"
SCPFORM="$(  mkfixture scpform     git@github.com:chpark-ML/thing.git)"
SHOUTING="$( mkfixture shouting    https://github.com/CHPARK-ml/thing.git)"

# A different push URL from the fetch URL. `git push` targets the push URL, so
# that is the one inference has to read.
PUSHURL="$(mkfixture pushurl       https://github.com/some-org/thing.git)"
git -C "$PUSHURL" remote set-url --push origin https://github.com/chpark-ML/thing.git 2>/dev/null

# Two accounts authenticated. That is the whole scenario this hook exists for —
# with one account there is no wrong one to be active as.
BOTH="chpark-ML work-acct"

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

# Nothing declared and the owner is an organisation, so inference has nothing to
# say. This is the case that stays silent, and it is why an org repository still
# has to declare if it wants the guard.
run_case "org remote, nothing declared → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push -u origin feat-x"}}' \
  CLAUDE_PROJECT_DIR="$ORG" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct STUB_GH_ROSTER="$BOTH"

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

# --- inference from the remote owner ----------------------------------------
#
# The point of this half: a personal repository needs no configuration at all.
# If the owner of `origin` is itself one of the accounts you are logged in as,
# that owner is the expectation.

run_case "owner is one of my accounts, a different one is active → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$MINE" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct STUB_GH_ROSTER="$BOTH"
expect_match "block names the inferred owner" "$ERR" "chpark-ML"
expect_match "block says the expectation was inferred, not declared" "$ERR" "origin"

run_case "owner is the active account → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$MINE" PATH="$GH_PATH" STUB_GH_LOGIN=chpark-ML STUB_GH_ROSTER="$BOTH"

# Explicit beats inferred, in both directions. The file naming an account that
# is NOT the owner must win, or declaring something would be pointless.
run_case "a declared account overrides the owner → block on the declared one" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$CONFLICT" PATH="$GH_PATH" STUB_GH_LOGIN=chpark-ML STUB_GH_ROSTER="$BOTH"
expect_match "block names the declared account, not the owner" "$ERR" "other-acct"
expect_match "block cites the file, not the remote" "$ERR" "gh-account.txt"

run_case "HARNESS_GH_ACCOUNT overrides the owner → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$MINE" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct STUB_GH_ROSTER="$BOTH" \
  HARNESS_GH_ACCOUNT=work-acct

# Three shapes with nothing to infer from. Each must stay silent rather than
# guess — a guard that invents an expectation blocks the wrong thing.
run_case "no origin remote → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$NOREMOTE" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct STUB_GH_ROSTER="$BOTH"

run_case "a non-github remote → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$ELSEWHERE" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct STUB_GH_ROSTER="$BOTH"

# One account authenticated: the owner still matches nothing to be wrong about,
# so inference is a no-op rather than a new way to block.
run_case "only one account authenticated → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$MINE" PATH="$GH_PATH" STUB_GH_LOGIN=chpark-ML

# --- regressions from the review of the inference ---------------------------
#
# All three shipped in the first draft, and each is asserted here before it was
# fixed, so none of them can come back quietly.

# The host has to be parsed, not searched for. Both of these contain the string
# "github.com" while being other hosts entirely, and inferring an owner from
# them blocks pushes this hook has no business judging — the cries-wolf
# direction, which is how a guard gets switched off.
run_case "a host merely containing github.com → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$LOOKALIKE" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct STUB_GH_ROSTER="$BOTH"

run_case "a github.com-prefixed host → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$SUFFIXED" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct STUB_GH_ROSTER="$BOTH"

# ...while the scp-like form of a real github.com remote must still be read.
run_case "scp-form github remote → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$SCPFORM" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct STUB_GH_ROSTER="$BOTH"

# GitHub logins are case-insensitive. Comparing exactly left the expectation
# empty and let the push through — failing open, and silently.
run_case "owner spelled in different case → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$SHOUTING" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct STUB_GH_ROSTER="$BOTH"
expect_match "block names gh's spelling, not the URL's" "$ERR" "chpark-ML"

# ...and the mirror of it: the same difference in case must NOT block when the
# owner is who is active. Carrying the URL's casing into the expectation would
# only have moved the defect here.
run_case "different case, owner is active → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$SHOUTING" PATH="$GH_PATH" STUB_GH_LOGIN=chpark-ML STUB_GH_ROSTER="$BOTH"

# `git push` targets the push URL when one is set, so reading the fetch URL
# judges a repository the command is not touching.
run_case "a separate push URL is what gets read → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  CLAUDE_PROJECT_DIR="$PUSHURL" PATH="$GH_PATH" STUB_GH_LOGIN=work-acct STUB_GH_ROSTER="$BOTH"
expect_match "judged by the push URL's owner" "$ERR" "chpark-ML"

verify_summary

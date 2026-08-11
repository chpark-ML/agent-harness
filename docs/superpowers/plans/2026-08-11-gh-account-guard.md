# gh-account-guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> Dated design record. Counts and case totals quoted below describe the tree at the time of writing; [`agent-layer.md`](../../agent-layer.md) is the source of truth for current numbers — the figures here are a record of that moment.

**Goal:** Ship a PreToolUse hook that blocks `git push`, `gh pr create` and `gh pr merge` when the active GitHub account is not the one the repository declared.

**Architecture:** One bash hook gated in four stages — jq present, command caught, expectation declared, account compared — so the expensive step (`gh auth status`, measured at ~0.5 s) runs only after the command has already been identified as a push or a PR. Configuration follows `protected-paths` (a consumer-owned file, absent by default, so the guard ships off), except that its three sources resolve first-match-wins instead of unioning. A frozen `gh` stub keeps the verifier hermetic.

**Tech Stack:** bash 3.2, jq, `gh` 2.89.0's `auth status --active --json hosts`.

**Spec:** [`docs/superpowers/specs/2026-08-11-gh-account-guard-design.md`](../specs/2026-08-11-gh-account-guard-design.md)

**The hook code below was run before this plan was written**, assembled in a scratch directory with the stub and driven through every path under `/bin/bash`: 11 gate cases and 8 end-to-end cases, plus both self-disabling branches and the block message. Two defects were found and are already fixed in the text — `-C` only matched lowercase, so `git -C /elsewhere push` walked through; and the gh-absent case passed while testing nothing. Expect it to work as written; if it does not, suspect the environment before the code.

## Global Constraints

- **bash 3.2 and jq only.** No python, no node, no `mapfile`, no associative arrays, no `${x^^}`. Under `set -u`, expand a possibly-empty array as `"${a[@]+"${a[@]}"}"` ([ADR-0002](../../adr/0002-hook-contract.md)).
- **Every task ends green under both interpreters:** `make verify` and `make verify BASH=/bin/bash`.
- **Only a blocking hook exits 2.** Every other path exits 0, including every self-disabling branch.
- **A hook that parses stdin self-disables when `jq` is absent** — one line to stderr naming the hook, then `exit 0`.
- **The block message is the only interface a consumer has** — it carries what was caught, how to get past it, and a pointer to `docs/hooks/gh-account-guard.md`.
- **`catches` / `scope` / `bypass` go in the hook's header comment.**
- **No AI attribution** in any commit message or PR body — no `Co-Authored-By: Claude`, no `🤖 Generated with` ([ADR-0006](../../adr/0006-no-ai-attribution.md)).
- **Everything shipped is written in English.** The one exception this plan touches is `.claude/harness-gaps.md`, which stays Korean because it is an append-only repo-local ledger ([`CLAUDE.md`](../../../CLAUDE.md) §8).
- **Commit at the end of every task.** Branch is `feat-gh-account-guard`, already created.
- The name `gh-account-guard` must be identical in the hook, the verifier, the doc and `hooks.json`, or the `harness-reviewer` audit cannot run mechanically.

## File Structure

| Path | Responsibility |
|---|---|
| `plugins/harness-core/hooks/gh-account-guard.sh` | the whole decision — gate, config resolution, comparison, block message |
| `plugins/harness-core/scripts/verify-gh-account-guard.sh` | 12 behavioural cases, plus the `gh` stub that keeps them hermetic |
| `docs/hooks/gh-account-guard.md` | consumer-facing behaviour, configuration, what passes and why |
| `plugins/harness-core/hooks/hooks.json` | registration, fourth entry under the existing `Bash` matcher |
| `plugins/harness-core/declarative/templates/gh-account.txt` | comments only, so installing leaves the guard off |
| `plugins/harness-core/bin/harnessctl` | template registration at both scopes, and the inactive hint |
| `plugins/harness-core/declarative/settings-fragment.json` | widen the `gh auth status` permission |
| `plugins/harness-core/skills/pr-create/SKILL.md` | surface the identity before pushing, for repositories that declared nothing |
| `docs/agent-layer.md` | the inventory — hooks 6 → 7, blocking 4 → 5 |
| `plugins/harness-core/.claude-plugin/plugin.json` | `version` 1.11.0 → 1.12.0 |
| `README.md`, `README.ko.md` | `badge/checks-NNN`, moved together as a mirror pair |
| `.claude/harness-gaps.md` | two ledger entries, in Korean |

Tasks 1 and 2 split the hook by what a reviewer could reject independently: *does it match the right commands* versus *does it compare identity correctly*. Both leave a runnable verifier behind.

---

### Task 1: The gate — match the right commands, and nothing else

The half of the hook that decides whether a command acts under an identity. It ends at "yes, and an account is declared", stopping before `gh` is ever called.

**Files:**
- Create: `plugins/harness-core/hooks/gh-account-guard.sh`
- Create: `plugins/harness-core/scripts/verify-gh-account-guard.sh`

**Interfaces:**
- Consumes: `run_case` / `run_hook` / `expect` / `expect_match` / `verify_begin` / `verify_summary` from `plugins/harness-core/scripts/_verify-lib.sh`. `run_hook` runs the hook under `env -i PATH="$PATH_SAVE" HOME="$WORK" LC_ALL=C "$@"`, from `CASE_CWD` (default `$WORK`), and sets `RC` / `OUT` / `ERR`. Extra `VAR=value` arguments land in that environment, and a later `PATH=` overrides the earlier one.
- Produces: the hook file that Task 2 extends, and the verifier's stub scaffolding (`$WORK/stub/gh`, `$WORK/jqonly/jq`) that Task 2's cases reuse.

- [ ] **Step 1: Write the verifier — scaffolding plus the six gate cases**

Create `plugins/harness-core/scripts/verify-gh-account-guard.sh`:

```bash
#!/bin/bash
# verify-gh-account-guard.sh — behavioural verification of the
# gh-account-guard hook.
# Run from any cwd:  bash scripts/verify-gh-account-guard.sh

set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/_verify-lib.sh"
verify_begin gh-account-guard hooks/gh-account-guard.sh

# A stub `gh`, because the suite has to be hermetic. The real one cannot be
# used for two measured reasons: `gh auth status` makes a network call (~0.5s),
# and its answer depends on whoever happens to be logged in on the machine
# running the suite.
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

# jq present, gh absent — for the self-disabling branch of step 4. PATH is this
# directory alone, because the real gh would otherwise still be found further
# along. `PATH=/nonexistent` cannot serve here: it removes jq too, so step 1
# fires and step 4 is never reached.
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

verify_summary
```

- [ ] **Step 2: Run it and confirm it fails for the right reason**

```bash
bash plugins/harness-core/scripts/verify-gh-account-guard.sh
```

Expected: `verify-gh-account-guard: hook not found at .../hooks/gh-account-guard.sh`, exit 1. Not a case failure — `verify_begin` aborts before any case runs.

- [ ] **Step 3: Write the hook, up to the declaration check**

Create `plugins/harness-core/hooks/gh-account-guard.sh`:

```bash
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
# so `git commit -m "... git push ..."` would be a false positive.
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
```

`while read` runs in the current shell here because the input is a heredoc, not a pipe — so `caught` survives the loop. A pipe would put it in a subshell and the assignment would vanish.

`tr ';|&\n' '\n\n\n\n'` maps every separator character to a newline, which handles `&&` and `||` as a side effect: two newlines make an empty segment, which the `case` skips.

- [ ] **Step 4: Make it executable, then run the verifier**

```bash
chmod +x plugins/harness-core/hooks/gh-account-guard.sh
bash plugins/harness-core/scripts/verify-gh-account-guard.sh
```

Expected: `9 / 9 passed`.

- [ ] **Step 5: Run it under the bash 3.2 floor**

```bash
BASH=/bin/bash bash plugins/harness-core/scripts/verify-gh-account-guard.sh
/bin/bash -n plugins/harness-core/hooks/gh-account-guard.sh
```

Expected: `9 / 9 passed`, and no syntax output.

- [ ] **Step 6: Commit**

```bash
git add plugins/harness-core/hooks/gh-account-guard.sh \
        plugins/harness-core/scripts/verify-gh-account-guard.sh
git commit -m "Match the commands that act under a GitHub identity" -m "The gate is anchored at the start of each command segment, unlike
ai-attribution-guard's deliberately wide one. That hook can afford a
wide gate because a clean command passes it and exits 0 anyway; here
the gate is the block, so 'git commit -m \"... git push ...\"' would
be a false positive, and a check that cries wolf gets switched off."
```

---

### Task 2: The comparison — who is active, and the block message

**Files:**
- Modify: `plugins/harness-core/hooks/gh-account-guard.sh` (replace the trailing `exit 0` placeholder)
- Modify: `plugins/harness-core/scripts/verify-gh-account-guard.sh` (add six cases before `verify_summary`)

**Interfaces:**
- Consumes: from Task 1 — the variables `caught` (the matched command segment), `expected` (the declared login) and `expected_from` (the path or env var name it came from); and in the verifier, `$GH_PATH`, `$JQONLY`, `$DECLARED`, `$SILENT`, `STUB_GH_LOGIN`, `STUB_GH_SOURCE`.
- Produces: the finished hook. Nothing later depends on its internals.

- [ ] **Step 1: Add the six remaining cases**

Insert immediately before `verify_summary` in `plugins/harness-core/scripts/verify-gh-account-guard.sh`:

```bash
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
# account declared, or step 3 exits first and nothing is printed.
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
```

- [ ] **Step 2: Run and confirm the new cases fail**

```bash
bash plugins/harness-core/scripts/verify-gh-account-guard.sh
```

Expected: the nine Task 1 cases pass; the four `→ block` cases FAIL with `expected exit 2, got 0`; the `expect_match` assertions on the message FAIL. The two self-disabling cases and the two allow cases pass already, for the wrong reason — Task 1's placeholder allows everything.

- [ ] **Step 3: Replace the placeholder with the comparison**

In `plugins/harness-core/hooks/gh-account-guard.sh`, delete the line
`exit 0   # Task 2 replaces this line with the comparison.` and append:

```bash
# --- who is active? ---------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  echo "gh-account-guard: gh not found — hook disabled for this call." >&2
  exit 0
fi

# --active --json hosts, rather than reading the prose. Under --json gh exits 0
# regardless of any authentication issue (its own help says so), so the payload
# is read and the exit code never is.
#
# ~/.config/gh/hosts.yml would be free and offline, and was rejected: when
# GH_TOKEN or GITHUB_TOKEN is set, gh uses that token and `gh auth switch` has
# no effect, yet hosts.yml still names the old account. A guard about mistaken
# identity must not be confidently wrong exactly when identity is confused.
status="$(gh auth status --active --hostname github.com --json hosts 2>/dev/null || true)"
active="$(printf '%s' "$status" | jq -r '.hosts["github.com"][0].login // empty' 2>/dev/null || true)"

# gh answered but named nobody. Not an identity mismatch — let git report the
# real problem. `state` is not consulted either: a broken token fails loudly on
# its own, and this hook only ever answers *which account*.
[ -n "$active" ] || exit 0
[ "$active" = "$expected" ] && exit 0

token_src="$(printf '%s' "$status" | jq -r '.hosts["github.com"][0].tokenSource // empty' 2>/dev/null || true)"
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
```

- [ ] **Step 4: Run the verifier, both interpreters**

```bash
bash plugins/harness-core/scripts/verify-gh-account-guard.sh
BASH=/bin/bash bash plugins/harness-core/scripts/verify-gh-account-guard.sh
```

Expected: all cases pass under both — **17 `run_case` cases** (9 from Task 1, 8 here) plus the `expect_match` assertions on the two block messages.

The spec sketched twelve. The five extra are the ones the hook contract obliges every stdin-parsing hook to pin: absent `tool_name`, non-Bash tool, empty command, both self-disabling branches, and `git -C <path> push` — the shape that slipped past `ai-attribution-guard` once already.

- [ ] **Step 5: Confirm the hook is inert in this repository**

This repository declares no expected account and must not start blocking its own pushes.

```bash
test -f .claude/gh-account.txt && echo "UNEXPECTED: a declaration exists" || echo "ok: no declaration, guard inert"
echo '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  | bash plugins/harness-core/hooks/gh-account-guard.sh; echo "exit=$?"
```

Expected: `ok: no declaration, guard inert` and `exit=0`.

- [ ] **Step 6: Commit**

```bash
git add plugins/harness-core/hooks/gh-account-guard.sh \
        plugins/harness-core/scripts/verify-gh-account-guard.sh
git commit -m "Compare the active gh account against the declared one" -m "Reads gh auth status --active --json hosts instead of parsing prose.
Under --json gh exits 0 whatever the auth state, so the payload is read
and the exit code is not. hosts.yml would have been free and offline but
is wrong under GH_TOKEN, which is the one case where the account is
genuinely in doubt."
```

---

### Task 3: Registration and the consumer-facing document

Until it is registered the hook never runs; until it is documented the block message points at a file that does not exist.

**Files:**
- Modify: `plugins/harness-core/hooks/hooks.json`
- Create: `docs/hooks/gh-account-guard.md`

**Interfaces:**
- Consumes: the finished hook from Task 2, and the exact string `docs/hooks/gh-account-guard.md` that its block message prints.
- Produces: nothing later tasks read.

- [ ] **Step 1: Register the hook**

In `plugins/harness-core/hooks/hooks.json`, add a fourth entry to the `hooks` array of the existing `"matcher": "Bash"` block, after `ai-attribution-guard`:

```json
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/gh-account-guard.sh\""
          }
```

Do not add a new matcher block — the `Bash` matcher already exists, and a second one with the same matcher would run the set twice.

- [ ] **Step 2: Confirm the JSON is valid and the path is anchored**

```bash
jq -e '.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks | length == 4' \
  plugins/harness-core/hooks/hooks.json
jq -r '.hooks.PreToolUse[].hooks[].command' plugins/harness-core/hooks/hooks.json \
  | grep -c 'CLAUDE_PLUGIN_ROOT'
```

Expected: `true`, then `5`.

- [ ] **Step 3: Write the document**

Create `docs/hooks/gh-account-guard.md`, following the shape of `docs/hooks/ai-attribution-guard.md` — `# name`, one-line purpose, `## Behaviour`, `## Configuration`, `## What passes`, `## Limits`. It must state, because each one is a decision someone will otherwise try to "fix":

- the numbered check order from the spec §3, and that the ~0.5 s `gh auth status` sits last on purpose;
- that configuration resolves **first-match-wins, not unioned like `protected-paths`**, and why a union would weaken the guard;
- that the absent file is the off switch, so the guard ships off;
- that the gate is anchored while `ai-attribution-guard`'s is not, and why the wide gate is safe there and not here;
- the accepted permissive gap: `echo $(git push)` is not caught;
- the two self-disabling branches, `jq` and `gh`;
- that `git config user.email` is **not** checked, and that a commit's author is a separate knob from the token.

Reference `../../plugins/harness-core/hooks/hooks.json` for the registration, as the sibling documents do.

- [ ] **Step 4: Verify references resolve and the dispatcher sees the hook**

```bash
make doc-refs
make verify-hooks 2>&1 | tail -20
```

Expected: doc-refs clean, and the summary now includes a `gh-account-guard` section.

- [ ] **Step 5: Commit**

```bash
git add plugins/harness-core/hooks/hooks.json docs/hooks/gh-account-guard.md
git commit -m "Register gh-account-guard and document its decisions" -m "Records the two that will otherwise be 'fixed' later: configuration
resolves first-match-wins rather than unioning like protected-paths,
because a union would mean either account is fine; and the gate is
anchored where ai-attribution-guard's is not."
```

---

### Task 4: The template and the installer

A hook whose configuration file no installer ever creates is a hook nobody turns on.

**Files:**
- Create: `plugins/harness-core/declarative/templates/gh-account.txt`
- Modify: `plugins/harness-core/bin/harnessctl` (near lines 229–234 and 193–195)
- Modify: `scripts/verify-install.sh`

**Interfaces:**
- Consumes: the filename `gh-account.txt`, which must match what the hook reads in Task 1's `read_account` calls.
- Produces: a `template`-tier manifest entry named `gh-account.txt` at user scope and `.claude/gh-account.txt` at project scope.

- [ ] **Step 1: Write the template — comments only**

Create `plugins/harness-core/declarative/templates/gh-account.txt`:

```
# gh-account — the GitHub account this repository expects to act as.
#
# One login, on its own line. Blank lines and #-comments are ignored, and only
# the first real line is read. While this file has no such line the guard is
# off, which is the default.
#
# When it is set, gh-account-guard blocks `git push`, `gh pr create` and
# `gh pr merge` if `gh` is currently active as a different account, and tells
# you which one it saw.
#
#   chpark-ML
#
# A one-off push as another account, without editing this file:
#   HARNESS_GH_ACCOUNT=<login> git push
#
# See docs/hooks/gh-account-guard.md
```

Leaving every line commented is the point: installing must not silently start blocking pushes in a repository that never asked.

- [ ] **Step 2: Register it at both scopes**

In `plugins/harness-core/bin/harnessctl`, beside the existing `addt` calls (near lines 229–234), add one line to each scope's block, matching the surrounding alignment:

```bash
  addt "$PAYLOAD/templates/gh-account.txt"     "gh-account.txt"
```

```bash
  addt "$PAYLOAD/templates/gh-account.txt"     ".claude/gh-account.txt"
```

- [ ] **Step 3: Add the inactive hint**

Next to the `protected-paths` hint (near lines 193–195), following its exact shape:

```bash
  if [ -f "$CONFIG_DIR/gh-account.txt" ] \
     && ! grep -q '^[[:space:]]*[^[:space:]#]' "$CONFIG_DIR/gh-account.txt" 2>/dev/null; then
    say "  --    gh-account-guard inactive — put the expected account login in $CONFIG_DIR/gh-account.txt to turn it on"
  fi
```

- [ ] **Step 4: Assert the install and uninstall properties**

`scripts/verify-install.sh` already loops over the files an install must produce, so these are additions to existing lists rather than new blocks.

Add `.claude/gh-account.txt` to the project-scope file loop at line 170:

```bash
for f in CLAUDE.md .claude/rules/harness/workflow.md .claude/protected-paths.txt \
         .claude/gh-account.txt \
```

Add `gh-account.txt` to the user-scope loop at line 374:

```bash
for f in CLAUDE.md protected-paths.txt allowed-paths.txt gh-account.txt harness-manifest.json; do
```

Then three `check` assertions, following the shape of the existing lines 329 and 346. Put the first in the `managed vs template` section (near line 285) and the other two beside their siblings:

```bash
check "gh-account.txt lands in the template tier, not managed" \
  "$(jq -e '(.files.template | index("gh-account.txt")) and ((.files.managed // []) | index("gh-account.txt") | not)' \
       "$C/.claude/harness-manifest.json" >/dev/null 2>&1 && echo 0 || echo 1)"
```

```bash
check "template gh-account.txt left behind by default" \
  "$([ -e "$C/.claude/gh-account.txt" ] && echo 0 || echo 1)"
```

```bash
check "--purge-templates removes gh-account.txt too" \
  "$([ ! -e "$C2/.claude/gh-account.txt" ] && echo 0 || echo 1)"
```

Confirm the manifest path and the `$C` / `$C2` variable names against the surrounding code before writing them — the two consumer fixtures are distinct on purpose, `$C2` being the one uninstalled with `--purge-templates`.

Then run the suite:

```bash
bash scripts/verify-install.sh 2>&1 | tail -20
BASH=/bin/bash bash scripts/verify-install.sh 2>&1 | tail -5
```

Expected: the count rises from 99 by the assertions added, zero failures, under both interpreters.

- [ ] **Step 5: Confirm a fresh install leaves the guard off**

Build-and-inspect, because the whole point is that installing changes nothing until someone opts in.

```bash
tmp="$(mktemp -d)" && git init -q "$tmp" && \
  ( cd "$tmp" && bash "$OLDPWD/plugins/harness-core/bin/harnessctl" init --scope project ) && \
  cat "$tmp/.claude/gh-account.txt" | grep -cv '^[[:space:]]*\(#.*\)\?$'
```

Expected: `0` — no active line, so the guard is off. Then remove `$tmp`.

- [ ] **Step 6: Commit**

```bash
git add plugins/harness-core/declarative/templates/gh-account.txt \
        plugins/harness-core/bin/harnessctl scripts/verify-install.sh
git commit -m "Install a commented gh-account template, off by default" -m "Registered in the template tier, so uninstall keeps it and only
--purge-templates removes it. Every line is a comment on purpose:
installing must not start blocking pushes in a repository that never
asked for it."
```

---

### Task 5: Widen the gh auth status permission

**Files:**
- Modify: `plugins/harness-core/declarative/settings-fragment.json:53`

**Interfaces:**
- Consumes: nothing.
- Produces: the permission that Task 6's `pr-create` step relies on to run without a prompt.

- [ ] **Step 1: Widen the string**

Line 53 currently allows the exact string `"Bash(gh auth status)"`. `gh auth status --active --json hosts` does not match it, so the identity check added in Task 6 would prompt every time. Change it to:

```json
      "Bash(gh auth status:*)"
```

This is read-only in every form — `--active`, `--hostname`, `--json`, `--jq` — so widening it grants nothing that mutates. The count of permission strings is unchanged, so `docs/agent-layer.md`'s `allow 47 / ask 3 / deny 8` still holds.

The hook itself is unaffected either way: hook commands are not gated by the Bash allowlist.

- [ ] **Step 2: Verify the fragment still parses and merges**

```bash
jq -e '.permissions.allow | index("Bash(gh auth status:*)")' \
  plugins/harness-core/declarative/settings-fragment.json
jq -e '.permissions.allow | length == 47' \
  plugins/harness-core/declarative/settings-fragment.json
bash scripts/verify-install.sh 2>&1 | tail -5
```

Expected: an index, `true`, and the install suite green.

- [ ] **Step 3: Commit**

```bash
git add plugins/harness-core/declarative/settings-fragment.json
git commit -m "Allow gh auth status with flags, not just bare" -m "The entry was an exact string, so 'gh auth status --active --json
hosts' fell outside it and would prompt. Every form of the subcommand
is read-only, so widening grants nothing that mutates."
```

---

### Task 6: Surface the identity in pr-create

The guard is off until someone declares an account. This is what a repository that declared nothing gets: the fact, stated before the push.

**Files:**
- Modify: `plugins/harness-core/skills/pr-create/SKILL.md` (Step 5, before the `git push` block)

**Interfaces:**
- Consumes: the permission widened in Task 5.
- Produces: nothing.

- [ ] **Step 1: Add the identity line to Step 5**

In `plugins/harness-core/skills/pr-create/SKILL.md`, insert immediately before the `git push -u origin <branch>` fenced block:

````markdown
**Say who you are about to be.** `gh` is git's credential helper, so the push and
the PR both go out as whatever account is *active* — and with two accounts on one
machine that is not always the one this repository wants.

```bash
gh auth status --active --hostname github.com --json hosts \
  | jq -r '.hosts["github.com"][0] | "pushing as \(.login) (token from \(.tokenSource))"'
```

Report that line to the user before pushing. If a repository has declared an
expected account in `.claude/gh-account.txt`, `gh-account-guard` blocks a
mismatch on its own; this step is what the repositories that declared nothing
get.
````

- [ ] **Step 2: Confirm the description is untouched**

The skill's `description` frontmatter carries its triggers and negative routing, and changing it would invalidate the measured trigger eval. Adding a body step does not.

```bash
git diff plugins/harness-core/skills/pr-create/SKILL.md | grep -E '^[-+]description:' && \
  echo "STOP: description changed — the trigger eval must be re-measured" || \
  echo "ok: description untouched, no eval re-run needed"
bash scripts/verify-frontmatter.sh 2>&1 | tail -3
```

Expected: `ok: description untouched...`, and frontmatter verification clean.

- [ ] **Step 3: Commit**

```bash
git add plugins/harness-core/skills/pr-create/SKILL.md
git commit -m "State which account a push is about to go out as" -m "gh is git's credential helper, so the push and the PR both use the
active account. gh-account-guard blocks a declared mismatch; this line
is what a repository that declared nothing gets."
```

---

### Task 7: The inventory, the version, the badges, the ledger

The bookkeeping that makes the hook actually reach a consumer. **The version bump is not optional** — the manifest states a `version`, so committing alone delivers nothing: Claude Code sees the same string and keeps its cache.

**Files:**
- Modify: `docs/agent-layer.md`
- Modify: `plugins/harness-core/.claude-plugin/plugin.json`
- Modify: `README.md`, `README.ko.md`
- Modify: `.claude/harness-gaps.md`

**Interfaces:**
- Consumes: the final case count, which is only known once every earlier task is green — this task must run last.
- Produces: nothing.

- [ ] **Step 1: Update the single source of truth**

In `docs/agent-layer.md`, §3's adoption table: `✅ 6 (4 blocking, 2 informational)` → `✅ 7 (5 blocking, 2 informational)`. Add `gh-account-guard` to the hook inventory wherever the other six are listed, in the same form.

This file is the only place the inventory lives ([ADR-0004](../../adr/0004-single-source-of-truth.md)) — do not copy the count into the README or anywhere else.

- [ ] **Step 2: Bump the plugin version**

`plugins/harness-core/.claude-plugin/plugin.json`: `"version": "1.11.0"` → `"version": "1.12.0"`. A new capability, so the minor moves.

- [ ] **Step 3: Settle the published check total**

```bash
make verify-all 2>&1 | tail -25
```

If it reports a mismatch between the `badge/checks-NNN` in `README.md` and the real total, update the badge in **both** READMEs to the number it reports. They are a mirror pair and must move together ([`CLAUDE.md`](../../../CLAUDE.md) §8).

Then re-run until clean:

```bash
make verify-all 2>&1 | grep -iE 'FAIL|mismatch|badge' | head
```

Expected: no output.

- [ ] **Step 4: Append the two ledger entries**

`.claude/harness-gaps.md` is append-only and **stays in Korean** ([`CLAUDE.md`](../../../CLAUDE.md) §8) — translating it would mean rewriting history, which is the one thing an append-only record must not do. Append two entries in the existing format (`## <date> — <title>`, `- **어디**`, `- **무슨 일**`, `- **회차**`):

1. **`user.email` and the active gh account are independent, and nothing checks it.** Occurrence 1. Note the concrete evidence: on this machine the active account is `chpark-ML` while `git config user.email` is a personal address. Say that it was deliberately left out of `gh-account-guard` because it doubles the configuration format and was not one of the accidents named.
2. **§7's occurrence gate was passed knowingly for this hook.** Record that the count was not established, that the requester chose to build anyway, and that this is a decision rather than a precedent — so the next person reads it as one.

- [ ] **Step 5: Full verification, both interpreters**

```bash
make verify-all 2>&1 | tail -15
make verify BASH=/bin/bash 2>&1 | tail -15
```

Expected: zero failures under both. `make verify BASH=/bin/bash` is the required gate before merging.

- [ ] **Step 6: Audit the bundle**

Dispatch the `harness-reviewer` agent to check that every artifact this contribution owes is present and consistent — the §2 six plus the four this plan added. Fix anything it names.

- [ ] **Step 7: Commit**

```bash
git add docs/agent-layer.md plugins/harness-core/.claude-plugin/plugin.json \
        README.md README.ko.md .claude/harness-gaps.md
git commit -m "Record gh-account-guard in the inventory and bump to 1.12.0" -m "The version bump is what actually delivers the hook: the manifest
states a version, so committing alone leaves Claude Code looking at the
same string and keeping its cache.

Two ledger entries. The user.email mismatch is occurrence 1 — the
active account and the commit author are independent knobs and nothing
checks the second. And §7's two-occurrence gate was passed knowingly
here, recorded so the next person reads a decision, not a precedent."
```

---

## After the plan

Open the PR with the `harness-core:pr-create` skill. Two things belong in the body under `## Notes`:

- **§7's occurrence gate was passed deliberately.** The count was never established; the requester chose to build the hook anyway.
- **`docs/superpowers/specs/` and `docs/superpowers/plans/` are new directory families** in this repository, sitting beside `docs/adr/`. They were accepted as Superpowers' default location. If they should live elsewhere, moving them is cheaper now than later.

Do not merge — that is the user's ([`CLAUDE.md`](../../../CLAUDE.md) §6, and the `pr-create` skill stops at PR open).

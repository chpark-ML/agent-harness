#!/bin/bash
# verify-harness-log.sh — behavioural verification of the harness-log renderer.
#
# The load-bearing property is what it leaves OUT. The page is meant to hold
# typed prompts and final answers and nothing else; everything it drops — tool
# results, subagent transcripts, skill injections, system reminders, compaction
# hand-offs — is dropped because a page that swallowed them would carry
# whatever a command printed into a file the developer then opens, shares, or
# forgets to keep out of git.
#
# So the cases come in three kinds, and the third is the one that earns its
# keep: content that must appear, content that must not, and content that
# *looks* like the excluded kind but is really a human talking about it.
#
# Run from any cwd:  bash scripts/verify-harness-log.sh

set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/_verify-lib.sh"
verify_begin harness-log bin/harness-log

PROJ="$WORK/proj"
CFG="$WORK/cfg"
mkdir -p "$PROJ"
SLUG="$(printf '%s' "$PROJ" | sed 's/[\/.]/-/g')"
TDIR="$CFG/projects/$SLUG"

# One transcript event. Keeping the JSON in jq rather than in printf means a
# case can carry quotes, angle brackets and newlines without the fixture itself
# becoming the thing under test.
ev_user()   { jq -cn --arg t "$1" --arg b "${2:-main}" \
                '{type:"user",isSidechain:false,timestamp:"2026-08-08T00:00:00Z",gitBranch:$b,message:{content:$t}}'; }
ev_asst()   { jq -cn --arg t "$1" \
                '{type:"assistant",isSidechain:false,timestamp:"2026-08-08T00:00:01Z",message:{content:[{type:"text",text:$t}]}}'; }
ev_tool()   { jq -cn --arg t "$1" \
                '{type:"user",isSidechain:false,timestamp:"2026-08-08T00:00:02Z",message:{content:[{type:"tool_result",content:$t}]}}'; }
ev_inject() { jq -cn --arg t "$1" \
                '{type:"user",isSidechain:false,timestamp:"2026-08-08T00:00:03Z",message:{content:[{type:"text",text:$t}]}}'; }
ev_sub()    { jq -cn --arg t "$1" \
                '{type:"assistant",isSidechain:true,timestamp:"2026-08-08T00:00:04Z",message:{content:[{type:"text",text:$t}]}}'; }

# session <name> — start a fresh transcript; every ev_* after it appends.
session() {
  rm -rf "$TDIR"; mkdir -p "$TDIR"
  CUR="$TDIR/$1.jsonl"
  : > "$CUR"
}
add() { printf '%s\n' "$1" >> "$CUR"; }

# render [extra args] — sets RC, OUT (the page), ERR.
render() {
  ( cd "$PROJ" && env -i PATH="$PATH_SAVE" HOME="$WORK" LC_ALL=C \
      CLAUDE_CONFIG_DIR="$CFG" "$BASH_SAVE" "$HOOK" \
      --project "$PROJ" --out "$WORK/out.html" --no-exclude "$@" ) \
    > "$WORK/.stdout" 2> "$WORK/.stderr"
  RC=$?
  ERR="$(cat "$WORK/.stderr")"
  OUT="$(cat "$WORK/out.html" 2>/dev/null)"
}

# --- 1. no transcripts at all ------------------------------------------------
# An empty project must fail loudly. A renderer that writes a blank page here
# is indistinguishable from one whose extraction silently matched nothing.

rm -rf "$TDIR"
render
if [ "$RC" -ne 0 ]; then _pass "no transcripts → non-zero exit"; else _fail "no transcripts → non-zero exit" "got 0"; fi
expect_match "and names the directory it looked in" "$ERR" "$TDIR"

# --- 2. the basic shape ------------------------------------------------------

session s1
add "$(ev_user 'count the ADR files')"
add "$(ev_asst 'There are 13.')"
render
expect "one turn renders" 0 "$RC"
expect_match "the prompt is on the page" "$OUT" "count the ADR files"
expect_match "the answer is on the page" "$OUT" "There are 13."
expect_match "the branch is shown" "$OUT" "main"

# --- 3. what must not appear -------------------------------------------------

session s2
add "$(ev_user 'summarise the repo')"
add "$(ev_tool 'AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG')"
add "$(ev_inject 'Base directory for this skill: /cache/harness-core/skills/pr-create')"
add "$(ev_sub 'subagent scratch notes nobody asked for')"
add "$(ev_asst 'Six plugins, 431 checks.')"
render
expect_absent "a tool result never reaches the page" "$OUT" "wJalrXUtnFEMI"
expect_absent "a skill injection never reaches the page" "$OUT" "Base directory for this skill"
expect_absent "a subagent transcript never reaches the page" "$OUT" "subagent scratch notes"
expect_match "and the real answer still does" "$OUT" "Six plugins, 431 checks."

# --- 4. inline plumbing inside an otherwise real prompt ----------------------

session s3
add "$(ev_user 'fix the build
<system-reminder>Recalled memory: the user prefers rebase merges</system-reminder>
and then run the tests')"
add "$(ev_asst 'Done.')"
render
expect_absent "a system-reminder is stripped from a prompt" "$OUT" "Recalled memory"
expect_match "the prose before it survives" "$OUT" "fix the build"
expect_match "the prose after it survives" "$OUT" "and then run the tests"

# --- 5. slash-command plumbing ----------------------------------------------

session s4
add "$(ev_user '<command-name>/effort</command-name>')"
add "$(ev_asst 'Effort set to xhigh.')"
add "$(ev_user 'now review the diff')"
add "$(ev_asst 'Two findings.')"
render
expect_absent "a wrapper-only prompt is dropped" "$OUT" "Effort set to xhigh"
expect_match "the real prompt after it is kept" "$OUT" "now review the diff"

# --- 6. the compaction hand-off ---------------------------------------------
# It arrives as a user message, but nobody typed it and its body is a machine
# summary of exactly the tool work this page exists to leave out.

session s5
add "$(ev_user 'This session is being continued from a previous conversation.
Summary: ran sed over /etc/shadow and found root:$6$saltysalt')"
add "$(ev_asst 'Continuing.')"
render
expect_absent "the hand-off body is dropped" "$OUT" "saltysalt"
expect_match "but the fact of it is shown" "$OUT" "context compacted"
expect_match "and the turn after it still renders" "$OUT" "Continuing."

# --- 7. boundary: a human talking ABOUT the excluded kinds -------------------
# This is the case that separates a filter from a blanket ban. Someone
# discussing tool_result must not be censored for using the word.

session s6
add "$(ev_user 'why does the log skip tool_result and system-reminder blocks?')"
add "$(ev_asst 'Because a page that kept tool_result would carry whatever a command printed.')"
render
expect_match "prose mentioning tool_result is kept in the prompt" "$OUT" "why does the log skip tool_result"
expect_match "and in the answer" "$OUT" "would carry whatever a command printed"

# --- 8. more than one turn per session --------------------------------------
# Regression: the first assembly emitted bare objects with hand-written commas
# and produced invalid JSON the moment a session held two turns. It passed
# every single-turn fixture.

session s7
add "$(ev_user 'first question')";  add "$(ev_asst 'first answer')"
add "$(ev_user 'second question')"; add "$(ev_asst 'second answer')"
add "$(ev_user 'third question')";  add "$(ev_asst 'third answer')"
render
expect "three turns still exit 0" 0 "$RC"
expect_match "turn 1 survives" "$OUT" "first question"
expect_match "turn 2 survives" "$OUT" "second question"
expect_match "turn 3 survives" "$OUT" "third question"

# --- 9. the LAST assistant text is the answer -------------------------------

session s8
add "$(ev_user 'refactor the parser')"
add "$(ev_asst 'Let me look at the current implementation.')"
add "$(ev_asst 'Now I will extract the tokenizer.')"
add "$(ev_asst 'Refactored: 3 files, 40 lines removed.')"
render
expect_match "the final message is the answer" "$OUT" "3 files, 40 lines removed"
expect_absent "interim narration is not" "$OUT" "Let me look at the current implementation"

# --- 10. HTML in a prompt is escaped, not executed ---------------------------

session s9
add "$(ev_user 'does <script>alert(1)</script> get escaped? also a<b')"
add "$(ev_asst 'It does.')"
render
expect_absent "a script tag is not emitted raw" "$OUT" "<script>alert(1)"
expect_match "it is escaped instead" "$OUT" "&lt;script&gt;alert(1)"
expect_match "and a bare less-than is too" "$OUT" "a&lt;b"

# --- 11. fenced code survives as code ---------------------------------------

session s10
add "$(ev_user 'show me the command')"
add "$(ev_asst 'Run this:

```bash
make verify BASH=/bin/bash
```
')"
render
expect_match "a fenced block becomes a code block" "$OUT" 'class="code"'
expect_match "with its contents intact" "$OUT" "make verify BASH=/bin/bash"
expect_absent "and the fence markers are gone" "$OUT" '```'

# --- 12. --limit selects the most recent sessions ---------------------------

session s11
add "$(ev_user 'oldest session prompt')"; add "$(ev_asst 'a')"
CUR="$TDIR/s12.jsonl"; : > "$CUR"
add "$(jq -cn '{type:"user",isSidechain:false,timestamp:"2026-08-09T00:00:00Z",gitBranch:"main",message:{content:"newest session prompt"}}')"
add "$(ev_asst 'b')"
render --limit 1
expect_match "--limit 1 keeps the newest session" "$OUT" "newest session prompt"
expect_absent "and drops the older one" "$OUT" "oldest session prompt"

# --- 13. git exclusion is opt-out, and never edits a tracked .gitignore ------

git -C "$PROJ" init -q 2>/dev/null
git -C "$PROJ" config user.email verify@example.invalid
git -C "$PROJ" config user.name verify
session s13
add "$(ev_user 'anything')"; add "$(ev_asst 'ok')"

( cd "$PROJ" && env -i PATH="$PATH_SAVE" HOME="$WORK" LC_ALL=C \
    CLAUDE_CONFIG_DIR="$CFG" "$BASH_SAVE" "$HOOK" --project "$PROJ" ) >/dev/null 2>&1
if [ -f "$PROJ/.git/info/exclude" ] && grep -q '^session-log\.html$' "$PROJ/.git/info/exclude"; then
  _pass "the default run excludes the page from git"
else
  _fail "the default run excludes the page from git" "not found in .git/info/exclude"
fi
if [ -f "$PROJ/.gitignore" ]; then
  _fail "and never creates a tracked .gitignore" "it created one"
else
  _pass "and never creates a tracked .gitignore"
fi

rm -f "$PROJ/.git/info/exclude"
render
if [ -f "$PROJ/.git/info/exclude" ] && grep -q 'session-log' "$PROJ/.git/info/exclude" 2>/dev/null; then
  _fail "--no-exclude leaves git alone" "it wrote to .git/info/exclude anyway"
else
  _pass "--no-exclude leaves git alone"
fi

# --- 14. the second run does not duplicate the exclude line ------------------
# The "already ignored" branch only runs on a repeat invocation, and a renderer
# people run weekly would otherwise grow that file a line at a time.

( cd "$PROJ" && env -i PATH="$PATH_SAVE" HOME="$WORK" LC_ALL=C \
    CLAUDE_CONFIG_DIR="$CFG" "$BASH_SAVE" "$HOOK" --project "$PROJ" ) >/dev/null 2>&1
( cd "$PROJ" && env -i PATH="$PATH_SAVE" HOME="$WORK" LC_ALL=C \
    CLAUDE_CONFIG_DIR="$CFG" "$BASH_SAVE" "$HOOK" --project "$PROJ" ) > "$WORK/.stdout" 2>&1
expect "a repeat run still adds exactly one exclude line" 1 \
  "$(grep -c '^session-log\.html$' "$PROJ/.git/info/exclude" 2>/dev/null | tr -d ' ')"
expect_match "and says it was already ignored" "$(cat "$WORK/.stdout")" "already ignored"

# --- 15. a project reached through a symlink ---------------------------------
# The transcript directory is named after the *logical* cwd of the session. On
# macOS `pwd -P` rewrites /var and /tmp, so a resolve-first lookup finds
# nothing. This exercises the physical-path fallback, which otherwise runs only
# on one platform and therefore never runs in CI.

# Pick a project path whose logical and physical forms differ. macOS gives one
# for free (mktemp lives under /var, a symlink to /private/var); elsewhere,
# make one. Then store the transcripts under the PHYSICAL slug and ask for the
# LOGICAL path, so the lookup must miss once and fall back to hit.

LOGICAL="$PROJ"
PHYS="$(cd "$PROJ" && pwd -P)"
if [ "$PHYS" = "$PROJ" ]; then
  ln -s "$PROJ" "$WORK/link" 2>/dev/null
  LOGICAL="$WORK/link"
  PHYS="$(cd "$WORK/link" && pwd -P)"
fi

if [ "$PHYS" = "$LOGICAL" ]; then
  _fail "a symlinked project still finds its transcripts" "could not build a symlinked fixture"
else
  session s14
  add "$(ev_user 'reached through a symlink')"; add "$(ev_asst 'found anyway')"
  # The fixture has to sit where a session run under the *resolved* path would
  # have left it, so the logical slug matches nothing and the fallback must
  # fire. Whether that is a move depends on which branch above ran:
  #
  #   macOS  — LOGICAL is $PROJ under /var, PHYS is /private/var. Different
  #            slugs, so the fixture moves.
  #   Linux  — no such indirection, so we made the symlink ourselves and PHYS
  #            *is* $PROJ. The fixture is already at the physical slug, and
  #            moving it onto itself deletes it.
  PHYS_TDIR="$CFG/projects/$(printf '%s' "$PHYS" | sed 's/[\/.]/-/g')"
  MOVED=0
  if [ "$PHYS_TDIR" != "$TDIR" ]; then
    rm -rf "$PHYS_TDIR"; mv "$TDIR" "$PHYS_TDIR"; MOVED=1
  fi

  ( cd "$LOGICAL" && env -i PATH="$PATH_SAVE" HOME="$WORK" LC_ALL=C \
      CLAUDE_CONFIG_DIR="$CFG" "$BASH_SAVE" "$HOOK" \
      --project "$LOGICAL" --out "$WORK/link.html" --no-exclude ) >/dev/null 2>"$WORK/.stderr"
  RC=$?
  if [ "$RC" -eq 0 ] && grep -q "reached through a symlink" "$WORK/link.html" 2>/dev/null; then
    _pass "a symlinked project falls back to the resolved path"
  else
    _fail "a symlinked project falls back to the resolved path" \
      "exit $RC | $(head -1 "$WORK/.stderr")"
  fi

  # And the fallback must not fire when the logical path is the right one:
  # asking for $PROJ, whose slug is where the fixture lives, has to keep working.
  [ "$MOVED" -eq 1 ] && mv "$PHYS_TDIR" "$TDIR"
  render
  expect_match "and the logical path is still preferred when it exists" "$OUT" "reached through a symlink"
fi

# --- 16. argument handling ---------------------------------------------------

( cd "$PROJ" && env -i PATH="$PATH_SAVE" HOME="$WORK" LC_ALL=C CLAUDE_CONFIG_DIR="$CFG" \
    "$BASH_SAVE" "$HOOK" --limit banana ) >/dev/null 2>"$WORK/.stderr"
RC=$?; ERR="$(cat "$WORK/.stderr")"
if [ "$RC" -ne 0 ]; then _pass "a non-numeric --limit is refused"; else _fail "a non-numeric --limit is refused" "got 0"; fi

( cd "$PROJ" && env -i PATH="$PATH_SAVE" HOME="$WORK" LC_ALL=C CLAUDE_CONFIG_DIR="$CFG" \
    "$BASH_SAVE" "$HOOK" --nonsense ) >/dev/null 2>"$WORK/.stderr"
RC=$?; ERR="$(cat "$WORK/.stderr")"
if [ "$RC" -ne 0 ]; then _pass "an unknown flag is refused"; else _fail "an unknown flag is refused" "got 0"; fi
expect_match "and the refusal says what to try" "$ERR" "--help"

verify_summary

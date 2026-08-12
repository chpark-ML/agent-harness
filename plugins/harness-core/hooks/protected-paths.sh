#!/bin/bash
# protected-paths — block tool calls that touch a protected absolute path
# without an explicit carve-out.
#
# catches  a tool call touching an absolute path under a declared protected
#          prefix, with no carve-out. Silent until a prefix is declared
# scope    PreToolUse, Read/Write/Edit/NotebookEdit/Glob/Grep/Bash
# bypass   HARNESS_ALLOWED_PATHS=/p1:/p2 <command>, or add the path to
#          .claude/allowed-paths.txt
#
# Fills the gap settings.json permission globs cannot: those are relative to
# the project, so anything reached by absolute path — a shared mount, another
# team's export, a production data directory — is outside their reach.
#
# Off by default, and that is the point. A generic harness cannot guess which
# absolute paths matter to a given site, and a guard with an invented default
# either blocks the wrong thing or teaches people to ignore it. The hook stays
# silent until someone declares a protected prefix.
#
# Configuration, in resolution order. Both env vars are colon-separated, like
# PATH, so a prefix may contain spaces:
#   protected  1. HARNESS_PROTECTED_PATHS — replaces both files
#              2. <user config>/protected-paths.txt  ∪  <project>/.claude/protected-paths.txt
#   allowed    HARNESS_ALLOWED_PATHS  ∪  <user config>/allowed-paths.txt
#              ∪  <project>/.claude/allowed-paths.txt
#
# Everything unions except the protected env override, which replaces — that is
# the one direction where you need a way to say "less", and it is scoped to a
# single shell. The user config directory is $CLAUDE_CONFIG_DIR when set,
# otherwise ~/.claude, so the hook behaves the same installed at either level.
#
# A path is blocked when it falls under a protected prefix and under no allowed
# prefix. Matching is on the literal prefix: `/data` covers `/data` and
# `/data/...` but not `/database`.
#
# The Bash tokenizer splits on whitespace, quotes, `=`, redirection characters
# and commas. Redirection matters because `>/data/f` is a write and is the shape
# people actually type; without `>` in the set the token never looks absolute.
#
# Paths are not normalised, and the gap that opens runs in the permissive
# direction: `/tmp/../data/secret` reaches protected data and is NOT caught,
# because the string does not start with a protected prefix. A relative path is
# not examined at all — after a `cd`, `../data/secret` never looks absolute. So
# this is a guard against accidents, not against an adversary, and the deny
# rules in settings.json remain the backstop for the paths that matter most.
#
# The project directory is NOT implicitly allowed. If a project lives inside a
# protected prefix, say so in .claude/allowed-paths.txt; an implicit exception
# would quietly disable the guard exactly where it was asked for.
#
# Exit: 0 allow · 2 block.

set -euo pipefail

if ! type -P jq >/dev/null 2>&1; then
  echo "protected-paths: jq not found — hook disabled. Install jq to enable." >&2
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

read_prefix_file() {
  [ -f "$1" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"   # ltrim
    line="${line%"${line##*[![:space:]]}"}"   # rtrim
    [ -n "$line" ] && printf '%s\n' "$line"
  done < "$1"
  # Must return 0. The loop's last statement is a test-and-print, so a file
  # whose final meaningful line is a comment leaves $? at 1 — and under `set -e`
  # that killed the process substitution below before the SECOND file was read.
  # The shipped user-config template is comments-only, so this silently disabled
  # every project's own list.
  return 0
}

# Two config locations, unioned. The hook can be installed at either level, and
# a machine-wide protection must not disappear because some project happens to
# ship its own list — that would make the guard weakest in exactly the projects
# nobody configured.
PROJECT_CONFIG="${CLAUDE_PROJECT_DIR:-.}/.claude"
USER_CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

PROTECTED=()
if [ -n "${HARNESS_PROTECTED_PATHS:-}" ]; then
  # Whitespace is a plausible guess at the separator, and guessing wrong fails
  # OPEN: `'/a /b'` becomes the single prefix `/a /b`, which matches nothing, so
  # the guard silently stops guarding. Say so rather than let it happen quietly.
  # A value that already contains a colon is using the separator correctly, so a
  # space in it is a real space and draws no warning.
  case "$HARNESS_PROTECTED_PATHS" in
    *:*) ;;
    *" "*)
      echo "protected-paths: HARNESS_PROTECTED_PATHS is colon-separated, so '$HARNESS_PROTECTED_PATHS' is being read as ONE prefix. If you meant several, write '/a:/b'." >&2
      ;;
  esac
  IFS=':' read -r -a PROTECTED <<<"$HARNESS_PROTECTED_PATHS"
else
  while IFS= read -r line; do
    [ -n "$line" ] && PROTECTED+=("$line")
  done < <(read_prefix_file "$USER_CONFIG/protected-paths.txt"
           read_prefix_file "$PROJECT_CONFIG/protected-paths.txt")
fi

# Nothing declared → nothing to guard. Silent by design.
[ ${#PROTECTED[@]} -eq 0 ] && exit 0

ALLOWED=()
if [ -n "${HARNESS_ALLOWED_PATHS:-}" ]; then
  IFS=':' read -r -a env_allowed <<<"$HARNESS_ALLOWED_PATHS"
  ALLOWED+=("${env_allowed[@]+"${env_allowed[@]}"}")
fi
while IFS= read -r line; do
  [ -n "$line" ] && ALLOWED+=("$line")
done < <(read_prefix_file "$USER_CONFIG/allowed-paths.txt"
         read_prefix_file "$PROJECT_CONFIG/allowed-paths.txt")

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // ""')"
[ -z "$tool" ] && exit 0

paths=()
case "$tool" in
  Read|Write|Edit)
    p="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""')"
    [ -n "$p" ] && paths+=("$p")
    ;;
  NotebookEdit)
    p="$(printf '%s' "$input" | jq -r '.tool_input.notebook_path // ""')"
    [ -n "$p" ] && paths+=("$p")
    ;;
  Glob|Grep)
    p="$(printf '%s' "$input" | jq -r '.tool_input.path // ""')"
    [ -n "$p" ] && paths+=("$p")
    ;;
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
    while IFS= read -r tok; do
      [ -n "$tok" ] && paths+=("$tok")
    done < <(printf '%s' "$cmd" | tr -s '[:space:]"'"'"'=<>,' '\n' | grep '^/' || true)
    ;;
  *)
    exit 0
    ;;
esac

violation=""
for path in "${paths[@]+"${paths[@]}"}"; do
  case "$path" in /*) ;; *) continue ;; esac

  is_protected=0
  for pre in "${PROTECTED[@]}"; do
    # An empty entry (a stray ':' in the env list) would match every absolute
    # path. The allowed loop below already guards this; both need it.
    [ -z "$pre" ] && continue
    case "$path" in "$pre"|"$pre"/*) is_protected=1; break ;; esac
  done
  [ $is_protected -eq 0 ] && continue

  is_allowed=0
  for root in "${ALLOWED[@]+"${ALLOWED[@]}"}"; do
    [ -z "$root" ] && continue
    case "$path" in "$root"|"$root"/*) is_allowed=1; break ;; esac
  done

  if [ $is_allowed -eq 0 ]; then
    violation="$path"
    break
  fi
done

if [ -n "$violation" ]; then
  cat >&2 <<EOF
protected-paths blocked tool '$tool': '$violation'
That path is under a protected prefix and no allow rule covers it.
  - if this project should reach it: add the path to .claude/allowed-paths.txt
  - if this is a one-off for this shell: HARNESS_ALLOWED_PATHS=/p1:/p2 <command>
  - if the prefix should not be protected at all: edit .claude/protected-paths.txt
See docs/hooks/protected-paths.md in the agent-harness repo.
EOF
  exit 2
fi

exit 0

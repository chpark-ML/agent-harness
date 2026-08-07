#!/bin/bash
# verify-protected-paths.sh — behavioural verification of the protected-paths hook.
# Run from any cwd:  bash scripts/verify-protected-paths.sh

set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/_verify-lib.sh"
verify_begin protected-paths hooks/protected-paths.sh

# --- fixtures ---------------------------------------------------------------
# Four project directories, differing only in their .claude config, so each
# case names the configuration it is exercising.

mkdir -p "$WORK/none/.claude"

mkdir -p "$WORK/commented/.claude"
cat > "$WORK/commented/.claude/protected-paths.txt" <<'EOF'
# nothing declared yet

#   /example
EOF

mkdir -p "$WORK/basic/.claude"
cat > "$WORK/basic/.claude/protected-paths.txt" <<'EOF'
# team mounts
/data
/mnt/shared
EOF

mkdir -p "$WORK/carve/.claude"
printf '/data\n' > "$WORK/carve/.claude/protected-paths.txt"
printf '# this project owns one corner of it\n/data/project-x\n' > "$WORK/carve/.claude/allowed-paths.txt"

# pcase <name> <expected_exit> <fixture-dir> <json> [VAR=value ...]
pcase() {
  local name="$1" exp="$2" fix="$3" json="$4"; shift 4
  run_case "$name" "$exp" "$json" CLAUDE_PROJECT_DIR="$fix" "$@"
}

# --- off by default ---------------------------------------------------------

pcase "no config file → allow (hook disabled)" 0 "$WORK/none" \
  '{"tool_name":"Read","tool_input":{"file_path":"/data/secret.csv"}}'

pcase "config with only comments → allow (hook disabled)" 0 "$WORK/commented" \
  '{"tool_name":"Read","tool_input":{"file_path":"/data/secret.csv"}}'

pcase "no tool_name → allow" 0 "$WORK/basic" '{}'

pcase "unhandled tool (Task) → allow" 0 "$WORK/basic" \
  '{"tool_name":"Task","tool_input":{"prompt":"read /data/secret.csv"}}'

# --- block, per tool --------------------------------------------------------

pcase "Read under a protected prefix → block" 2 "$WORK/basic" \
  '{"tool_name":"Read","tool_input":{"file_path":"/data/secret.csv"}}'

pcase "Write under a protected prefix → block" 2 "$WORK/basic" \
  '{"tool_name":"Write","tool_input":{"file_path":"/mnt/shared/out.txt","content":"x"}}'

pcase "Edit under a protected prefix → block" 2 "$WORK/basic" \
  '{"tool_name":"Edit","tool_input":{"file_path":"/data/config.yaml"}}'

pcase "NotebookEdit under a protected prefix → block" 2 "$WORK/basic" \
  '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/data/analysis.ipynb"}}'

pcase "Glob rooted at a protected prefix → block" 2 "$WORK/basic" \
  '{"tool_name":"Glob","tool_input":{"path":"/data","pattern":"**/*.csv"}}'

pcase "Grep rooted at a protected prefix → block" 2 "$WORK/basic" \
  '{"tool_name":"Grep","tool_input":{"path":"/mnt/shared","pattern":"key"}}'

pcase "Bash touching a protected path → block" 2 "$WORK/basic" \
  '{"tool_name":"Bash","tool_input":{"command":"rm -rf /data/old"}}'

pcase "Bash with the path after = → block" 2 "$WORK/basic" \
  '{"tool_name":"Bash","tool_input":{"command":"OUT=/mnt/shared/x.log ./run.sh"}}'

pcase "the prefix itself → block" 2 "$WORK/basic" \
  '{"tool_name":"Read","tool_input":{"file_path":"/data"}}'

# --- boundary: look-alikes must pass ----------------------------------------

pcase "/database is not under /data → allow" 0 "$WORK/basic" \
  '{"tool_name":"Read","tool_input":{"file_path":"/database/schema.sql"}}'

pcase "/mnt/shared-old is not under /mnt/shared → allow" 0 "$WORK/basic" \
  '{"tool_name":"Read","tool_input":{"file_path":"/mnt/shared-old/x"}}'

pcase "relative path → allow (only absolute paths are matched)" 0 "$WORK/basic" \
  '{"tool_name":"Read","tool_input":{"file_path":"data/local.csv"}}'

pcase "Read via tool_input.path instead of file_path → block" 2 "$WORK/basic" \
  '{"tool_name":"Read","tool_input":{"path":"/data/secret.csv"}}'

# Known gap, asserted so it cannot change silently: matching is on the literal
# prefix, so a path that traverses INTO a protected prefix is not caught. The
# header documents this; settings.json deny rules are the backstop.
pcase "known gap: traversal into a protected prefix is not caught → allow" 0 "$WORK/basic" \
  '{"tool_name":"Read","tool_input":{"file_path":"/tmp/../data/secret.csv"}}'

pcase "traversal OUT of a protected prefix is still blocked (prefix matched)" 2 "$WORK/basic" \
  '{"tool_name":"Read","tool_input":{"file_path":"/data/../tmp/x"}}'

pcase "Bash with no absolute path → allow" 0 "$WORK/basic" \
  '{"tool_name":"Bash","tool_input":{"command":"npm test && git status"}}'

# --- allow list -------------------------------------------------------------

pcase "carve-out path → allow" 0 "$WORK/carve" \
  '{"tool_name":"Write","tool_input":{"file_path":"/data/project-x/out.json"}}'

pcase "sibling of the carve-out → block" 2 "$WORK/carve" \
  '{"tool_name":"Write","tool_input":{"file_path":"/data/project-y/out.json"}}'

# --- environment overrides --------------------------------------------------

pcase "HARNESS_PROTECTED_PATHS protects a path the file does not" 2 "$WORK/basic" \
  '{"tool_name":"Read","tool_input":{"file_path":"/scratch/x"}}' \
  HARNESS_PROTECTED_PATHS="/scratch"

pcase "HARNESS_PROTECTED_PATHS replaces the file rather than adding to it" 0 "$WORK/basic" \
  '{"tool_name":"Read","tool_input":{"file_path":"/data/secret.csv"}}' \
  HARNESS_PROTECTED_PATHS="/scratch"

pcase "HARNESS_PROTECTED_PATHS is colon-separated (second entry)" 2 "$WORK/none" \
  '{"tool_name":"Read","tool_input":{"file_path":"/vault/x"}}' \
  HARNESS_PROTECTED_PATHS="/scratch:/vault"

pcase "colon-separated entries may contain spaces" 2 "$WORK/none" \
  '{"tool_name":"Read","tool_input":{"file_path":"/my data/x"}}' \
  HARNESS_PROTECTED_PATHS="/my data"

pcase "HARNESS_ALLOWED_PATHS unions with the allow file" 0 "$WORK/carve" \
  '{"tool_name":"Read","tool_input":{"file_path":"/data/project-z/x"}}' \
  HARNESS_ALLOWED_PATHS="/data/project-z:/data/project-w"

pcase "the allow file still applies when the env allow list is set" 0 "$WORK/carve" \
  '{"tool_name":"Read","tool_input":{"file_path":"/data/project-x/x"}}' \
  HARNESS_ALLOWED_PATHS="/data/project-z"

# --- user-level config ------------------------------------------------------
# The hook installs at either level, so it reads the user config directory as
# well as the project's, and unions them. A machine-wide protection that a
# project's own list could silently drop would be weakest exactly where nobody
# configured anything.

mkdir -p "$WORK/usercfg"
printf '/machine-wide\n' > "$WORK/usercfg/protected-paths.txt"
printf '/machine-wide/ok\n' > "$WORK/usercfg/allowed-paths.txt"

pcase "user config alone protects, with no project config" 2 "$WORK/none" \
  '{"tool_name":"Read","tool_input":{"file_path":"/machine-wide/x"}}' \
  CLAUDE_CONFIG_DIR="$WORK/usercfg"

pcase "user carve-out applies" 0 "$WORK/none" \
  '{"tool_name":"Read","tool_input":{"file_path":"/machine-wide/ok/x"}}' \
  CLAUDE_CONFIG_DIR="$WORK/usercfg"

pcase "project list still applies alongside the user list" 2 "$WORK/basic" \
  '{"tool_name":"Read","tool_input":{"file_path":"/data/secret.csv"}}' \
  CLAUDE_CONFIG_DIR="$WORK/usercfg"

pcase "user list still applies alongside the project list" 2 "$WORK/basic" \
  '{"tool_name":"Read","tool_input":{"file_path":"/machine-wide/x"}}' \
  CLAUDE_CONFIG_DIR="$WORK/usercfg"

pcase "the protected env override replaces both files" 0 "$WORK/basic" \
  '{"tool_name":"Read","tool_input":{"file_path":"/machine-wide/x"}}' \
  CLAUDE_CONFIG_DIR="$WORK/usercfg" HARNESS_PROTECTED_PATHS="/elsewhere"

# --- a comments-only user config must not suppress the project config --------
# Regression: read_prefix_file ended in a test-and-print, so a file whose last
# meaningful line was a comment returned 1 and `set -e` killed the process
# substitution before the second file was read. The shipped user template is
# comments-only, so this silently disabled every project's own list.

mkdir -p "$WORK/usercfg-comments"
printf '# nothing declared here\n#   /example\n' > "$WORK/usercfg-comments/protected-paths.txt"

pcase "comments-only user config still lets the project config load" 2 "$WORK/basic" \
  '{"tool_name":"Read","tool_input":{"file_path":"/data/secret.csv"}}' \
  CLAUDE_CONFIG_DIR="$WORK/usercfg-comments"

pcase "...and the same for a Bash path" 2 "$WORK/basic" \
  '{"tool_name":"Bash","tool_input":{"command":"cat /data/secret.csv"}}' \
  CLAUDE_CONFIG_DIR="$WORK/usercfg-comments"

# --- shapes the tokenizer used to miss ---------------------------------------

pcase "redirection written without a space → block" 2 "$WORK/basic" \
  '{"tool_name":"Bash","tool_input":{"command":"echo pwned >/data/overwritten.csv"}}'

pcase "append redirection without a space → block" 2 "$WORK/basic" \
  '{"tool_name":"Bash","tool_input":{"command":"date >>/data/audit.log"}}'

pcase "input redirection without a space → block" 2 "$WORK/basic" \
  '{"tool_name":"Bash","tool_input":{"command":"wc -l </data/secret.csv"}}'

pcase "comma-separated path → block" 2 "$WORK/basic" \
  '{"tool_name":"Bash","tool_input":{"command":"cp a,/data/x ."}}'

# --- a prefix containing shell metacharacters ---------------------------------
# Regression: the line was passed through xargs, whose quote parsing dropped a
# prefix containing an apostrophe and rewrote ones containing " or \.

mkdir -p "$WORK/quoted/.claude"
printf "/data/o'brien\n/data/say\"hi\"\n" > "$WORK/quoted/.claude/protected-paths.txt"

pcase "prefix containing an apostrophe still guards" 2 "$WORK/quoted" \
  '{"tool_name":"Read","tool_input":{"file_path":"/data/o'"'"'brien/secret.csv"}}'

pcase "prefix containing double quotes still guards" 2 "$WORK/quoted" \
  '{"tool_name":"Read","tool_input":{"file_path":"/data/say\"hi\"/x"}}'

# --- an empty separator component must not become deny-all --------------------
# Regression: an empty entry made the pattern "$pre"|"$pre"/* degenerate to
# ""|/*, matching every absolute path, with a message naming an unrelated file.

pcase "leading empty colon component → does not block unrelated paths" 0 "$WORK/none" \
  '{"tool_name":"Read","tool_input":{"file_path":"/Users/me/notes.txt"}}' \
  HARNESS_PROTECTED_PATHS=":/data"

pcase "interior empty colon component → does not block unrelated paths" 0 "$WORK/none" \
  '{"tool_name":"Bash","tool_input":{"command":"ls /usr/local/bin"}}' \
  HARNESS_PROTECTED_PATHS="/a::/b"

pcase "...and the real entries in that list still guard" 2 "$WORK/none" \
  '{"tool_name":"Read","tool_input":{"file_path":"/data/x"}}' \
  HARNESS_PROTECTED_PATHS=":/data"

# --- the separator is a plausible thing to guess wrong ----------------------
# Guessing whitespace fails OPEN — the value becomes one prefix that matches
# nothing — so the hook has to say something rather than quietly stop guarding.

run_hook '{"tool_name":"Read","tool_input":{"file_path":"/a/secret"}}' \
  CLAUDE_PROJECT_DIR="$WORK/none" HARNESS_PROTECTED_PATHS="/a /b"
expect "whitespace-separated value still exits 0 (it protects nothing)" 0 "$RC"
expect_match "...but warns that it was read as one prefix" "$ERR" "ONE prefix"

run_hook '{"tool_name":"Read","tool_input":{"file_path":"/my data/x"}}' \
  CLAUDE_PROJECT_DIR="$WORK/none" HARNESS_PROTECTED_PATHS="/my data:/other"
expect "a correctly colon-separated value containing a space → block" 2 "$RC"
expect_absent "...and draws no separator warning" "$ERR" "ONE prefix"

# --- the fail-open branch ----------------------------------------------------

run_case "jq missing → allow, and say so" 0 \
  '{"tool_name":"Read","tool_input":{"file_path":"/data/secret.csv"}}' \
  CLAUDE_PROJECT_DIR="$WORK/basic" PATH=/nonexistent
expect_match "...with a warning naming the hook" "$ERR" "protected-paths"

# --- the block message has to be actionable ---------------------------------

run_hook '{"tool_name":"Read","tool_input":{"file_path":"/data/secret.csv"}}' CLAUDE_PROJECT_DIR="$WORK/basic"
expect_match "block message names the offending path" "$ERR" "/data/secret.csv"
expect_match "block message names the allow file" "$ERR" "allowed-paths.txt"
expect_empty "block writes nothing to stdout" "$OUT"

verify_summary

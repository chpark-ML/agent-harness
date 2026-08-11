#!/bin/bash
# secret-scrubber — block Bash commands that carry a literal secret.
#
# catches  a Bash command carrying a literal secret — API keys, tokens, AWS keys,
#          private-key headers
# scope    PreToolUse, Bash
# bypass   none by design; rewrite the command to read the value from the
#          environment or a file instead
#
# Catches the "pasted the API key straight into the command" failure mode. Once
# a key reaches the shell it is in history, in the process table, and often in
# a log; the only real fix afterwards is rotation, so the cheap move is to
# never let it be typed.
#
# Scope: the Bash tool only. File contents are deliberately not scanned —
# fixtures, docs and tests legitimately contain key-shaped strings, and a guard
# that cries wolf gets disabled.
#
# Detection: high-confidence vendor token formats, plus environment-style
# assignments to KEY/SECRET/TOKEN/PASSWORD names whose value is a substantive
# (12+ char) literal. `KEY=$VAR` does not match — the literal `$` is outside
# the value character class — so the recommended fix is also the one that
# passes.
#
# Two properties of the assignment rule worth knowing before you tune it. The
# name list is unanchored, which is deliberate: it is what makes MYSQL_PASSWORD
# and DEPLOY_PRIVATE_KEY match. The value class admits `/` and `.`, which means
# a long literal path assigned to a secret-shaped name is blocked too — a false
# positive we accept, because narrowing the class would let base64 and
# dot-separated tokens through.
#
# Bypass: rotate the leaked value, then re-issue the command through a shell
# variable. There is deliberately no env-var escape hatch.
#
# Exit: 0 allow · 2 block (stderr is fed back to the model as feedback).

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "secret-scrubber: jq not found — hook disabled. Install jq to enable." >&2
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

# Each entry: "label|extended-regex", split on the FIRST pipe. Order = priority
# (first match wins). The regex may contain alternation; the label may not — a
# pipe in a label would silently move its tail into the pattern, turning it
# into a literal that matches almost nothing.
#
# The two OpenAI entries use different character classes on purpose, and it is
# not an oversight to tidy up. The scoped families (sk-proj-, sk-svcacct-,
# sk-admin-) really do contain `_` and `-`; the legacy sk- format is plain
# base62. Widening the legacy class to match the scoped one buys nothing — no
# such key exists — and costs real false positives, because a long kebab-case
# identifier that happens to start with `sk-` then reads as a key. That was
# tried; `git switch -c sk-refactor-the-whole-data-loading-layer` got blocked.
PATTERNS=(
  'Anthropic API key (sk-ant-...)|sk-ant-api03-[A-Za-z0-9_-]{40,}'
  'OpenAI scoped key (sk-proj-/sk-svcacct-/sk-admin-)|sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{40,}'
  'OpenAI legacy API key (sk-...)|sk-[A-Za-z0-9]{40,}'
  'GitHub personal access token (ghp_...)|ghp_[A-Za-z0-9]{36,}'
  'GitHub token (gho_/ghu_/ghs_/ghr_)|gh[ousr]_[A-Za-z0-9]{36,}'
  'GitHub fine-grained token (github_pat_...)|github_pat_[A-Za-z0-9_]{40,}'
  'Slack token (xox...-...)|xox[abprs]-[A-Za-z0-9-]{20,}'
  'AWS access key ID (AKIA...)|AKIA[0-9A-Z]{16}'
  'AWS temporary access key (ASIA...)|ASIA[0-9A-Z]{16}'
  'Google API key (AIza...)|AIza[0-9A-Za-z_-]{35}'
  'PEM private key block|-----BEGIN[A-Z ]*PRIVATE KEY-----'
)

# Searching *for* leaked secrets is the one thing this guard must not obstruct,
# and "rotate the value" is nonsense advice for a grep. Exempt a command whose
# first word is a read-only search tool — but only when it is the whole command,
# so `grep x && curl -d KEY=...` is still inspected.
case "$cmd" in
  *[\;\&\|]*) ;;
  grep\ *|rg\ *|ag\ *|ack\ *|git\ grep\ *) exit 0 ;;
esac

# The name list is matched case-insensitively — `api_key=` is the same mistake
# as `API_KEY=` — while the value class stays exactly as narrow as before.
if printf '%s' "$cmd" | grep -qEi '(API_KEY|APIKEY|SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE_KEY|ACCESS_KEY)=["'"'"']?[A-Za-z0-9+/=._-]{12,}'; then
  cat >&2 <<EOF
secret-scrubber blocked Bash: detected env-style secret assignment (KEY/SECRET/TOKEN/PASSWORD=literal)
A literal secret in a command is already compromised — rotate the value, then
reference it through the environment instead: 'KEY=\$REAL_KEY <command>'.
See docs/hooks/secret-scrubber.md in the agent-harness repo.
EOF
  exit 2
fi

for entry in "${PATTERNS[@]}"; do
  label="${entry%%|*}"
  pattern="${entry#*|}"
  if printf '%s' "$cmd" | grep -qE -- "$pattern"; then
    cat >&2 <<EOF
secret-scrubber blocked Bash: detected $label
A literal secret in a command is already compromised — rotate the value, then
reference it through the environment instead: 'KEY=\$REAL_KEY <command>'.
See docs/hooks/secret-scrubber.md in the agent-harness repo.
EOF
    exit 2
  fi
done

exit 0

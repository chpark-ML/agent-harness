#!/bin/bash
# verify-secret-scrubber.sh — behavioural verification of the secret-scrubber hook.
# Run from any cwd:  bash scripts/verify-secret-scrubber.sh

set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/_verify-lib.sh"
verify_begin secret-scrubber hooks/secret-scrubber.sh

# --- no-op: the hook must stay out of the way -------------------------------

run_case "no tool_name → allow" 0 '{}'

run_case "non-Bash tool (Read) → allow" 0 \
  '{"tool_name":"Read","tool_input":{"file_path":"secrets.md"}}'

run_case "Bash with empty command → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":""}}'

run_case "benign command → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"ls -la /tmp && git status"}}'

# --- boundary: the recommended fix must itself pass -------------------------

run_case 'KEY=$VAR expansion → allow (literal $ is outside the value class)' 0 \
  '{"tool_name":"Bash","tool_input":{"command":"API_KEY=$REAL_KEY python train.py"}}'

run_case 'value read from a command → allow' 0 \
  '{"tool_name":"Bash","tool_input":{"command":"TOKEN=$(cat ~/.token) curl -H \"Authorization: Bearer $TOKEN\" api.example.com"}}'

run_case "short assignment under 12 chars → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"DEBUG_TOKEN=ab12 echo ok"}}'

run_case "non-secret name with a long value → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"OUTPUT_PATH=/very/long/path/to/somewhere/output.json python run.py"}}'

run_case "prose mentioning sk- but not key-shaped → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"document the sk- prefix used by vendor keys\""}}'

# The legacy sk- class is base62 for exactly this reason. Widening it to admit
# `_` and `-` blocked both of these; the boundary is pinned in both directions
# so the next person to "tidy up" the inconsistent classes finds out here.
run_case "long kebab-case branch name starting with sk- → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git switch -c sk-refactor-the-whole-data-loading-layer-for-real"}}'

run_case "long kebab-case identifier in a commit message → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"rename sk-learn-preprocessing-pipeline-v2-final-experiment\""}}'

# --- block: literal vendor tokens -------------------------------------------

run_case "Anthropic API key → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"export ANTHROPIC_API_KEY=sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}}'

run_case "OpenAI project key → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"openai --api-key sk-proj-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA models list"}}'

run_case "legacy sk- token → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"curl -H \"Authorization: Bearer sk-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\" api.example.com"}}'

run_case "sk-svcacct- scoped key with an underscore → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"export OPENAI_API_KEY=sk-svcacct-aaaaaaaaaa_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'

run_case "GitHub PAT embedded in a remote URL → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"git remote set-url origin https://ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@github.com/x/y.git"}}'

run_case "GitHub server token (ghs_) → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"curl -H \"Authorization: token ghs_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\" api.github.com"}}'

run_case "GitHub fine-grained token → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"gh auth login --with-token <<< github_pat_11AAAAAAA0aaaaaaaaaa_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'

run_case "Slack bot token → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"curl -d token=xoxb-EXAMPLE-NOT-A-REAL-TOKEN-000000 https://slack.com/api/auth.test"}}'

run_case "AWS access key ID → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"aws configure set aws_access_key_id AKIAIOSFODNN7EXAMPLE"}}'

run_case "AWS temporary access key → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"export AWS_ACCESS_KEY_ID=ASIAIOSFODNN7EXAMPLE"}}'

run_case "Google API key → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"curl \"https://maps.googleapis.com/maps/api/geocode/json?key=AIzaSyA0aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\""}}'

run_case "PEM private key header → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"echo -----BEGIN RSA PRIVATE KEY----- > /tmp/deploy.pem"}}'

# --- block: env-style assignments -------------------------------------------

run_case "API_KEY=literal → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"API_KEY=abcdef0123456789xyzABC ./deploy.sh"}}'

run_case 'PASSWORD="quoted literal" → block' 2 \
  '{"tool_name":"Bash","tool_input":{"command":"MYSQL_PASSWORD=\"hunter22hunter22hunter\" mysql -u root"}}'

run_case "SECRET='single-quoted literal' → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"export APP_SECRET='\''abcdefghijklmnopqrst'\''"}}'

run_case "PRIVATE_KEY=literal → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"export DEPLOY_PRIVATE_KEY=abcdefghijklmnopqrstuvwxyz"}}'

# --- the assignment name list is case-insensitive ----------------------------

run_case "lowercase api_key= → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"curl -d \"api_key=abcdef0123456789xyzABC\" https://api.example.com"}}'

run_case "mixed-case Api_Key= → block" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"Api_Key=abcdef0123456789xyzABC ./deploy.sh"}}'

# --- searching for leaked secrets must not be obstructed ---------------------
# "rotate the value" is nonsense advice for a grep, and this is the one thing a
# secret guard should never get in the way of. The sibling ai-attribution-guard
# already treats a grep for its own pattern as legitimate.

run_case "grep for a PEM header → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"grep -rn -- \"-----BEGIN RSA PRIVATE KEY-----\" /etc/ssl"}}'

run_case "rg for an AWS key shape → allow" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"rg AKIAIOSFODNN7EXAMPLE ."}}'

run_case "a search chained into something else → still inspected" 2 \
  '{"tool_name":"Bash","tool_input":{"command":"grep -q x f && export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"}}'

run_case "jq missing → allow, and say so" 0 \
  '{"tool_name":"Bash","tool_input":{"command":"export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"}}' \
  PATH=/nonexistent
expect_match "...with a warning naming the hook" "$ERR" "secret-scrubber"

# --- the block message has to be actionable ---------------------------------

run_hook '{"tool_name":"Bash","tool_input":{"command":"export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"}}'
expect_match "block message names the detected kind" "$ERR" "AWS access key ID"
expect_match "block message states the fix" "$ERR" "rotate"
expect_empty "block writes nothing to stdout" "$OUT"

verify_summary

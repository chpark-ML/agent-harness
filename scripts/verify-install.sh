#!/bin/bash
# verify-install.sh — end-to-end verification of harnessctl against a scratch
# consumer project.
#
# This is the installer's regression net, and the properties it pins down are
# the ones a consumer would only discover by losing something:
#
#   - a settings.json the project already had survives intact
#   - re-running install changes nothing (idempotence)
#   - templates are never overwritten, managed files always are
#   - dropping a module removes its files
#   - a file at a managed path that the harness does not own aborts the install
#     before anything is written
#   - uninstall restores settings.json to the byte-for-byte* original
#
#   * canonically: compared as `jq -S`, since install re-serialises the file.
#
# Harness-repo only — not shipped to consumers.
# Run:  bash scripts/verify-install.sh

set -uo pipefail

HARNESS="$(cd "$(dirname "$0")/.." && pwd)"
HCTL="$HARNESS/plugins/harness-core/bin/harnessctl"
BASH_BIN="${BASH:-bash}"

command -v jq >/dev/null 2>&1 || { echo "verify-install: jq is required" >&2; exit 1; }
[ -f "$HCTL" ] || { echo "verify-install: $HCTL not found" >&2; exit 1; }

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
FAILED=""

ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() {
  FAIL=$((FAIL + 1)); FAILED="$FAILED$1
"
  printf '  FAIL  %s\n' "$1"
  [ -n "${2:-}" ] && printf '        %s\n' "$2"
  return 0
}
check() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "${3:-}"; fi; }

section() { printf '\n--- %s\n' "$1"; }

# Content fingerprint of a whole tree — path plus contents, .git excluded.
tree_hash() {
  ( cd "$1" 2>/dev/null && find . -type f -not -path './.git/*' | LC_ALL=C sort \
    | while IFS= read -r f; do printf '%s ' "$f"; cksum < "$f"; done ) | cksum
}

# A consumer project with a settings.json that already has opinions: an
# unrelated top-level key, an existing allow entry, a deliberately empty deny
# tier, no ask tier at all, and hooks registered in the very event/matcher
# slots the harness also uses.
new_consumer() {
  local c="$1" bare="${2:-}"
  mkdir -p "$c/.claude"
  git -C "$c" init -q
  git -C "$c" config user.email verify@example.invalid
  git -C "$c" config user.name verify
  [ -n "$bare" ] && return 0
  cat > "$c/.claude/settings.json" <<'EOF'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "statusLine": { "type": "command", "command": "~/.claude/statusline.sh", "padding": 0 },
  "permissions": {
    "allow": ["Bash(echo consumer-owned:*)"],
    "deny": []
  },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "bash .claude/hooks/mine/audit.sh" }] }
    ],
    "Stop": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "bash .claude/hooks/mine/notify.sh" }] }
    ]
  }
}
EOF
  printf 'node_modules/\n*.log\n' > "$c/.gitignore"
}

run_install() { ( cd "$1" && shift && "$BASH_BIN" "$HCTL" init "$@" ); }
run_uninst() { ( cd "$1" && shift && "$BASH_BIN" "$HCTL" uninstall "$@" ); }

echo "=== harnessctl verification ==="
echo "Harness: $HARNESS"
echo "bash:    $("$BASH_BIN" --version | head -1)"

# --- 0. harness hygiene ------------------------------------------------------
section "harness tree"

missing_x=""
while IFS= read -r f; do
  [ -x "$f" ] || missing_x="$missing_x $f"
done < <(find "$HARNESS/plugins" -name '*.sh' -type f; printf '%s\n' "$HCTL")
check "every shipped script is executable" "$([ -z "$missing_x" ] && echo 0 || echo 1)" "not executable:$missing_x"

json_bad=""
for f in "$HARNESS/.claude-plugin/marketplace.json" "$HARNESS"/plugins/*/.claude-plugin/plugin.json \
         "$HARNESS/plugins/harness-core/hooks/hooks.json" "$HARNESS/plugins/harness-core/declarative/settings-fragment.json"; do
  [ -f "$f" ] || { json_bad="$json_bad MISSING:$f"; continue; }
  jq empty "$f" 2>/dev/null || json_bad="$json_bad $f"
done
check "every plugin/marketplace JSON is valid" "$([ -z "$json_bad" ] && echo 0 || echo 1)" "invalid:$json_bad"

# The fragment must not carry hooks: the plugin owns those now, and a stray
# hooks block here would register them a second time.
check "settings fragment carries no hooks block" \
  "$(jq -e 'has("hooks") | not' "$HARNESS/plugins/harness-core/declarative/settings-fragment.json" >/dev/null 2>&1 && echo 0 || echo 1)"

# Every hook the plugin registers must exist and be executable.
unresolved=""
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  rel="$(printf '%s' "$cmd" | sed -n 's|.*\${CLAUDE_PLUGIN_ROOT}/\([^"]*\)".*|\1|p')"
  [ -n "$rel" ] || { unresolved="$unresolved (unparsable:$cmd)"; continue; }
  { [ -f "$HARNESS/plugins/harness-core/$rel" ] && [ -x "$HARNESS/plugins/harness-core/$rel" ]; } \
    || unresolved="$unresolved $rel"
done < <(jq -r '[.. | objects | select(has("command")) | .command][]' "$HARNESS/plugins/harness-core/hooks/hooks.json")
check "every hooks.json registration resolves to an executable file" \
  "$([ -z "$unresolved" ] && echo 0 || echo 1)" "unresolved:$unresolved"

check "marketplace lists every plugin directory" \
  "$([ "$(jq -r '.plugins|length' "$HARNESS/.claude-plugin/marketplace.json")" = "$(ls -d "$HARNESS"/plugins/*/ | wc -l | tr -d ' ')" ] && echo 0 || echo 1)"

# --- 1. install over an opinionated settings.json ----------------------------
section "--with repeats accumulate"

# `--with dev --with research` is a reasonable thing to type. Overwriting on the
# second flag drops a module the user explicitly asked for and says nothing.
C="$WORK/c0"
new_consumer "$C"
run_install "$C" --with dev --with research >/dev/null 2>&1
[ -f "$C/.claude/rules/harness/dev/review.md" ]
check "repeated --with keeps the first module (dev)" $?
[ -f "$C/.claude/rules/harness/research/notes.md" ]
check "repeated --with keeps the second module (research)" $?

section "install --with dev,research"

C="$WORK/c1"
new_consumer "$C"
BEFORE_SETTINGS="$(jq -S . "$C/.claude/settings.json")"
BEFORE_GITIGNORE="$(cat "$C/.gitignore")"

out="$(run_install "$C" --with dev,research 2>&1)"
rc=$?
check "install exits 0" "$rc" "$(printf '%s' "$out" | tail -5)"

M="$C/.claude/harness-manifest.json"
jq empty "$M" 2>/dev/null
check "manifest is valid JSON" $?

missing=""
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  [ -e "$C/$rel" ] || missing="$missing $rel"
done < <(jq -r '((.files.managed // []) + (.files.template // []))[]' "$M")
check "every manifest-listed file exists on disk" "$([ -z "$missing" ] && echo 0 || echo 1)" "missing:$missing"

check "manifest records both modules" \
  "$([ "$(jq -r '.modules | sort | join(",")' "$M")" = "dev,research" ] && echo 0 || echo 1)" \
  "got $(jq -c '.modules' "$M")"

for f in CLAUDE.md .claude/rules/harness/workflow.md .claude/protected-paths.txt \
         .claude/rules/harness/dev/review.md .claude/rules/harness/research/notes.md; do
  [ -e "$C/$f" ]; check "installed $f" $?
done

# Hooks, skills, commands and verifiers are the plugin's job. harnessctl
# writing any of them would mean two copies drifting apart.
for f in .claude/hooks .claude/skills .claude/commands .claude/scripts; do
  [ ! -e "$C/$f" ]; check "harnessctl did not write $f (plugin territory)" $?
done

# A module rule links to core's workflow.md by relative path. Those links only
# resolve once harnessctl has assembled them in a consumer, so this is the only
# place they can be checked at all.
broken=""
while IFS= read -r f; do
  d="$(dirname "$f")"
  while IFS= read -r target; do
    target="${target%%#*}"
    [ -n "$target" ] || continue
    [ -e "$d/$target" ] || broken="$broken ${f#$C/}→$target"
  done < <(grep -o '](\.\{1,2\}/[^)]*)' "$f" 2>/dev/null | sed 's/^](//; s/)$//')
done < <(find "$C" -name '*.md' -not -path '*/.git/*')
check "relative links in the installed markdown resolve" \
  "$([ -z "$broken" ] && echo 0 || echo 1)" "broken:$broken"

# --- 2. the consumer's own settings survive ----------------------------------
section "consumer settings preserved"

S="$C/.claude/settings.json"
check "unrelated top-level key (statusLine) untouched" \
  "$([ "$(jq -c '.statusLine' "$S")" = '{"type":"command","command":"~/.claude/statusline.sh","padding":0}' ] && echo 0 || echo 1)"
check "\$schema untouched" "$([ "$(jq -r '."$schema"' "$S")" != "null" ] && echo 0 || echo 1)"
check "consumer allow entry survives" \
  "$(jq -e '.permissions.allow | index("Bash(echo consumer-owned:*)")' "$S" >/dev/null 2>&1 && echo 0 || echo 1)"
check "consumer PreToolUse hook survives" \
  "$(jq -e '[.hooks.PreToolUse[].hooks[].command] | index("bash .claude/hooks/mine/audit.sh")' "$S" >/dev/null 2>&1 && echo 0 || echo 1)"
check "consumer Stop hook survives" \
  "$(jq -e '[.hooks.Stop[].hooks[].command] | index("bash .claude/hooks/mine/notify.sh")' "$S" >/dev/null 2>&1 && echo 0 || echo 1)"

# The strongest property of the split: harnessctl has no business in .hooks at
# all, so the consumer's hooks block must come back byte-identical.
check "the consumer's .hooks block is byte-identical after install" \
  "$([ "$(jq -Sc '.hooks' "$S")" = "$(printf '%s' "$BEFORE_SETTINGS" | jq -Sc '.hooks')" ] && echo 0 || echo 1)" \
  "$(jq -Sc '.hooks' "$S")"
check "no harness hook registration was added" \
  "$(jq -e '[.. | objects | select(has("command")) | .command | select(contains("harness"))] | length == 0' "$S" >/dev/null 2>&1 && echo 0 || echo 1)"
check "includeCoAuthoredBy set to false" \
  "$([ "$(jq -r '.includeCoAuthoredBy' "$S")" = "false" ] && echo 0 || echo 1)"
check "ask tier created" "$([ "$(jq '.permissions.ask | length' "$S")" -gt 0 ] && echo 0 || echo 1)"
check ".gitignore keeps its existing entries" \
  "$(grep -qxF 'node_modules/' "$C/.gitignore" && echo 0 || echo 1)"
check ".gitignore gained settings.local.json" \
  "$(grep -qxF '.claude/settings.local.json' "$C/.gitignore" && echo 0 || echo 1)"

# --- 2b. guards added after the review ---------------------------------------

# The docs promised a warning when the consumer already set one of our scalars,
# and the code silently did nothing — leaving includeCoAuthoredBy true defeats
# the guard the harness exists to provide.
CW="$WORK/cwarn"
new_consumer "$CW" bare
printf '{"includeCoAuthoredBy": true}' > "$CW/.claude/settings.json"
out="$(run_install "$CW" 2>&1)"
check "a conflicting scalar draws a warning" \
  "$(printf '%s' "$out" | grep -q 'includeCoAuthoredBy' && echo 0 || echo 1)" \
  "$(printf '%s' "$out" | tail -3)"
check "...and the consumer's value is left alone" \
  "$([ "$(jq -r '.includeCoAuthoredBy' "$CW/.claude/settings.json")" = "true" ] && echo 0 || echo 1)"
run_uninst "$CW" >/dev/null 2>&1
check "...and uninstall does not take a scalar it never set" \
  "$([ "$(jq -r '.includeCoAuthoredBy' "$CW/.claude/settings.json")" = "true" ] && echo 0 || echo 1)"

# A committed manifest can be corrupted by a merge conflict. Both commands used
# to die with raw jq errors and no stated way out.
CB="$WORK/cbroken"
new_consumer "$CB" bare
run_install "$CB" >/dev/null 2>&1
printf '<<<<<<< HEAD\n{}\n' > "$CB/.claude/harness-manifest.json"
out="$(run_install "$CB" 2>&1)"; rc=$?
check "a corrupt manifest aborts rather than emitting jq errors" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check "...and the message says how to recover" \
  "$(printf '%s' "$out" | grep -q 'rm ' && echo 0 || echo 1)"

# jq empty accepts [] and null, so a settings.json that is valid JSON but not an
# object used to pass preflight and explode mid-merge, after files were written.
CA="$WORK/carray"
new_consumer "$CA" bare
printf '[]' > "$CA/.claude/settings.json"
out="$(run_install "$CA" 2>&1)"; rc=$?
check "a non-object settings.json is rejected in preflight" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check "...before any file is written" "$([ ! -e "$CA/CLAUDE.md" ] && echo 0 || echo 1)"

# --- 3. idempotence ----------------------------------------------------------
section "idempotence"

nbak() { find "$1/.claude" -name 'settings.json.bak-*' 2>/dev/null | wc -l | tr -d ' '; }

H1="$(tree_hash "$C")"
B1="$(nbak "$C")"
out="$(run_install "$C" 2>&1)"; rc=$?
H2="$(tree_hash "$C")"
check "re-install exits 0" "$rc"
check "re-install changes nothing on disk" "$([ "$H1" = "$H2" ] && echo 0 || echo 1)"
check "re-install reports no settings change" \
  "$(printf '%s' "$out" | grep -q '변경 없음' && echo 0 || echo 1)"
# A run that rewrites nothing must not leave a snapshot either, or the project
# accumulates one .bak file per no-op install.
check "re-install writes no new backup" "$([ "$B1" = "$(nbak "$C")" ] && echo 0 || echo 1)" \
  "$B1 → $(nbak "$C")"
check "the first install did take a snapshot" "$([ "$B1" -ge 1 ] && echo 0 || echo 1)"
check "re-install keeps the module set" \
  "$([ "$(jq -r '.modules | sort | join(",")' "$M")" = "dev,research" ] && echo 0 || echo 1)"

# --- 4. two tiers behave differently -----------------------------------------
section "managed vs template"

printf '\n<!-- my own project rule -->\n' >> "$C/CLAUDE.md"
TMPL_EDITED="$(cksum < "$C/CLAUDE.md")"
printf '\n# local scribble\n' >> "$C/.claude/rules/harness/workflow.md"
run_install "$C" >/dev/null 2>&1
check "template edit is preserved" \
  "$([ "$(cksum < "$C/CLAUDE.md")" = "$TMPL_EDITED" ] && echo 0 || echo 1)"
check "managed edit is overwritten" \
  "$(cmp -s "$C/.claude/rules/harness/workflow.md" "$HARNESS/plugins/harness-core/declarative/rules/core/workflow.md" && echo 0 || echo 1)"

# --- 5. dropping a module ----------------------------------------------------
section "module selection"

run_install "$C" --with dev >/dev/null 2>&1
check "research rule removed when the module is dropped" \
  "$([ ! -e "$C/.claude/rules/harness/research/notes.md" ] && echo 0 || echo 1)"
check "research rule directory pruned" \
  "$([ ! -d "$C/.claude/rules/harness/research" ] && echo 0 || echo 1)"
check "dev rule still present" "$([ -e "$C/.claude/rules/harness/dev/review.md" ] && echo 0 || echo 1)"
check "core still present" "$([ -e "$C/.claude/rules/harness/workflow.md" ] && echo 0 || echo 1)"
check "manifest records only dev" \
  "$([ "$(jq -r '.modules | join(",")' "$M")" = "dev" ] && echo 0 || echo 1)" "got $(jq -c '.modules' "$M")"

run_install "$C" --with dev,research >/dev/null 2>&1
check "re-adding the module restores its files" \
  "$([ -e "$C/.claude/rules/harness/research/notes.md" ] && echo 0 || echo 1)"

# --- 6. uninstall round-trip -------------------------------------------------
section "uninstall"

out="$(run_uninst "$C" 2>&1)"; rc=$?
check "uninstall exits 0" "$rc" "$(printf '%s' "$out" | tail -5)"
check "settings.json is canonically identical to the original" \
  "$([ "$(jq -S . "$C/.claude/settings.json")" = "$BEFORE_SETTINGS" ] && echo 0 || echo 1)" \
  "$(diff <(printf '%s\n' "$BEFORE_SETTINGS") <(jq -S . "$C/.claude/settings.json") | head -12)"
check ".gitignore restored" \
  "$([ "$(cat "$C/.gitignore")" = "$BEFORE_GITIGNORE" ] && echo 0 || echo 1)" \
  "$(diff <(printf '%s\n' "$BEFORE_GITIGNORE") "$C/.gitignore" | head -6)"
check "no harness rule remains" \
  "$([ -z "$(find "$C/.claude" -path '*rules/harness*' 2>/dev/null)" ] && echo 0 || echo 1)" \
  "left: $(find "$C/.claude" -path '*rules/harness*' 2>/dev/null | tr '\n' ' ')"
check "manifest removed" "$([ ! -e "$M" ] && echo 0 || echo 1)"
check "template CLAUDE.md left behind by default" "$([ -e "$C/CLAUDE.md" ] && echo 0 || echo 1)"
check "template protected-paths.txt left behind by default" "$([ -e "$C/.claude/protected-paths.txt" ] && echo 0 || echo 1)"
check "a backup of the pre-uninstall settings exists" \
  "$([ "$(find "$C/.claude" -name 'settings.json.bak-*' | wc -l | tr -d ' ')" -ge 1 ] && echo 0 || echo 1)"

# --- 7. a project with nothing in it -----------------------------------------
section "bare project (no settings.json, no .gitignore)"

C2="$WORK/c2"
new_consumer "$C2" bare
run_install "$C2" >/dev/null 2>&1
check "settings.json created" "$([ -f "$C2/.claude/settings.json" ] && echo 0 || echo 1)"
check ".gitignore created" "$([ -f "$C2/.gitignore" ] && echo 0 || echo 1)"
run_uninst "$C2" --purge-templates >/dev/null 2>&1
check "settings.json removed again (installer created it)" \
  "$([ ! -e "$C2/.claude/settings.json" ] && echo 0 || echo 1)"
check ".gitignore removed again (installer created it)" \
  "$([ ! -e "$C2/.gitignore" ] && echo 0 || echo 1)"
check "--purge-templates removes CLAUDE.md too" "$([ ! -e "$C2/CLAUDE.md" ] && echo 0 || echo 1)"
# The settings snapshot is deliberately left behind — it is the undo path, and
# uninstall prints where it is. Everything else must be gone.
check "nothing left under .claude except the settings snapshot" \
  "$([ -z "$(find "$C2/.claude" -type f ! -name 'settings.json.bak-*' 2>/dev/null)" ] && echo 0 || echo 1)" \
  "left: $(find "$C2/.claude" -type f ! -name 'settings.json.bak-*' 2>/dev/null | tr '\n' ' ')"

# --- 7b. user-level install ---------------------------------------------------
# CLAUDE_CONFIG_DIR redirects the whole thing into a scratch directory, so this
# never touches the real ~/.claude — which is also the only reason this test is
# safe to run in CI and on a developer's own machine.
section "user scope (--scope user)"

U="$WORK/usercfg"
mkdir -p "$U"
cat > "$U/settings.json" <<'EOF'
{ "model": "opus", "permissions": { "allow": ["Bash(echo consumer-owned:*)"] } }
EOF
U_BEFORE="$(jq -S . "$U/settings.json")"

run_user()  { ( cd "$WORK" && CLAUDE_CONFIG_DIR="$U" "$BASH_BIN" "$HCTL" init --scope user "$@" ); }
run_userun(){ ( cd "$WORK" && CLAUDE_CONFIG_DIR="$U" "$BASH_BIN" "$HCTL" uninstall --scope user "$@" ); }

out="$(run_user --with dev,research 2>&1)"; rc=$?
check "user install exits 0" "$rc" "$(printf '%s' "$out" | tail -5)"
check "user install needs no git repo" \
  "$([ ! -e "$WORK/.git" ] && [ -f "$U/harness-manifest.json" ] && echo 0 || echo 1)"

for f in CLAUDE.md protected-paths.txt allowed-paths.txt harness-manifest.json; do
  [ -e "$U/$f" ]; check "user install placed $f" $?
done

# Path-scoped rules have no documented user-level equivalent, so shipping them
# would put inert files where they look active.
check "rules are not installed at user scope" \
  "$([ ! -e "$U/rules" ] && echo 0 || echo 1)"
check "...and the install says which files it skipped" \
  "$(printf '%s' "$out" | grep -q 'rules' && echo 0 || echo 1)"

check "user settings.json keeps its existing keys" \
  "$([ "$(jq -r '.model' "$U/settings.json")" = "opus" ] && echo 0 || echo 1)"
check "user scope writes no hooks either" \
  "$(jq -e 'has("hooks") | not' "$U/settings.json" >/dev/null 2>&1 && echo 0 || echo 1)"

check "no .gitignore invented at the user level" "$([ ! -e "$WORK/.gitignore" ] && echo 0 || echo 1)"

H1="$(tree_hash "$U")"
run_user >/dev/null 2>&1
check "user re-install changes nothing" "$([ "$H1" = "$(tree_hash "$U")" ] && echo 0 || echo 1)"

# Both scopes can be initialised at once with no interaction: the plugin
# registers hooks once regardless of how many scopes ran harnessctl init, and
# each scope keeps its own manifest. Before the split this needed a warning.
CBOTH="$WORK/cboth"
new_consumer "$CBOTH" bare
out="$( ( cd "$CBOTH" && CLAUDE_CONFIG_DIR="$U" "$BASH_BIN" "$HCTL" init ) 2>&1 )"; rc=$?
check "a project init alongside a user init succeeds" "$rc" "$(printf '%s' "$out" | tail -3)"
check "...and the two manifests are independent" \
  "$([ -f "$CBOTH/.claude/harness-manifest.json" ] && [ -f "$U/harness-manifest.json" ] && echo 0 || echo 1)"

run_userun --purge-templates >/dev/null 2>&1
check "user uninstall restores settings.json exactly" \
  "$([ "$(jq -S . "$U/settings.json")" = "$U_BEFORE" ] && echo 0 || echo 1)" \
  "$(diff <(printf '%s\n' "$U_BEFORE") <(jq -S . "$U/settings.json") | head -10)"
check "user uninstall leaves nothing but the snapshot" \
  "$([ -z "$(find "$U" -type f ! -name 'settings.json' ! -name 'settings.json.bak-*' 2>/dev/null)" ] && echo 0 || echo 1)" \
  "left: $(find "$U" -type f ! -name 'settings.json' ! -name 'settings.json.bak-*' 2>/dev/null | tr '\n' ' ')"

# --- 8. collision guard ------------------------------------------------------
section "collision guard"

C3="$WORK/c3"
new_consumer "$C3" bare
mkdir -p "$C3/.claude/rules/harness"
printf 'my own file, not the harness\n' > "$C3/.claude/rules/harness/workflow.md"
H_BEFORE="$(tree_hash "$C3")"
out="$(run_install "$C3" 2>&1)"; rc=$?
check "install aborts on an unowned file at a managed path" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check "abort names the conflicting path" \
  "$(printf '%s' "$out" | grep -q 'workflow.md' && echo 0 || echo 1)"
check "abort wrote nothing" "$([ "$H_BEFORE" = "$(tree_hash "$C3")" ] && echo 0 || echo 1)"

# --- 9. dry run --------------------------------------------------------------
section "dry run"

C4="$WORK/c4"
new_consumer "$C4"
H_BEFORE="$(tree_hash "$C4")"
out="$(run_install "$C4" --with research --dry-run 2>&1)"; rc=$?
check "dry-run exits 0" "$rc"
check "dry-run writes nothing" "$([ "$H_BEFORE" = "$(tree_hash "$C4")" ] && echo 0 || echo 1)"
check "dry-run still describes the plan" \
  "$(printf '%s' "$out" | grep -q 'CLAUDE.md' && echo 0 || echo 1)"

# --- 10. unknown module ------------------------------------------------------
section "argument handling"

out="$(run_install "$C4" --with nope 2>&1)"; rc=$?
check "unknown module is rejected" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check "rejection lists the available modules" \
  "$(printf '%s' "$out" | grep -q 'research' && echo 0 || echo 1)"
out="$(run_install "$C4" --bogus 2>&1)"; rc=$?
check "unknown flag is rejected" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"

# --- 11. install.sh itself ---------------------------------------------------
# This file is named verify-install and until now it verified only harnessctl.
# install.sh got `bash -n` and nothing else — and parsing cannot tell a comment
# from a command.
#
# It found out the hard way. A line in the usage header lost its `#` and became
# `./install.sh --profile research,slides`, executed before anything else on
# every run. From a clone, that is unbounded self-invocation; from a
# `curl -o`'d copy it is a permission-denied line the user is told to ignore.
# It sat on main through five releases. `bash -n` passed the whole time,
# because the line is perfectly good bash.
section "install.sh"

INSTALL_SH="$HARNESS/install.sh"

# Everything above `set -uo pipefail` is documentation and must look like it.
# Static, deterministic, and it catches the whole class rather than the one
# line that bit us.
header_code="$(awk '/^set -uo pipefail/{exit} /^[[:space:]]*$/{next} /^[[:space:]]*#/{next} {print NR": "$0}' "$INSTALL_SH")"
check "nothing executable hides in the usage header" \
  "$([ -z "$header_code" ] && echo 0 || echo 1)"
[ -n "$header_code" ] && printf '        %s\n' "$header_code"

# --help must be inert. It runs before the Claude CLI is looked for, so this
# works on a machine that has never seen Claude Code — including CI.
#
# The probe deliberately runs from an EMPTY directory with the script reached by
# absolute path. Running it from a directory that contains install.sh is what a
# consumer does, but it is also what turns a header self-invocation into
# unbounded recursion — and a verifier that fork-bombs the machine it is meant
# to protect is worse than the bug. From an empty cwd the same `./install.sh`
# resolves to nothing, so the attempt still shows up in stderr and nothing
# spawns. The static check above is what covers the class; this covers the rest
# of the argument surface.
probe="$WORK/probe"
probe_cwd="$WORK/probe-cwd"
mkdir -p "$probe" "$probe_cwd"
cp "$INSTALL_SH" "$probe/install.sh"
chmod 755 "$probe/install.sh"

run_probe() { ( cd "$probe_cwd" && "$BASH_BIN" "$probe/install.sh" "$@" 2>&1 ); }

out="$(run_probe --help)"; rc=$?
check "--help exits 0" "$rc"
check "--help prints the usage block" \
  "$(printf '%s' "$out" | grep -q -- '--profile <list>' && echo 0 || echo 1)"
check "--help runs nothing on the way there" \
  "$(printf '%s' "$out" | grep -qE 'Permission denied|No such file or directory|command not found' && echo 1 || echo 0)"

out="$(run_probe --scope nowhere)"; rc=$?
check "an unknown --scope is rejected" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
out="$(run_probe --profile nope)"; rc=$?
check "an unknown --profile is rejected" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
out="$(run_probe --bogus)"; rc=$?
check "an unknown flag is rejected" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"

# --- summary -----------------------------------------------------------------
total=$((PASS + FAIL))
echo
echo "=== Summary ==="
echo "  $PASS / $total passed"
if [ "$FAIL" -gt 0 ]; then
  echo "  $FAIL failed:"
  printf '%s' "$FAILED" | while IFS= read -r n; do [ -n "$n" ] && echo "    - $n"; done
  exit 1
fi
exit 0

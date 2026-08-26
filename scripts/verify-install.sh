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

type -P jq >/dev/null 2>&1 || { echo "verify-install: jq is required" >&2; exit 1; }
[ -f "$HCTL" ] || { echo "verify-install: $HCTL not found" >&2; exit 1; }

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

. "$(cd "$(dirname "$0")" && pwd)/_check-lib.sh"

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
check_rc "every shipped script is executable" "$([ -z "$missing_x" ] && echo 0 || echo 1)" "not executable:$missing_x"

json_bad=""
for f in "$HARNESS/.claude-plugin/marketplace.json" "$HARNESS"/plugins/*/.claude-plugin/plugin.json \
         "$HARNESS/plugins/harness-core/hooks/hooks.json" "$HARNESS/plugins/harness-core/declarative/settings-fragment.json"; do
  [ -f "$f" ] || { json_bad="$json_bad MISSING:$f"; continue; }
  jq empty "$f" 2>/dev/null || json_bad="$json_bad $f"
done
check_rc "every plugin/marketplace JSON is valid" "$([ -z "$json_bad" ] && echo 0 || echo 1)" "invalid:$json_bad"

# The fragment must not carry hooks: the plugin owns those now, and a stray
# hooks block here would register them a second time.
check_rc "settings fragment carries no hooks block" \
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
check_rc "every hooks.json registration resolves to an executable file" \
  "$([ -z "$unresolved" ] && echo 0 || echo 1)" "unresolved:$unresolved"

check_rc "marketplace lists every plugin directory" \
  "$([ "$(jq -r '.plugins|length' "$HARNESS/.claude-plugin/marketplace.json")" = "$(ls -d "$HARNESS"/plugins/*/ | wc -l | tr -d ' ')" ] && echo 0 || echo 1)"

# --- 1. install over an opinionated settings.json ----------------------------
section "--with repeats accumulate"

# `--with dev --with research` is a reasonable thing to type. Overwriting on the
# second flag drops a module the user explicitly asked for and says nothing.
C="$WORK/c0"
new_consumer "$C"
run_install "$C" --with dev --with research >/dev/null 2>&1
[ -f "$C/.claude/rules/harness/dev/review.md" ]
check_rc "repeated --with keeps the first module (dev)" $?
[ -f "$C/.claude/rules/harness/research/notes.md" ]
check_rc "repeated --with keeps the second module (research)" $?

section "install --with dev,research"

C="$WORK/c1"
new_consumer "$C"
BEFORE_SETTINGS="$(jq -S . "$C/.claude/settings.json")"
BEFORE_GITIGNORE="$(cat "$C/.gitignore")"

out="$(run_install "$C" --with dev,research 2>&1)"
rc=$?
check_rc "install exits 0" "$rc" "$(printf '%s' "$out" | tail -5)"

M="$C/.claude/harness-manifest.json"
jq empty "$M" 2>/dev/null
check_rc "manifest is valid JSON" $?

missing=""
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  [ -e "$C/$rel" ] || missing="$missing $rel"
done < <(jq -r '((.files.managed // []) + (.files.template // []))[]' "$M")
check_rc "every manifest-listed file exists on disk" "$([ -z "$missing" ] && echo 0 || echo 1)" "missing:$missing"

check_rc "manifest records both modules" \
  "$([ "$(jq -r '.modules | sort | join(",")' "$M")" = "dev,research" ] && echo 0 || echo 1)" \
  "got $(jq -c '.modules' "$M")"

for f in CLAUDE.md .claude/rules/harness/workflow.md .claude/protected-paths.txt \
         .claude/gh-account.txt \
         .claude/rules/harness/dev/review.md .claude/rules/harness/research/notes.md; do
  [ -e "$C/$f" ]; check_rc "installed $f" $?
done

# Hooks, skills, commands and verifiers are the plugin's job. harnessctl
# writing any of them would mean two copies drifting apart.
for f in .claude/hooks .claude/skills .claude/commands .claude/scripts; do
  [ ! -e "$C/$f" ]; check_rc "harnessctl did not write $f (plugin territory)" $?
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
check_rc "relative links in the installed markdown resolve" \
  "$([ -z "$broken" ] && echo 0 || echo 1)" "broken:$broken"

# --- 2. the consumer's own settings survive ----------------------------------
section "consumer settings preserved"

S="$C/.claude/settings.json"
check_rc "unrelated top-level key (statusLine) untouched" \
  "$([ "$(jq -c '.statusLine' "$S")" = '{"type":"command","command":"~/.claude/statusline.sh","padding":0}' ] && echo 0 || echo 1)"
check_rc "\$schema untouched" "$([ "$(jq -r '."$schema"' "$S")" != "null" ] && echo 0 || echo 1)"
check_rc "consumer allow entry survives" \
  "$(jq -e '.permissions.allow | index("Bash(echo consumer-owned:*)")' "$S" >/dev/null 2>&1 && echo 0 || echo 1)"
check_rc "consumer PreToolUse hook survives" \
  "$(jq -e '[.hooks.PreToolUse[].hooks[].command] | index("bash .claude/hooks/mine/audit.sh")' "$S" >/dev/null 2>&1 && echo 0 || echo 1)"
check_rc "consumer Stop hook survives" \
  "$(jq -e '[.hooks.Stop[].hooks[].command] | index("bash .claude/hooks/mine/notify.sh")' "$S" >/dev/null 2>&1 && echo 0 || echo 1)"

# The strongest property of the split: harnessctl has no business in .hooks at
# all, so the consumer's hooks block must come back byte-identical.
check_rc "the consumer's .hooks block is byte-identical after install" \
  "$([ "$(jq -Sc '.hooks' "$S")" = "$(printf '%s' "$BEFORE_SETTINGS" | jq -Sc '.hooks')" ] && echo 0 || echo 1)" \
  "$(jq -Sc '.hooks' "$S")"
check_rc "no harness hook registration was added" \
  "$(jq -e '[.. | objects | select(has("command")) | .command | select(contains("harness"))] | length == 0' "$S" >/dev/null 2>&1 && echo 0 || echo 1)"
check_rc "includeCoAuthoredBy set to false" \
  "$([ "$(jq -r '.includeCoAuthoredBy' "$S")" = "false" ] && echo 0 || echo 1)"
# The style ships in the plugin half; this scalar is the only thing that selects
# it. Shipping the file without the key would install a style nobody turns on.
check_rc "outputStyle selects the harness report style" \
  "$([ "$(jq -r '.outputStyle' "$S")" = "harness-core:Report" ] && echo 0 || echo 1)" \
  "$(jq -r '.outputStyle' "$S")"
check_rc "ask tier created" "$([ "$(jq '.permissions.ask | length' "$S")" -gt 0 ] && echo 0 || echo 1)"
check_rc ".gitignore keeps its existing entries" \
  "$(grep -qxF 'node_modules/' "$C/.gitignore" && echo 0 || echo 1)"
check_rc ".gitignore gained settings.local.json" \
  "$(grep -qxF '.claude/settings.local.json' "$C/.gitignore" && echo 0 || echo 1)"

# --- 2b. guards added after the review ---------------------------------------

# The docs promised a warning when the consumer already set one of our scalars,
# and the code silently did nothing — leaving includeCoAuthoredBy true defeats
# the guard the harness exists to provide.
#
# outputStyle rides the same path and is the one where it matters most: a
# consumer who has chosen how Claude talks to them has made a deliberate
# choice, and only one output style can be active at a time, so overwriting it
# would silently take theirs away rather than add to it.
CW="$WORK/cwarn"
new_consumer "$CW" bare
printf '{"includeCoAuthoredBy": true, "outputStyle": "Concise"}' > "$CW/.claude/settings.json"
out="$(run_install "$CW" 2>&1)"
check_rc "a conflicting scalar draws a warning" \
  "$(printf '%s' "$out" | grep -q 'includeCoAuthoredBy' && echo 0 || echo 1)" \
  "$(printf '%s' "$out" | tail -3)"
check_rc "a conflicting outputStyle draws a warning" \
  "$(printf '%s' "$out" | grep -q 'outputStyle' && echo 0 || echo 1)" \
  "$(printf '%s' "$out" | tail -3)"
check_rc "...and the consumer's value is left alone" \
  "$([ "$(jq -r '.includeCoAuthoredBy' "$CW/.claude/settings.json")" = "true" ] && echo 0 || echo 1)"
check_rc "...and the consumer keeps the output style they chose" \
  "$([ "$(jq -r '.outputStyle' "$CW/.claude/settings.json")" = "Concise" ] && echo 0 || echo 1)" \
  "$(jq -r '.outputStyle' "$CW/.claude/settings.json")"
run_uninst "$CW" >/dev/null 2>&1
check_rc "...and uninstall does not take a scalar it never set" \
  "$([ "$(jq -r '.includeCoAuthoredBy' "$CW/.claude/settings.json")" = "true" ] && echo 0 || echo 1)"
check_rc "...and uninstall does not take the output style it never set" \
  "$([ "$(jq -r '.outputStyle' "$CW/.claude/settings.json")" = "Concise" ] && echo 0 || echo 1)" \
  "$(jq -r '.outputStyle' "$CW/.claude/settings.json")"

# A committed manifest can be corrupted by a merge conflict. Both commands used
# to die with raw jq errors and no stated way out.
CB="$WORK/cbroken"
new_consumer "$CB" bare
run_install "$CB" >/dev/null 2>&1
printf '<<<<<<< HEAD\n{}\n' > "$CB/.claude/harness-manifest.json"
out="$(run_install "$CB" 2>&1)"; rc=$?
check_rc "a corrupt manifest aborts rather than emitting jq errors" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check_rc "...and the message says how to recover" \
  "$(printf '%s' "$out" | grep -q 'rm ' && echo 0 || echo 1)"

# jq empty accepts [] and null, so a settings.json that is valid JSON but not an
# object used to pass preflight and explode mid-merge, after files were written.
CA="$WORK/carray"
new_consumer "$CA" bare
printf '[]' > "$CA/.claude/settings.json"
out="$(run_install "$CA" 2>&1)"; rc=$?
check_rc "a non-object settings.json is rejected in preflight" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check_rc "...before any file is written" "$([ ! -e "$CA/CLAUDE.md" ] && echo 0 || echo 1)"

# --- 3. idempotence ----------------------------------------------------------
section "idempotence"

nbak() { find "$1/.claude" -name 'settings.json.bak-*' 2>/dev/null | wc -l | tr -d ' '; }

H1="$(tree_hash "$C")"
B1="$(nbak "$C")"
out="$(run_install "$C" 2>&1)"; rc=$?
H2="$(tree_hash "$C")"
check_rc "re-install exits 0" "$rc"
check_rc "re-install changes nothing on disk" "$([ "$H1" = "$H2" ] && echo 0 || echo 1)"
check_rc "re-install reports no settings change" \
  "$(printf '%s' "$out" | grep -q '=  no change' && echo 0 || echo 1)"
# A run that rewrites nothing must not leave a snapshot either, or the project
# accumulates one .bak file per no-op install.
check_rc "re-install writes no new backup" "$([ "$B1" = "$(nbak "$C")" ] && echo 0 || echo 1)" \
  "$B1 → $(nbak "$C")"
check_rc "the first install did take a snapshot" "$([ "$B1" -ge 1 ] && echo 0 || echo 1)"
check_rc "re-install keeps the module set" \
  "$([ "$(jq -r '.modules | sort | join(",")' "$M")" = "dev,research" ] && echo 0 || echo 1)"

# --- 4. two tiers behave differently -----------------------------------------
section "managed vs template"

printf '\n<!-- my own project rule -->\n' >> "$C/CLAUDE.md"
TMPL_EDITED="$(cksum < "$C/CLAUDE.md")"
printf '\n# local scribble\n' >> "$C/.claude/rules/harness/workflow.md"
run_install "$C" >/dev/null 2>&1
check_rc "template edit is preserved" \
  "$([ "$(cksum < "$C/CLAUDE.md")" = "$TMPL_EDITED" ] && echo 0 || echo 1)"
check_rc "managed edit is overwritten" \
  "$(cmp -s "$C/.claude/rules/harness/workflow.md" "$HARNESS/plugins/harness-core/declarative/rules/core/workflow.md" && echo 0 || echo 1)"

# A guard's config file in the managed tier would be overwritten on every
# reinstall, silently discarding whichever account the consumer declared.
check_rc "gh-account.txt is in the template tier, not managed" \
  "$(jq -e '(.files.template | index(".claude/gh-account.txt")) and (((.files.managed // []) | index(".claude/gh-account.txt")) == null)' "$M" >/dev/null 2>&1 && echo 0 || echo 1)" \
  "template: $(jq -c '.files.template' "$M" 2>/dev/null)"

# --- 5. dropping a module ----------------------------------------------------
section "module selection"

run_install "$C" --with dev >/dev/null 2>&1
check_rc "research rule removed when the module is dropped" \
  "$([ ! -e "$C/.claude/rules/harness/research/notes.md" ] && echo 0 || echo 1)"
check_rc "research rule directory pruned" \
  "$([ ! -d "$C/.claude/rules/harness/research" ] && echo 0 || echo 1)"
check_rc "dev rule still present" "$([ -e "$C/.claude/rules/harness/dev/review.md" ] && echo 0 || echo 1)"
check_rc "core still present" "$([ -e "$C/.claude/rules/harness/workflow.md" ] && echo 0 || echo 1)"
check_rc "manifest records only dev" \
  "$([ "$(jq -r '.modules | join(",")' "$M")" = "dev" ] && echo 0 || echo 1)" "got $(jq -c '.modules' "$M")"

run_install "$C" --with dev,research >/dev/null 2>&1
check_rc "re-adding the module restores its files" \
  "$([ -e "$C/.claude/rules/harness/research/notes.md" ] && echo 0 || echo 1)"

# --- 6. uninstall round-trip -------------------------------------------------
section "uninstall"

out="$(run_uninst "$C" 2>&1)"; rc=$?
check_rc "uninstall exits 0" "$rc" "$(printf '%s' "$out" | tail -5)"
check_rc "settings.json is canonically identical to the original" \
  "$([ "$(jq -S . "$C/.claude/settings.json")" = "$BEFORE_SETTINGS" ] && echo 0 || echo 1)" \
  "$(diff <(printf '%s\n' "$BEFORE_SETTINGS") <(jq -S . "$C/.claude/settings.json") | head -12)"
check_rc ".gitignore restored" \
  "$([ "$(cat "$C/.gitignore")" = "$BEFORE_GITIGNORE" ] && echo 0 || echo 1)" \
  "$(diff <(printf '%s\n' "$BEFORE_GITIGNORE") "$C/.gitignore" | head -6)"
check_rc "no harness rule remains" \
  "$([ -z "$(find "$C/.claude" -path '*rules/harness*' 2>/dev/null)" ] && echo 0 || echo 1)" \
  "left: $(find "$C/.claude" -path '*rules/harness*' 2>/dev/null | tr '\n' ' ')"
check_rc "manifest removed" "$([ ! -e "$M" ] && echo 0 || echo 1)"
check_rc "template CLAUDE.md left behind by default" "$([ -e "$C/CLAUDE.md" ] && echo 0 || echo 1)"
check_rc "template protected-paths.txt left behind by default" "$([ -e "$C/.claude/protected-paths.txt" ] && echo 0 || echo 1)"
check_rc "template gh-account.txt left behind by default" "$([ -e "$C/.claude/gh-account.txt" ] && echo 0 || echo 1)"
check_rc "a backup of the pre-uninstall settings exists" \
  "$([ "$(find "$C/.claude" -name 'settings.json.bak-*' | wc -l | tr -d ' ')" -ge 1 ] && echo 0 || echo 1)"

# --- 7. a project with nothing in it -----------------------------------------
section "bare project (no settings.json, no .gitignore)"

C2="$WORK/c2"
new_consumer "$C2" bare
run_install "$C2" >/dev/null 2>&1
check_rc "settings.json created" "$([ -f "$C2/.claude/settings.json" ] && echo 0 || echo 1)"
check_rc ".gitignore created" "$([ -f "$C2/.gitignore" ] && echo 0 || echo 1)"
run_uninst "$C2" --purge-templates >/dev/null 2>&1
check_rc "settings.json removed again (installer created it)" \
  "$([ ! -e "$C2/.claude/settings.json" ] && echo 0 || echo 1)"
check_rc ".gitignore removed again (installer created it)" \
  "$([ ! -e "$C2/.gitignore" ] && echo 0 || echo 1)"
check_rc "--purge-templates removes CLAUDE.md too" "$([ ! -e "$C2/CLAUDE.md" ] && echo 0 || echo 1)"
check_rc "--purge-templates removes gh-account.txt too" "$([ ! -e "$C2/.claude/gh-account.txt" ] && echo 0 || echo 1)"
# The settings snapshot is deliberately left behind — it is the undo path, and
# uninstall prints where it is. Everything else must be gone.
check_rc "nothing left under .claude except the settings snapshot" \
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
check_rc "user install exits 0" "$rc" "$(printf '%s' "$out" | tail -5)"
check_rc "user install needs no git repo" \
  "$([ ! -e "$WORK/.git" ] && [ -f "$U/harness-manifest.json" ] && echo 0 || echo 1)"

for f in CLAUDE.md protected-paths.txt allowed-paths.txt gh-account.txt harness-manifest.json; do
  [ -e "$U/$f" ]; check_rc "user install placed $f" $?
done

# Path-scoped rules have no documented user-level equivalent, so shipping them
# would put inert files where they look active.
check_rc "rules are not installed at user scope" \
  "$([ ! -e "$U/rules" ] && echo 0 || echo 1)"
check_rc "...and the install says which files it skipped" \
  "$(printf '%s' "$out" | grep -q 'rules' && echo 0 || echo 1)"

check_rc "user settings.json keeps its existing keys" \
  "$([ "$(jq -r '.model' "$U/settings.json")" = "opus" ] && echo 0 || echo 1)"
check_rc "user scope writes no hooks either" \
  "$(jq -e 'has("hooks") | not' "$U/settings.json" >/dev/null 2>&1 && echo 0 || echo 1)"

check_rc "no .gitignore invented at the user level" "$([ ! -e "$WORK/.gitignore" ] && echo 0 || echo 1)"

H1="$(tree_hash "$U")"
run_user >/dev/null 2>&1
check_rc "user re-install changes nothing" "$([ "$H1" = "$(tree_hash "$U")" ] && echo 0 || echo 1)"

# Both scopes can be initialised at once with no interaction: the plugin
# registers hooks once regardless of how many scopes ran harnessctl init, and
# each scope keeps its own manifest. Before the split this needed a warning.
CBOTH="$WORK/cboth"
new_consumer "$CBOTH" bare
out="$( ( cd "$CBOTH" && CLAUDE_CONFIG_DIR="$U" "$BASH_BIN" "$HCTL" init ) 2>&1 )"; rc=$?
check_rc "a project init alongside a user init succeeds" "$rc" "$(printf '%s' "$out" | tail -3)"
check_rc "...and the two manifests are independent" \
  "$([ -f "$CBOTH/.claude/harness-manifest.json" ] && [ -f "$U/harness-manifest.json" ] && echo 0 || echo 1)"

run_userun --purge-templates >/dev/null 2>&1
check_rc "user uninstall restores settings.json exactly" \
  "$([ "$(jq -S . "$U/settings.json")" = "$U_BEFORE" ] && echo 0 || echo 1)" \
  "$(diff <(printf '%s\n' "$U_BEFORE") <(jq -S . "$U/settings.json") | head -10)"
check_rc "user uninstall leaves nothing but the snapshot" \
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
check_rc "install aborts on an unowned file at a managed path" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check_rc "abort names the conflicting path" \
  "$(printf '%s' "$out" | grep -q 'workflow.md' && echo 0 || echo 1)"
check_rc "abort wrote nothing" "$([ "$H_BEFORE" = "$(tree_hash "$C3")" ] && echo 0 || echo 1)"

# --- 9. dry run --------------------------------------------------------------
section "dry run"

C4="$WORK/c4"
new_consumer "$C4"
H_BEFORE="$(tree_hash "$C4")"
out="$(run_install "$C4" --with research --dry-run 2>&1)"; rc=$?
check_rc "dry-run exits 0" "$rc"
check_rc "dry-run writes nothing" "$([ "$H_BEFORE" = "$(tree_hash "$C4")" ] && echo 0 || echo 1)"
check_rc "dry-run still describes the plan" \
  "$(printf '%s' "$out" | grep -q 'CLAUDE.md' && echo 0 || echo 1)"

# --- 10. unknown module ------------------------------------------------------
section "argument handling"

out="$(run_install "$C4" --with nope 2>&1)"; rc=$?
check_rc "unknown module is rejected" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check_rc "rejection lists the available modules" \
  "$(printf '%s' "$out" | grep -q 'research' && echo 0 || echo 1)"
out="$(run_install "$C4" --bogus 2>&1)"; rc=$?
check_rc "unknown flag is rejected" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"

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
check_rc "nothing executable hides in the usage header" \
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
check_rc "--help exits 0" "$rc"
check_rc "--help prints the usage block" \
  "$(printf '%s' "$out" | grep -q -- '--profile <list>' && echo 0 || echo 1)"
check_rc "--help runs nothing on the way there" \
  "$(printf '%s' "$out" | grep -qE 'Permission denied|No such file or directory|command not found' && echo 1 || echo 0)"

out="$(run_probe --scope nowhere)"; rc=$?
check_rc "an unknown --scope is rejected" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
out="$(run_probe --profile nope)"; rc=$?
check_rc "an unknown --profile is rejected" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
# The boundary: every profile the usage block advertises has to survive the same
# validation that rejects `nope`. Pairing a real name with a bogus one keeps the
# probe inert — it dies either way, and the question is *which* name it names.
# Ordered so the real profile is checked first: if `frontend` were missing from
# the case list, the message would say frontend rather than nope. Without this,
# a documented profile can be rejected by the installer and nothing notices.
out="$(run_probe --profile frontend,nope)"; rc=$?
check_rc "...but a profile the usage block advertises is not" \
  "$([ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'unknown profile: nope' && echo 0 || echo 1)"
# The same boundary, applied to the default set rather than to one name. Every
# profile installed when the consumer passes no flag at all has to survive the
# validator, and the list is read out of install.sh rather than repeated here so
# this cannot pass against a stale copy. A typo in PROFILES_DEFAULT makes the
# no-flag install die on its own first line, which is the whole default path.
default_profiles="$(sed -n 's/^PROFILES_DEFAULT="\(.*\)"$/\1/p' "$INSTALL_SH")"
check_rc "install.sh states a default profile set" \
  "$([ -n "$default_profiles" ] && echo 0 || echo 1)"
out="$(run_probe --profile "$default_profiles,nope")"; rc=$?
check_rc "every profile in the default set survives validation" \
  "$([ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'unknown profile: nope' && echo 0 || echo 1)"

out="$(run_probe --bogus)"; rc=$?
check_rc "an unknown flag is rejected" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"

# --- 12. the shell shim ------------------------------------------------------
# Only --help and the argument surface were covered, so the shim block — the
# part a consumer's terminal actually depends on — had no test at all. It shipped
# reading $HOME/.claude while step 3 resolved harnessctl through
# $CLAUDE_CONFIG_DIR, and the failure was silent: on a non-default config
# directory the glob matched nothing, the loop ran zero times, and one warning
# was the only sign of an install that had otherwise succeeded.
#
# A fake `claude` on PATH is what makes this testable. The real one reaches the
# network and needs a marketplace, and neither belongs in a verifier.
section "shell shim"

shimroot="$WORK/shim"
fakebin="$shimroot/fakebin"
mkdir -p "$fakebin"
# Accepts every subcommand install.sh calls and does nothing. `plugin --help`
# has to exit 0 or the script dies at its capability check.
printf '#!/bin/sh\nexit 0\n' > "$fakebin/claude"
chmod +x "$fakebin/claude"

# A cache in a NON-default config directory, holding two versions so the
# newest-wins rule is exercised at the same time.
# `.in_use` marks the live copy and `.orphaned_at` marks a superseded one —
# step 3 requires the first and skips the second, so a fixture without the
# marker never reaches the shim block at all.
altcfg="$shimroot/altcfg"
for v in 1.9.0 1.10.0; do
  mkdir -p "$altcfg/plugins/cache/agent-harness/harness-core/$v/bin"
  : > "$altcfg/plugins/cache/agent-harness/harness-core/$v/.in_use"
  printf '#!/bin/sh\necho "harnessctl %s"\n' "$v" \
    > "$altcfg/plugins/cache/agent-harness/harness-core/$v/bin/harnessctl"
  chmod +x "$altcfg/plugins/cache/agent-harness/harness-core/$v/bin/harnessctl"
done
# A superseded copy, left behind by `claude plugin update` with its bin/ emptied
# — the real shape, verified against this machine's cache. It sorts ABOVE the
# live versions, so anything that just takes the highest version finds an empty
# directory. Both the generator and the shim have to skip it.
mkdir -p "$altcfg/plugins/cache/agent-harness/harness-core/2.0.0/bin"
: > "$altcfg/plugins/cache/agent-harness/harness-core/2.0.0/.orphaned_at"
# A second executable, to pin that the loop globs bin/ instead of naming one.
printf '#!/bin/sh\necho "harness-log"\n' \
  > "$altcfg/plugins/cache/agent-harness/harness-core/1.10.0/bin/harness-log"
chmod +x "$altcfg/plugins/cache/agent-harness/harness-core/1.10.0/bin/harness-log"
# A decoy under the DEFAULT location. If the shim ever reverts to $HOME/.claude
# it will find this one, and the version assertion below says so by name.
fakehome="$shimroot/home"
mkdir -p "$fakehome/.claude/plugins/cache/agent-harness/harness-core/0.0.1/bin"
printf '#!/bin/sh\necho "harnessctl DECOY"\n' \
  > "$fakehome/.claude/plugins/cache/agent-harness/harness-core/0.0.1/bin/harnessctl"
chmod +x "$fakehome/.claude/plugins/cache/agent-harness/harness-core/0.0.1/bin/harnessctl"

shimbin="$shimroot/localbin"
( cd "$probe_cwd" && env -i PATH="$fakebin:/usr/bin:/bin" HOME="$fakehome" \
    CLAUDE_CONFIG_DIR="$altcfg" BIN_DIR="$shimbin" SHELL=/bin/bash \
    "$BASH_BIN" "$probe/install.sh" --scope user >/dev/null 2>&1 )

check_rc "a shim is written for harnessctl" "$([ -x "$shimbin/harnessctl" ] && echo 0 || echo 1)"
check_rc "a shim is written for every executable in bin/" "$([ -x "$shimbin/harness-log" ] && echo 0 || echo 1)"

# Run the shim the way a user would, with the config directory still set.
shim_out="$( env PATH="/usr/bin:/bin" HOME="$fakehome" CLAUDE_CONFIG_DIR="$altcfg" \
             sh "$shimbin/harnessctl" 2>&1 )"
check_rc "the shim honours CLAUDE_CONFIG_DIR" \
  "$(printf '%s' "$shim_out" | grep -q 'harnessctl 1.10.0' && echo 0 || echo 1)" \
  "got: $shim_out"
check_rc "...and does not fall back to the default cache" \
  "$(printf '%s' "$shim_out" | grep -q DECOY && echo 1 || echo 0)" \
  "got: $shim_out"

# 1.10.0 must beat 1.9.0. Lexicographic sorting gets this backwards, which is
# why the resolution uses sort -V.
check_rc "the shim picks the newest version, not the last alphabetically" \
  "$(printf '%s' "$shim_out" | grep -q '1.10.0' && echo 0 || echo 1)" \
  "got: $shim_out"

# With no config directory set, the shim must fall back to $HOME/.claude — the
# ordinary case, and the one the fix must not break.
shim_out="$( env PATH="/usr/bin:/bin" HOME="$fakehome" sh "$shimbin/harnessctl" 2>&1 )"
check_rc "the shim falls back to \$HOME/.claude when unset" \
  "$(printf '%s' "$shim_out" | grep -q DECOY && echo 0 || echo 1)" \
  "got: $shim_out"

# Nothing installed anywhere: the shim must say so and fail, not exec nothing.
emptyhome="$shimroot/empty"; mkdir -p "$emptyhome"
shim_out="$( env PATH="/usr/bin:/bin" HOME="$emptyhome" sh "$shimbin/harnessctl" 2>&1 )"; rc=$?
check_rc "with no plugin installed the shim exits non-zero" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check_rc "...and names the command that would fix it" \
  "$(printf '%s' "$shim_out" | grep -q 'claude plugin install harness-core' && echo 0 || echo 1)" \
  "got: $shim_out"

# --- 12a. the plugin upgrade path --------------------------------------------
# `claude plugin install` is a presence check: on an already-installed plugin it
# prints "is already installed" and exits 0 without comparing versions. So the
# installer's step 1 moved the marketplace to the latest while step 2 left the
# plugins where they were, and re-running the documented install command updated
# nothing. Found in the field at harness-core 1.13.0 against a marketplace
# serving 1.21.0 — eight minor versions of hooks, skills and verifiers, with no
# warning anywhere.
#
# Section 3's idempotence cases assert the opposite property ("re-install changes
# nothing on disk") and are right to: that is the declarative half, where a
# re-run must not churn a consumer's settings.json. The plugin half is the one
# place where a re-run is *supposed* to change something, and nothing looked at
# it. These cases are that.
#
# The fake claude logs its argv, so the assertion is on the command the installer
# actually issued rather than on anything it printed.
section "plugin upgrade path"

upg="$WORK/upgrade"
mkdir -p "$upg"
# $1 selects the plugin-install reply, $2 the plugin-update exit code. env -i
# clears the environment, so the log path is baked in rather than exported.
mk_fake_claude() {
  mkdir -p "$2"
  cat > "$2/claude" <<FAKE
#!/bin/sh
printf '%s\n' "\$*" >> "$3"
case "\$1 \$2" in
  'plugin install') echo '$1'; exit 0 ;;
  'plugin update')  exit $4 ;;
esac
exit 0
FAKE
  chmod +x "$2/claude"
}

run_upgrade_probe() {  # $1 = fakebin dir
  ( cd "$probe_cwd" && env -i PATH="$1:/usr/bin:/bin" HOME="$upg/home" \
      CLAUDE_CONFIG_DIR="$upg/cfg" BIN_DIR="$upg/bin" SHELL=/bin/bash \
      "$BASH_BIN" "$probe/install.sh" --profile core --scope user 2>&1 )
}

# Case 1 — already installed: the installer must follow up with an update.
log_a="$upg/a.log"; : > "$log_a"
mk_fake_claude '✔ Plugin "harness-core@agent-harness" is already installed (scope: user)' \
               "$upg/bin-a" "$log_a" 0
run_upgrade_probe "$upg/bin-a" >/dev/null 2>&1
check_rc "an already-installed plugin is followed by plugin update" \
  "$(grep -q 'plugin update harness-core@agent-harness' "$log_a" && echo 0 || echo 1)" \
  "issued: $(tr '\n' '|' < "$log_a")"
check_rc "...at the scope the install ran at" \
  "$(grep -q 'plugin update harness-core@agent-harness --scope user' "$log_a" && echo 0 || echo 1)" \
  "issued: $(tr '\n' '|' < "$log_a")"

# Case 2 — the boundary, and the one that earns its keep. A first install must
# NOT be chased with an update: that would prove only that an unconditional call
# was added, which is a different change with a different failure mode.
log_b="$upg/b.log"; : > "$log_b"
mk_fake_claude '✔ Successfully installed plugin: harness-core@agent-harness (scope: user)' \
               "$upg/bin-b" "$log_b" 0
run_upgrade_probe "$upg/bin-b" >/dev/null 2>&1
check_rc "a fresh install is not chased with an update" \
  "$(grep -q 'plugin update' "$log_b" && echo 1 || echo 0)" \
  "issued: $(tr '\n' '|' < "$log_b")"

# Case 3 — a failing update must stop the run. Reporting a successful install
# over a plugin half that did not move is the bug this section exists to catch,
# so the failure has to be loud.
log_c="$upg/c.log"; : > "$log_c"
mk_fake_claude '✔ Plugin "harness-core@agent-harness" is already installed (scope: user)' \
               "$upg/bin-c" "$log_c" 1
upg_out="$(run_upgrade_probe "$upg/bin-c")"; rc=$?
check_rc "a failing update aborts the install" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check_rc "...and the message names the plugin that failed" \
  "$(printf '%s' "$upg_out" | grep -q 'could not update harness-core' && echo 0 || echo 1)" \
  "got: $(printf '%s' "$upg_out" | tail -3)"

# --- 12b. uninstall.sh -------------------------------------------------------
# install.sh had no counterpart. `harnessctl uninstall` reverts the declarative
# half from its manifest and then prints "The plugins are untouched", leaving
# the plugin half, the marketplace registration and the shims as suggestions for
# the user to copy. uninstall.sh runs all four in the one order that works —
# harnessctl lives inside the plugin cache, so removing the plugins first
# strands the declarative half with no tool left to revert it.
#
# What is pinned here is the boundary: what it takes, and what it must not.
section "uninstall.sh"

UNINSTALL_SH="$HARNESS/uninstall.sh"

# The same header property install.sh is held to, for the same reason: a lost
# `#` in the usage block is perfectly good bash and `bash -n` cannot see it.
un_header_code="$(awk '/^set -uo pipefail/{exit} /^[[:space:]]*$/{next} /^[[:space:]]*#/{next} {print NR": "$0}' "$UNINSTALL_SH")"
check_rc "uninstall.sh: nothing executable hides in the usage header" \
  "$([ -z "$un_header_code" ] && echo 0 || echo 1)"
[ -n "$un_header_code" ] && printf '        %s\n' "$un_header_code"

# --help and the argument rejections run before the Claude CLI is looked for,
# so they work on a machine that has never seen Claude Code — including CI.
( env -i PATH="/usr/bin:/bin" "$BASH_BIN" "$UNINSTALL_SH" --help >/dev/null 2>&1 ); rc=$?
check_rc "uninstall.sh: --help exits 0 without the Claude CLI" "$rc"
( env -i PATH="/usr/bin:/bin" "$BASH_BIN" "$UNINSTALL_SH" --nope >/dev/null 2>&1 ); rc=$?
check_rc "uninstall.sh: an unknown argument is rejected" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
( env -i PATH="/usr/bin:/bin" "$BASH_BIN" "$UNINSTALL_SH" --scope sideways >/dev/null 2>&1 ); rc=$?
check_rc "uninstall.sh: an invalid scope is rejected" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"

# The shims are written by one script and found by the other, on a marker
# string that lives in both. Generating them with install.sh and removing them
# with uninstall.sh is what stops the two copies drifting apart in silence — a
# renamed marker would leave every shim behind and nothing would say so.
unbin="$shimroot/unbin"
unjqdir="$(dirname "$(type -P jq)")"
( cd "$probe_cwd" && env -i PATH="$fakebin:$unjqdir:/usr/bin:/bin" HOME="$fakehome" \
    CLAUDE_CONFIG_DIR="$altcfg" BIN_DIR="$unbin" SHELL=/bin/bash \
    "$BASH_BIN" "$probe/install.sh" --scope user >/dev/null 2>&1 )
check_rc "uninstall.sh: fixture — install.sh wrote a shim to remove" \
  "$([ -x "$unbin/harnessctl" ] && echo 0 || echo 1)"

# Two files that must survive, in the directory being swept. The jq is where
# install.sh's own bootstrap puts one, and by now anything on the machine may
# be using it; the lookalike is somebody else's executable that happens to sit
# next to ours. Neither carries the marker, so neither may be touched — the
# marker and not the directory is what decides.
# A working jq, not a stub, and delegating rather than copied. uninstall.sh
# prepends BIN_DIR to PATH exactly as install.sh does — that is how a
# bootstrapped jq becomes usable — so whatever sits here under the name `jq` is
# the jq the rest of the script then runs, and a stub made every `| jq` return
# nothing. Copying the real one is worse and quieter: macOS ships jq at
# /usr/bin, and a copy of a system binary loses its code-signing context and is
# SIGKILLed (137) the moment it runs, so the pipelines went empty with no error
# at all. Delegate, and it works wherever the real jq does.
printf '#!/bin/sh\nexec %s "$@"\n' "$(type -P jq)" > "$unbin/jq"; chmod +x "$unbin/jq"
printf '#!/bin/sh\necho not ours\n' > "$unbin/harnessctl-lookalike"; chmod +x "$unbin/harnessctl-lookalike"

run_uninstall() { ( cd "$probe_cwd" && env -i PATH="$fakebin:$unjqdir:/usr/bin:/bin" \
  HOME="$fakehome" CLAUDE_CONFIG_DIR="$altcfg" BIN_DIR="$unbin" SHELL=/bin/bash \
  "$BASH_BIN" "$UNINSTALL_SH" "$@" 2>&1 ); }

# --dry-run is the property the whole script rests on: every mutation goes
# through one wrapper, so a step that forgot to check the flag would show up
# here as a shim that vanished during a run that promised to write nothing.
un_out="$(run_uninstall --dry-run)"
check_rc "uninstall.sh: --dry-run leaves the shims in place" \
  "$([ -x "$unbin/harnessctl" ] && echo 0 || echo 1)"
check_rc "uninstall.sh: --dry-run says it wrote nothing" \
  "$(printf '%s' "$un_out" | grep -q 'dry-run finished' && echo 0 || echo 1)" \
  "got: $un_out"

# A missing manifest is an ordinary state — the plugin half installs without
# `harnessctl init` ever running — and harnessctl dies on it. uninstall.sh has
# three steps left at that point, so it must report and carry on, not abort.
check_rc "uninstall.sh: a missing manifest is reported, not fatal" \
  "$(printf '%s' "$un_out" | grep -q 'nothing to revert' && echo 0 || echo 1)" \
  "got: $un_out"
check_rc "...and the run still reaches the shim step" \
  "$(printf '%s' "$un_out" | grep -q 'shell shims' && echo 0 || echo 1)" \
  "got: $un_out"

un_out="$(run_uninstall)"
check_rc "uninstall.sh: the shims install.sh wrote are removed" \
  "$([ -e "$unbin/harnessctl" ] && echo 1 || echo 0)"
check_rc "...every one of them, not just the first" \
  "$([ -e "$unbin/harness-log" ] && echo 1 || echo 0)"
check_rc "uninstall.sh: a bootstrapped jq in the same directory survives" \
  "$([ -x "$unbin/jq" ] && echo 0 || echo 1)"
check_rc "uninstall.sh: an executable without the marker survives" \
  "$([ -x "$unbin/harnessctl-lookalike" ] && echo 0 || echo 1)"
check_rc "uninstall.sh: the surviving jq is reported rather than removed" \
  "$(printf '%s' "$un_out" | grep -q 'left in place' && echo 0 || echo 1)" \
  "got: $un_out"

# With a manifest present the declarative branch is taken, and it has to reach
# harnessctl *in the plugin cache* — the copy step 3 of install.sh resolves, not
# a shim, which by this point in the run has already been deleted. The fixture
# harnessctl announces its version, so its appearance in the output is proof the
# right binary was invoked and not merely that the branch was entered.
: > "$altcfg/harness-manifest.json"
un_out="$(run_uninstall --dry-run)"
check_rc "uninstall.sh: a present manifest reaches harnessctl in the cache" \
  "$(printf '%s' "$un_out" | grep -q 'harnessctl uninstall --scope user' && echo 0 || echo 1)" \
  "got: $un_out"
check_rc "...the newest one, not a superseded copy" \
  "$(printf '%s' "$un_out" | grep -q '1\.10\.0' && echo 0 || echo 1)" \
  "got: $un_out"

# Regression. The plugin and marketplace steps were written as
# `run cmd >/dev/null 2>&1`, which redirects the *wrapper's* own "would run"
# line as well — so --dry-run went silent about the two steps it was being
# asked to preview, and the marketplace step then reported "removed" for a
# registration it had not touched. The fake above answers `plugin --help` and
# nothing else, so neither step had anything to do and neither bug showed up.
# This fake answers the three subcommands the steps actually read.
unfake="$shimroot/unfakebin"
mkdir -p "$unfake"
cat > "$unfake/claude" <<'FAKE'
#!/bin/sh
if [ "$1" = plugin ] && [ "$2" = list ] && [ "$3" = --json ]; then
  cat "$UNFAKE_JSON"; exit 0
fi
if [ "$1" = plugin ] && [ "$2" = marketplace ] && [ "$3" = list ]; then
  printf 'Configured marketplaces:\n\n  \342\235\257 agent-harness\n    Source: GitHub (chpark-ML/agent-harness)\n\n  \342\235\257 headroom-marketplace\n    Source: GitHub (headroomlabs-ai/headroom)\n'
  exit 0
fi
exit 0
FAKE
chmod +x "$unfake/claude"

# Everything of ours at the scope being removed, so step 4 reaches its remove
# branch. The foreign entry is what the report at the end must find.
cat > "$shimroot/all-user.json" <<'J'
[{"id":"harness-core@agent-harness","scope":"user","enabled":true},
 {"id":"headroom@headroom-marketplace","scope":"project","enabled":false}]
J
un_out="$( cd "$probe_cwd" && env -i PATH="$unfake:$unjqdir:/usr/bin:/bin" \
  HOME="$fakehome" CLAUDE_CONFIG_DIR="$altcfg" BIN_DIR="$unbin" \
  UNFAKE_JSON="$shimroot/all-user.json" \
  "$BASH_BIN" "$UNINSTALL_SH" --dry-run 2>&1 )"
check_rc "uninstall.sh: --dry-run shows the plugin command it would run" \
  "$(printf '%s' "$un_out" | grep -q 'would run: claude plugin uninstall harness-core@agent-harness' && echo 0 || echo 1)" \
  "got: $un_out"
check_rc "uninstall.sh: --dry-run shows the marketplace command it would run" \
  "$(printf '%s' "$un_out" | grep -q 'would run: claude plugin marketplace remove agent-harness' && echo 0 || echo 1)" \
  "got: $un_out"
check_rc "uninstall.sh: --dry-run never claims the marketplace was removed" \
  "$(printf '%s' "$un_out" | grep -qE '^==>   removed$' && echo 1 || echo 0)" \
  "got: $un_out"
# The bullet Claude Code prints is multibyte. Parsing it with `.` matched under
# a UTF-8 locale and nothing at all under C, which is the locale CI and a
# Windows console both hand this script — a silently empty report.
check_rc "uninstall.sh: a foreign marketplace is reported under LC_ALL=C" \
  "$(printf '%s' "$un_out" | grep -q 'headroom-marketplace' && echo 0 || echo 1)" \
  "got: $un_out"
check_rc "uninstall.sh: a foreign plugin is reported, not removed" \
  "$(printf '%s' "$un_out" | grep -q 'headroom@headroom-marketplace' && echo 0 || echo 1)" \
  "got: $un_out"

# The other side of step 4: something of ours still installed at the other
# scope means the registration has to stay, or that install stops resolving.
cat > "$shimroot/split-scope.json" <<'J'
[{"id":"harness-core@agent-harness","scope":"user","enabled":true},
 {"id":"harness-dev@agent-harness","scope":"project","enabled":true}]
J
un_out="$( cd "$probe_cwd" && env -i PATH="$unfake:$unjqdir:/usr/bin:/bin" \
  HOME="$fakehome" CLAUDE_CONFIG_DIR="$altcfg" BIN_DIR="$unbin" \
  UNFAKE_JSON="$shimroot/split-scope.json" \
  "$BASH_BIN" "$UNINSTALL_SH" --dry-run 2>&1 )"
check_rc "uninstall.sh: the marketplace is kept while another scope still uses it" \
  "$(printf '%s' "$un_out" | grep -q 'kept — still used by' && echo 0 || echo 1)" \
  "got: $un_out"
check_rc "...and names what is still holding it" \
  "$(printf '%s' "$un_out" | grep -q 'harness-dev@agent-harness' && echo 0 || echo 1)" \
  "got: $un_out"

# Regression, and the one that matters most. `set -o pipefail` carries
# harnessctl's status out of step 2's pipeline, but nothing read it: a failed
# `harnessctl uninstall` printed its error as ordinary indented output and the
# run carried straight on to delete the plugins. That is unrecoverable — step 3
# removes the cache harnessctl lives in, so the declarative half it had just
# failed to revert can never be reverted afterwards. Reproduced before the fix.
unfail="$shimroot/failcfg"
mkdir -p "$unfail/plugins/cache/agent-harness/harness-core/1.0.0/bin"
: > "$unfail/plugins/cache/agent-harness/harness-core/1.0.0/.in_use"
: > "$unfail/harness-manifest.json"
printf '#!/bin/sh\necho "could not write settings" >&2\nexit 1\n' \
  > "$unfail/plugins/cache/agent-harness/harness-core/1.0.0/bin/harnessctl"
chmod +x "$unfail/plugins/cache/agent-harness/harness-core/1.0.0/bin/harnessctl"
# Records every uninstall it is asked for, so the assertion is about what the
# script actually did rather than about what it printed.
unlog="$shimroot/uninstall-calls.log"
: > "$unlog"
cat > "$unfake/claude-failcase" <<'FAKE'
#!/bin/sh
if [ "$1" = plugin ] && [ "$2" = list ] && [ "$3" = --json ]; then
  echo '[{"id":"harness-core@agent-harness","scope":"user","enabled":true}]'; exit 0
fi
if [ "$1" = plugin ] && [ "$2" = uninstall ]; then echo "$3" >> "$UNLOG"; exit 0; fi
exit 0
FAKE
unfailbin="$shimroot/failbin"; mkdir -p "$unfailbin"
cp "$unfake/claude-failcase" "$unfailbin/claude"; chmod +x "$unfailbin/claude"
un_out="$( cd "$probe_cwd" && env -i PATH="$unfailbin:$unjqdir:/usr/bin:/bin" \
  HOME="$fakehome" CLAUDE_CONFIG_DIR="$unfail" BIN_DIR="$unbin" UNLOG="$unlog" \
  "$BASH_BIN" "$UNINSTALL_SH" 2>&1 )"; rc=$?
check_rc "uninstall.sh: a failed harnessctl uninstall stops the run" \
  "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "rc=$rc, got: $un_out"
check_rc "...before a single plugin is removed" \
  "$([ -s "$unlog" ] && echo 1 || echo 0)" \
  "plugins uninstalled anyway: $(cat "$unlog")"
check_rc "...and says why stopping there is the point" \
  "$(printf '%s' "$un_out" | grep -q 'delete the only' && echo 0 || echo 1)" \
  "got: $un_out"

# --- 13. doctor reports the plugin half -------------------------------------
# harnessctl installs no plugins and removes none, so both commands used to say
# nothing about them — except one hardcoded line naming harness-core, while a
# default install places four. A consumer following it left three behind.
section "doctor: plugins and shims"

pcache="$WORK/pcache/plugins/cache"
mkdir -p "$pcache/agent-harness/harness-core/1.9.0" \
         "$pcache/agent-harness/harness-core/1.10.0" \
         "$pcache/agent-harness/harness-dev/2.0.0" \
         "$pcache/agent-harness/harness-python/1.0.0" \
         "$pcache/claude-plugins-official/superpowers/6.2.0" \
         "$pcache/claude-plugins-official/unrelated-plugin/1.0.0"
# harness-python's only version is superseded — it is gone, and must not be
# listed. Marking 1.9.0 too pins that the newest survivor wins.
: > "$pcache/agent-harness/harness-python/1.0.0/.orphaned_at"
: > "$pcache/agent-harness/harness-core/1.9.0/.orphaned_at"
# No .in_use anywhere on purpose: requiring that marker reported the current
# version as missing, because it was observed absent right after an update.

dshim="$WORK/dshim"; mkdir -p "$dshim"
printf '#!/bin/sh\n# harnessctl shim — resolves the installed plugin at run time.\n' > "$dshim/harnessctl"
printf '#!/bin/sh\necho not-a-shim\n' > "$dshim/something-else"
chmod +x "$dshim/harnessctl" "$dshim/something-else"

dout="$( cd "$C" && env PATH="$PATH" HOME="$WORK/pcache" \
         CLAUDE_CONFIG_DIR="$WORK/pcache" BIN_DIR="$dshim" \
         "$BASH_BIN" "$HCTL" doctor --scope project 2>&1 )"

check_rc "doctor lists an installed plugin with its version" \
  "$(printf '%s' "$dout" | grep -q 'harness-core@agent-harness  1.10.0' && echo 0 || echo 1)" \
  "got: $(printf '%s' "$dout" | grep -i 'harness-core@' | head -1)"
check_rc "...choosing the newest surviving version" \
  "$(printf '%s' "$dout" | grep -q '1.9.0' && echo 1 || echo 0)"
# Scoped to the plugin section: `harness-python` legitimately appears earlier,
# in the language-server line, and matching the whole output would fail on that.
dplugins="$(printf '%s' "$dout" | sed -n '/^plugins (installed by Claude Code/,/^no problems\|^!/p')"
check_rc "...and omitting a plugin whose only version is orphaned" \
  "$(printf '%s' "$dplugins" | grep -q 'harness-python' && echo 1 || echo 0)"
check_rc "...and a dependency from another marketplace" \
  "$(printf '%s' "$dout" | grep -q 'superpowers@claude-plugins-official' && echo 0 || echo 1)"
check_rc "...but nothing unrelated" \
  "$(printf '%s' "$dout" | grep -q 'unrelated-plugin' && echo 1 || echo 0)"
check_rc "doctor prints an uninstall command per plugin" \
  "$(printf '%s' "$dout" | grep -c 'claude plugin uninstall' | grep -q '^3$' && echo 0 || echo 1)" \
  "got: $(printf '%s' "$dout" | grep -c 'claude plugin uninstall') lines"
check_rc "doctor names the shims it can see" \
  "$(printf '%s' "$dout" | grep -q "$dshim/harnessctl" && echo 0 || echo 1)"
check_rc "...and not unrelated files in the same directory" \
  "$(printf '%s' "$dout" | grep -q 'something-else' && echo 1 || echo 0)"

# The same discovery has to drive uninstall's closing hint, or the two drift.
# uninstall refuses without a manifest, so this needs its own installed project.
uproj="$WORK/uproj"
new_consumer "$uproj" bare
run_install "$uproj" >/dev/null 2>&1
uout="$( cd "$uproj" && env PATH="$PATH" HOME="$WORK/pcache" \
         CLAUDE_CONFIG_DIR="$WORK/pcache" BIN_DIR="$dshim" \
         "$BASH_BIN" "$HCTL" uninstall --scope project 2>&1 )"
check_rc "uninstall names every installed plugin, not just harness-core" \
  "$(printf '%s' "$uout" | grep -c 'claude plugin uninstall' | grep -q '^3$' && echo 0 || echo 1)" \
  "got: $(printf '%s' "$uout" | grep 'claude plugin uninstall' | tr '\n' ' ')"

# A name is not an identity. A plugin that merely calls itself harness-* in an
# unrelated marketplace — or a superpowers under the wrong one — must not be
# swept into a list that ends in destructive uninstall suggestions.
mkdir -p "$pcache/some-forge/harness-core/3.0.0" \
         "$pcache/agent-harness/superpowers/1.0.0"
dout2="$( cd "$C" && env PATH="$PATH" HOME="$WORK/pcache" \
          CLAUDE_CONFIG_DIR="$WORK/pcache" BIN_DIR="$dshim" \
          "$BASH_BIN" "$HCTL" doctor --scope project 2>&1 )"
check_rc "a harness-core under a foreign marketplace is not listed" \
  "$(printf '%s' "$dout2" | grep -q 'harness-core@some-forge' && echo 1 || echo 0)" \
  "got: $(printf '%s' "$dout2" | grep 'some-forge' | head -1)"
check_rc "a superpowers under agent-harness is not listed" \
  "$(printf '%s' "$dout2" | grep -q 'superpowers@agent-harness' && echo 1 || echo 0)"
check_rc "...and the legitimate ones still are" \
  "$(printf '%s' "$dout2" | grep -q 'harness-core@agent-harness  1.10.0' && echo 0 || echo 1)"

# sort without -V. The resolution has to degrade to lexicographic, not die —
# a doctor whose sort dies reports a working plugin half as absent.
nosortv="$WORK/nosortv"; mkdir -p "$nosortv"
cat > "$nosortv/sort" <<'SH'
#!/bin/sh
for a in "$@"; do [ "$a" = "-V" ] && { echo "sort: illegal option -- V" >&2; exit 2; }; done
exec /usr/bin/sort "$@"
SH
chmod +x "$nosortv/sort"
dout3="$( cd "$C" && env PATH="$nosortv:$PATH" HOME="$WORK/pcache" \
          CLAUDE_CONFIG_DIR="$WORK/pcache" BIN_DIR="$dshim" \
          "$BASH_BIN" "$HCTL" doctor --scope project 2>&1 )"
check_rc "without sort -V the plugin list still resolves" \
  "$(printf '%s' "$dout3" | grep -q 'harness-core@agent-harness' && echo 0 || echo 1)" \
  "got: $(printf '%s' "$dout3" | grep -A2 '^plugins' | head -3 | tr '\n' ' ')"

# --- 14. doctor reports config that claims a plugin nothing can load -----------
# enabledPlugins says a plugin is on; if its marketplace was removed or it was
# never cached, the entry stays and nothing ever prints an error. That is the
# state a stale machine drifts into invisibly, and it is what PR #24's script
# was written to find — kept as a doctor check rather than a separate script so
# it comes with these cases.
section "doctor: config integrity"

cfg2="$WORK/cfg2"
mkdir -p "$cfg2/plugins/cache/agent-harness/harness-core/1.0.0" \
         "$cfg2/plugins/marketplaces/agent-harness" \
         "$cfg2/plugins/marketplaces/ghost-forge"
cat > "$cfg2/settings.json" <<'J'
{"enabledPlugins":{"harness-core@agent-harness":true,"harness-core@vanished-forge":true}}
J

iout="$( cd "$C" && env PATH="$PATH" HOME="$cfg2" CLAUDE_CONFIG_DIR="$cfg2" \
         BIN_DIR="$WORK/nobin2" "$BASH_BIN" "$HCTL" doctor --scope project 2>&1 )"; irc=$?

check_rc "a dangling enabledPlugins entry is reported" \
  "$(printf '%s' "$iout" | grep -q 'enabled but not installed: harness-core@vanished-forge' && echo 0 || echo 1)" \
  "got: $(printf '%s' "$iout" | grep -i 'enabled but' | head -1)"
check_rc "...as a failure, not a note" "$([ "$irc" -ne 0 ] && echo 0 || echo 1)"
check_rc "...while the resolvable one is not reported" \
  "$(printf '%s' "$iout" | grep -q 'enabled but not installed: harness-core@agent-harness' && echo 1 || echo 0)"
check_rc "an unused marketplace is a note" \
  "$(printf '%s' "$iout" | grep -q 'no enabled plugin uses.*ghost-forge' && echo 0 || echo 1)" \
  "got: $(printf '%s' "$iout" | grep 'no enabled plugin uses' | head -1)"

# The note must not be what fails the run — a doctor that raises alarms over
# harmless state is a doctor people stop reading.
cat > "$cfg2/settings.json" <<'J'
{"enabledPlugins":{"harness-core@agent-harness":true}}
J
jout="$( cd "$C" && env PATH="$PATH" HOME="$cfg2" CLAUDE_CONFIG_DIR="$cfg2" \
         BIN_DIR="$WORK/nobin2" "$BASH_BIN" "$HCTL" doctor --scope project 2>&1 )"; jrc=$?
check_rc "an unused marketplace alone does not fail the run" "$([ "$jrc" -eq 0 ] && echo 0 || echo 1)" \
  "got exit $jrc"
check_rc "...and is still mentioned" \
  "$(printf '%s' "$jout" | grep -q 'ghost-forge' && echo 0 || echo 1)"

# An orphaned-only cache is not an install: the entry has nothing to load.
mkdir -p "$cfg2/plugins/cache/agent-harness/harness-dev/9.9.9"
: > "$cfg2/plugins/cache/agent-harness/harness-dev/9.9.9/.orphaned_at"
cat > "$cfg2/settings.json" <<'J'
{"enabledPlugins":{"harness-dev@agent-harness":true}}
J
kout="$( cd "$C" && env PATH="$PATH" HOME="$cfg2" CLAUDE_CONFIG_DIR="$cfg2" \
         BIN_DIR="$WORK/nobin2" "$BASH_BIN" "$HCTL" doctor --scope project 2>&1 )"
check_rc "a superseded-only cache counts as not installed" \
  "$(printf '%s' "$kout" | grep -q 'enabled but not installed: harness-dev@agent-harness' && echo 0 || echo 1)"

# --- 15. doctor: composite always-on cost -------------------------------------
# The context-budget gate sums what this harness ships; a session pays for every
# enabled plugin. Two third-party installs pushed a real session past the
# ceiling while the gate printed green (2026-08-13), so doctor now reports the
# whole composite, informationally. The claude CLI is stubbed so the priced
# branch runs identically on machines with and without the real one — a branch
# that runs in only one environment is an unverified branch.
section "doctor: composite always-on cost"

cfg3="$WORK/cfg3"
mkdir -p "$cfg3/plugins/cache/forge/alpha/1.0.0" \
         "$cfg3/plugins/cache/forge/beta/1.0.0" \
         "$cfg3/plugins/cache/forge/gamma/1.0.0" \
         "$cfg3/plugins/cache/forge/delta/1.0.0" \
         "$cfg3/plugins/marketplaces/forge"
cat > "$cfg3/settings.json" <<'J'
{"enabledPlugins":{"alpha@forge":true,"beta@forge":true,"gamma@forge":false,"delta@forge":true}}
J

# The stub answers the one call doctor makes. alpha's figure carries a comma —
# the real CLI prints `~28,321 tok` — so the sum below also pins the parsing.
cstub="$WORK/cstub"; mkdir -p "$cstub"
cat > "$cstub/claude" <<'SH'
#!/bin/sh
[ "$1" = plugin ] && [ "$2" = details ] || exit 1
case "$3" in
  alpha@forge) printf 'Projected token cost\n  Always-on:   ~1,234 tok   added to every session\n' ;;
  beta@forge)  printf '  Always-on:   ~98 tok   added to every session\n' ;;
  *) echo "no such plugin" >&2; exit 1 ;;
esac
SH
chmod +x "$cstub/claude"

lout="$( cd "$C" && env PATH="$cstub:$PATH" HOME="$cfg3" CLAUDE_CONFIG_DIR="$cfg3" \
         BIN_DIR="$cfg3/nobin" "$BASH_BIN" "$HCTL" doctor --scope project 2>&1 )"; lrc=$?
check_rc "the composite total sums every priced plugin, commas stripped" \
  "$(printf '%s' "$lout" | grep -q 'total ~1332 tok' && echo 0 || echo 1)" \
  "got: $(printf '%s' "$lout" | grep 'total ~' | head -1)"
check_rc "...a disabled entry is neither priced nor listed" \
  "$(printf '%s' "$lout" | grep -q 'gamma@forge' && echo 1 || echo 0)"
check_rc "...a plugin the CLI cannot price is named, not dropped" \
  "$(printf '%s' "$lout" | grep -q 'no Always-on figure.*delta@forge' && echo 0 || echo 1)" \
  "got: $(printf '%s' "$lout" | grep 'no Always-on' | head -1)"
check_rc "...and the section is informational — the run still passes" \
  "$([ "$lrc" -eq 0 ] && echo 0 || echo 1)" "got exit $lrc"

# No enabled plugins at all is a note, not silence and not a failure.
cfg3b="$WORK/cfg3b"; mkdir -p "$cfg3b/plugins/cache"
printf '{"enabledPlugins":{}}\n' > "$cfg3b/settings.json"
nout="$( cd "$C" && env PATH="$cstub:$PATH" HOME="$cfg3b" CLAUDE_CONFIG_DIR="$cfg3b" \
         BIN_DIR="$cfg3b/nobin" "$BASH_BIN" "$HCTL" doctor --scope project 2>&1 )"
check_rc "an empty enabledPlugins degrades to a note" \
  "$(printf '%s' "$nout" | grep -q 'no enabled plugins recorded' && echo 0 || echo 1)" \
  "got: $(printf '%s' "$nout" | grep -A1 'always-on context' | tail -1)"

# Without the claude CLI the section skips with a note — built from wrappers so
# the absence is real on a machine that has the CLI, and the case still runs on
# one that does not. Resolved with `type -P`, not `command -v`: this library
# defines jq as a CR-stripping shell function, and `command -v jq` answers with
# the function — the same trap the hook verifiers already document.
noclaude="$WORK/noclaude"; mkdir -p "$noclaude"
for t in bash jq git awk grep sed tr head sort basename dirname ls cat mktemp uname; do
  p="$(type -P "$t" 2>/dev/null)" || continue
  case "$p" in /*) ;; *) continue ;; esac
  printf '#!/bin/sh\nexec %s "$@"\n' "$p" > "$noclaude/$t"
  chmod +x "$noclaude/$t"
done
mout="$( cd "$C" && env PATH="$noclaude" HOME="$cfg3" CLAUDE_CONFIG_DIR="$cfg3" \
         BIN_DIR="$cfg3/nobin" "$BASH_BIN" "$HCTL" doctor --scope project 2>&1 )"; mrc=$?
check_rc "without the claude CLI the composite section skips with a note" \
  "$(printf '%s' "$mout" | grep -q 'skipped — claude CLI not on PATH' && echo 0 || echo 1)" \
  "got: $(printf '%s' "$mout" | grep -A1 'always-on context' | tail -1)"
check_rc "...and skipping is not a failure" \
  "$([ "$mrc" -eq 0 ] && echo 0 || echo 1)" "got exit $mrc"

# --- 13. the jq bootstrap ----------------------------------------------------
# jq is required by every guard and by harnessctl, and a machine without root
# had no way through. What made it worth a verifier rather than a one-liner is
# how it failed: harnessctl's own `jq is required` preflight never fired (a CR
# wrapper shadowed `command -v jq` with a shell function), so the install died
# blaming a settings.json that was perfectly valid. Nothing said "jq".
#
# The platform is stubbed to Linux/x86_64 throughout, so these run identically
# on macOS, Linux and CI, and the expected hash below is a fixed constant rather
# than whatever the host happens to be.
section "jq bootstrap"

LINUX_AMD64_SHA="b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f"

jqroot="$WORK/jq"
jqstub="$jqroot/stub"      # stubs: claude, curl, uname, sha256sum
jqreal="$jqroot/real"      # the real tools install.sh needs, deliberately no jq
mkdir -p "$jqstub" "$jqreal"

# A PATH with the usual tools and no jq. `env -i` plus this is what makes the
# absence real; pointing PATH at /usr/bin would hand the script the host's jq.
# `bash` is on this list because install.sh invokes harnessctl as `bash "$HCTL"`,
# by name and not by path.
for t in bash sh env sed grep ls sort tail head cut basename dirname mkdir mv rm \
         chmod cmp cat mktemp uname awk tr find touch wc; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$jqreal/$t"
done
# Both hashers, when the host has them: file_sha256 prefers sha256sum and falls
# back to shasum, and the mismatch case below needs a real one of either.
have_hasher=0
for t in sha256sum shasum; do
  p="$(command -v "$t" 2>/dev/null)" && { ln -sf "$p" "$jqreal/$t"; have_hasher=1; }
done

printf '#!/bin/sh\nexit 0\n' > "$jqstub/claude"
printf '#!/bin/sh\ncase "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac\n' > "$jqstub/uname"
# Records the URL, then serves a runnable stand-in so the post-install smoke
# test (`jq --version`) has something to execute.
cat > "$jqstub/curl" <<'CURL'
#!/bin/sh
echo "$*" >> "$CURL_LOG"
out=""
while [ $# -gt 0 ]; do
  case "$1" in -o) shift; out="$1" ;; esac
  shift
done
[ -n "$out" ] || exit 1
printf '#!/bin/sh\necho jq-1.8.2\n' > "$out"
CURL
chmod +x "$jqstub/claude" "$jqstub/uname" "$jqstub/curl"

# A stubbed hasher that agrees with the table, so the success path can be
# exercised without a byte-exact copy of the real release.
printf '#!/bin/sh\necho "%s  $1"\n' "$LINUX_AMD64_SHA" > "$jqstub/sha256sum"
chmod +x "$jqstub/sha256sum"

# A cache holding a fake harnessctl that reports whether jq reached it. This is
# the only honest test of the PATH export: install.sh itself never calls jq, so
# the property is "the child process that needs jq can find it", and asserting
# on install.sh's own output cannot tell the export apart from the absolute path
# it prints anyway. Removing the export has to turn a case red, and this is the
# case that goes red.
jqcache="$jqroot/cfg/plugins/cache/agent-harness/harness-core/1.0.0"
mkdir -p "$jqcache/bin"
: > "$jqcache/.in_use"
printf '#!/bin/sh\necho "harnessctl saw jq at: $(command -v jq || echo NONE)"\n' \
  > "$jqcache/bin/harnessctl"
chmod +x "$jqcache/bin/harnessctl"

# install.sh reads BIN_DIR for both the shims and a bootstrapped jq.
run_install() {
  # $1 = BIN_DIR, rest = PATH entries in order
  local bd="$1"; shift
  local p=""
  for d in "$@"; do p="${p:+$p:}$d"; done
  ( cd "$probe_cwd" && env -i PATH="$p" HOME="$jqroot/home" SHELL=/bin/bash \
      CLAUDE_CONFIG_DIR="$jqroot/cfg" BIN_DIR="$bd" CURL_LOG="$jqroot/curl.log" \
      "$BASH_BIN" "$probe/install.sh" --scope user 2>&1 )
}

# --- no-op: a machine that already has jq must not fetch one.
: > "$jqroot/curl.log"
mkdir -p "$jqroot/hasjq"
printf '#!/bin/sh\necho jq-1.7.1\n' > "$jqroot/hasjq/jq"
chmod +x "$jqroot/hasjq/jq"
out="$(run_install "$jqroot/bin-hasjq" "$jqroot/hasjq" "$jqstub" "$jqreal")"
check_rc "an existing jq is left alone" \
  "$([ ! -s "$jqroot/curl.log" ] && echo 0 || echo 1)" \
  "curl was called: $(cat "$jqroot/curl.log")"
check_rc "...and nothing is written to BIN_DIR for it" \
  "$([ ! -e "$jqroot/bin-hasjq/jq" ] && echo 0 || echo 1)"

# --- success: jq absent, download served by the stub.
: > "$jqroot/curl.log"
out="$(run_install "$jqroot/bin-ok" "$jqstub" "$jqreal")"
check_rc "a missing jq is fetched" \
  "$([ -s "$jqroot/curl.log" ] && echo 0 || echo 1)"
check_rc "...from the pinned release, for this platform's asset" \
  "$(grep -q 'releases/download/jq-1.8.2/jq-linux-amd64$' "$jqroot/curl.log" && echo 0 || echo 1)" \
  "asked for: $(cat "$jqroot/curl.log")"
check_rc "...and lands in BIN_DIR, executable" \
  "$([ -x "$jqroot/bin-ok/jq" ] && echo 0 || echo 1)"
check_rc "...leaving no partial download behind" \
  "$(ls "$jqroot/bin-ok"/jq.download.* >/dev/null 2>&1 && echo 1 || echo 0)"
check_rc "...and the install carries on past it" \
  "$(printf '%s' "$out" | grep -q '==> marketplace' && echo 0 || echo 1)" \
  "got: $out"
# The whole point of the PATH export: harnessctl needs jq, and it is a child
# process, so it gets whatever PATH install.sh leaves it.
check_rc "...and harnessctl inherits a PATH that finds the new jq" \
  "$(printf '%s' "$out" | grep -q "harnessctl saw jq at: $jqroot/bin-ok/jq" && echo 0 || echo 1)" \
  "got: $out"

# --- boundary: the checksum is what decides, and it must be able to say no.
# The real hasher runs against the stand-in file, whose hash is nothing like the
# pinned one. Dropping the stubbed hasher from PATH is cleaner than trying to
# outrank it.
jqstub_nohash="$jqroot/stub-nohash"
mkdir -p "$jqstub_nohash"
for f in claude curl uname; do cp "$jqstub/$f" "$jqstub_nohash/$f"; done
chmod +x "$jqstub_nohash"/*
if [ "$have_hasher" -eq 1 ]; then
  : > "$jqroot/curl.log"
  out="$(run_install "$jqroot/bin-bad" "$jqstub_nohash" "$jqreal")"
  check_rc "a checksum mismatch stops the install" \
    "$(printf '%s' "$out" | grep -q 'checksum mismatch' && echo 0 || echo 1)" \
    "got: $out"
  check_rc "...and refuses to leave the binary behind" \
    "$([ ! -e "$jqroot/bin-bad/jq" ] && echo 0 || echo 1)"
  check_rc "...including the partial download" \
    "$(ls "$jqroot/bin-bad"/jq.download.* >/dev/null 2>&1 && echo 1 || echo 0)"
else
  skip_case "a checksum mismatch stops the install" "no sha256sum or shasum on this machine"
fi

# --- boundary: no hasher at all. An unverifiable binary is not run.
jqreal_nohash="$jqroot/real-nohash"
mkdir -p "$jqreal_nohash"
for f in "$jqreal"/*; do
  case "$(basename "$f")" in sha256sum|shasum) ;; *) ln -sf "$f" "$jqreal_nohash/$(basename "$f")" ;; esac
done
: > "$jqroot/curl.log"
out="$(run_install "$jqroot/bin-nohash" "$jqstub_nohash" "$jqreal_nohash")"
check_rc "an unverifiable download is refused" \
  "$(printf '%s' "$out" | grep -q 'neither sha256sum nor shasum' && echo 0 || echo 1)" \
  "got: $out"
check_rc "...and nothing is left in BIN_DIR" \
  "$([ ! -e "$jqroot/bin-nohash/jq" ] && echo 0 || echo 1)"

# --- boundary: no curl. The message must name jq, which is the whole point.
jqstub_nocurl="$jqroot/stub-nocurl"
mkdir -p "$jqstub_nocurl"
cp "$jqstub/claude" "$jqstub/uname" "$jqstub_nocurl/"
chmod +x "$jqstub_nocurl"/*
out="$(run_install "$jqroot/bin-nocurl" "$jqstub_nocurl" "$jqreal")"
check_rc "no curl fails with a message that names jq" \
  "$(printf '%s' "$out" | grep -q 'jq is missing and there is no curl' && echo 0 || echo 1)" \
  "got: $out"

# --- boundary: a platform jq does not publish for.
jqstub_sun="$jqroot/stub-sun"
mkdir -p "$jqstub_sun"
cp "$jqstub/claude" "$jqstub/curl" "$jqstub_sun/"
printf '#!/bin/sh\ncase "$1" in -s) echo SunOS ;; -m) echo sparc ;; esac\n' > "$jqstub_sun/uname"
chmod +x "$jqstub_sun"/*
: > "$jqroot/curl.log"
out="$(run_install "$jqroot/bin-sun" "$jqstub_sun" "$jqreal")"
check_rc "an unpublished platform fails without guessing an asset" \
  "$(printf '%s' "$out" | grep -q 'publishes no build for this platform' && echo 0 || echo 1)" \
  "got: $out"
check_rc "...and downloads nothing" \
  "$([ ! -s "$jqroot/curl.log" ] && echo 0 || echo 1)"

# --- static: the pinned table. A truncated or edited hash is not something the
# stubbed cases above can see, because they stub the hasher.
table="$(sed -n '/^jq_sha256()/,/^}/p' "$INSTALL_SH")"
check_eq "the hash table covers all six published assets" 6 \
  "$(printf '%s' "$table" | grep -c "jq-\(linux\|macos\|windows\)-\(amd64\|arm64\)")"
check_eq "every pinned hash is a full sha256" 6 \
  "$(printf '%s' "$table" | grep -c "'[0-9a-f]\{64\}'")"
check_rc "the pinned linux-amd64 hash is the one upstream published" \
  "$(printf '%s' "$table" | grep -q "$LINUX_AMD64_SHA" && echo 0 || echo 1)"

# --- 14. jq guards that can actually fail ------------------------------------
# The incident these come from: the CR-stripping `jq()` shell function makes
# `command -v jq` answer with the function name, so every guard written that way
# returns 0 whether or not jq exists. harnessctl's preflight was dead, and a
# machine with no jq was told its settings.json was not a JSON object.
#
# verify_begin asserts the same thing per hook. These cover the two executables
# and the library, which no hook verifier reaches, and they assert on behaviour
# rather than on the spelling: the message a user without jq actually gets.
section "jq guards"

nojq="$WORK/nojq"
mkdir -p "$nojq/cfg"
# A settings.json that is beyond reproach. If the message mentions it, the
# preflight above it did not fire.
printf '{"model":"opus"}\n' > "$nojq/cfg/settings.json"

# $jqreal is the tool set from section 13, deliberately built without jq.
run_nojq() { ( cd "$WORK" && env -i PATH="$jqreal" HOME="$nojq" \
                 CLAUDE_CONFIG_DIR="$nojq/cfg" BIN_DIR="$nojq/bin" \
                 "$BASH_BIN" "$@" 2>&1 ) }

out="$(run_nojq "$HCTL" init --scope user --dry-run)"
check_rc "harnessctl without jq says so" \
  "$(printf '%s' "$out" | grep -q 'jq is required' && echo 0 || echo 1)" \
  "got: $out"
check_rc "...and does not blame a valid settings.json" \
  "$(printf '%s' "$out" | grep -q 'not a JSON object' && echo 1 || echo 0)" \
  "got: $out"
check_rc "...and names a way to install it" \
  "$(printf '%s' "$out" | grep -q 'apt-get install jq' && echo 0 || echo 1)" \
  "got: $out"

# doctor is the tool a stuck user is pointed at, and it used to answer `ok jq `
# — a blank version — on a machine with none. The preflight now stops it before
# it can say anything, which is the better answer: the same actionable line
# every other subcommand gives. What must never come back is the false ok.
out="$(run_nojq "$HCTL" doctor --scope user)"
check_rc "doctor without jq refuses rather than reporting" \
  "$(printf '%s' "$out" | grep -q 'jq is required' && echo 0 || echo 1)" \
  "got: $out"
check_rc "...and never claims jq is ok with a blank version" \
  "$(printf '%s' "$out" | grep -qE 'ok +jq *$' && echo 1 || echo 0)" \
  "got: $out"

HLOG="$HARNESS/plugins/harness-core/bin/harness-log"
out="$(run_nojq "$HLOG")"
check_rc "harness-log without jq says so" \
  "$(printf '%s' "$out" | grep -q 'jq is required' && echo 0 || echo 1)" \
  "got: $out"

# Structural, and it is the half verify_begin cannot do: it runs per hook, so it
# can never assert about _verify-lib.sh itself, about the two executables, or
# about the repo-only scripts that source the wrapper through _check-lib.sh.
# Globbed rather than listed, so a new file cannot arrive outside the check.
#
# Anchored to the start of a statement, the way verify-frontmatter's selftest
# had to be. A guard is `command -v jq >/dev/null` opening a line or following
# `if !`; a mention of the broken spelling inside a comment or a grep pattern is
# not, and both exist in this repository — including on the line just below,
# which is why an unanchored first draft reported this file and harnessctl as
# offenders on the strength of their own explanations.
offenders=""
for f in "$HARNESS"/plugins/harness-core/hooks/*.sh \
         "$HARNESS"/plugins/harness-core/bin/* \
         "$HARNESS"/plugins/harness-core/scripts/*.sh \
         "$HARNESS"/scripts/*.sh; do
  [ -f "$f" ] || continue
  { grep -q '^jq() { local rc; command jq' "$f" \
    || grep -q '_check-lib\.sh\|_verify-lib\.sh' "$f"; } || continue
  grep -q '^[[:space:]]*\(if ! \)\?command -v jq >/dev/null' "$f" \
    && offenders="$offenders ${f#"$HARNESS"/}"
done
check_rc "no file defining the jq wrapper resolves jq with command -v" \
  "$([ -z "$offenders" ] && echo 0 || echo 1)" \
  "offenders:$offenders"

# And the wrapper is what makes that necessary, so pin that it is still there —
# otherwise the check above passes by the wrapper quietly disappearing.
wrapped=0
for f in "$HARNESS"/plugins/harness-core/hooks/*.sh \
         "$HARNESS"/plugins/harness-core/bin/* \
         "$HARNESS"/plugins/harness-core/scripts/_verify-lib.sh; do
  [ -f "$f" ] && grep -q '^jq() { local rc; command jq' "$f" && wrapped=$((wrapped + 1))
done
check_eq "the CR-stripping wrapper is still in all eight" 8 "$wrapped"

# --- summary -----------------------------------------------------------------
summary
exit $?

#!/bin/bash
# Exercise the Codex install boundary, ownership and consumer-data preservation.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/_verify-lib.sh"
verify_begin harness-codex bin/harness-codex
CORE_ROOT="$(cd "$(dirname "$HOOK")/.." && pwd)"
SOURCE_ROOT="$WORK/source"
mkdir -p "$SOURCE_ROOT/plugins"
cp -R "$CORE_ROOT" "$SOURCE_ROOT/plugins/harness-core"
# Fixture modules keep this shipped verifier independent of sibling plugin caches.
for profile in dev research slides; do
  mkdir -p "$SOURCE_ROOT/plugins/harness-$profile/.claude-plugin"
  printf '{"name":"harness-%s","version":"1.0.0"}\n' "$profile" > "$SOURCE_ROOT/plugins/harness-$profile/.claude-plugin/plugin.json"
  printf 'Fixture attribution\n' > "$SOURCE_ROOT/plugins/harness-$profile/NOTICE.md"
  case "$profile" in
    dev) names='engineering project-verification pr-review cross-model-review ecosystem-review' ;;
    research) names='research-notes repro-checklist' ;;
    slides) names='results-deck manuscript-audit' ;;
  esac
  for name in $names; do
    mkdir -p "$SOURCE_ROOT/plugins/harness-$profile/skills/$name"
    printf -- '---\nname: %s\ndescription: "Fixture workflow"\n---\n\nFixture body.\n' "$name" > "$SOURCE_ROOT/plugins/harness-$profile/skills/$name/SKILL.md"
  done
done
mkdir -p "$SOURCE_ROOT/plugins/harness-dev/skills/engineering/references"
printf 'Fixture delivery reference\n' > "$SOURCE_ROOT/plugins/harness-dev/skills/engineering/references/delivery.md"
RUN_BASH="${BASH:-/bin/bash}"
PROJ="$WORK/project with spaces & symbols"
mkdir -p "$PROJ/.agents/skills/consumer-owned" "$PROJ/.codex" "$PROJ/.claude"
git -C "$PROJ" init --quiet
printf 'consumer instructions without trailing newline' > "$PROJ/AGENTS.md"
cp "$PROJ/AGENTS.md" "$WORK/original-agents"
printf '[consumer]\nvalue = "keep"\n' > "$PROJ/.codex/config.toml"
printf '{"consumer":true}\n' > "$PROJ/.claude/settings.json"
printf 'consumer skill\n' > "$PROJ/.agents/skills/consumer-owned/SKILL.md"
ROOT="$PROJ/.agents/agent-harness"
invoke() {
  ( cd "$PROJ" && "$RUN_BASH" "$HOOK" "$@" ) > "$WORK/out" 2> "$WORK/err"
  RC=$?
}
check_file() { if [ -f "$1" ]; then _pass "$2"; else _fail "$2" "missing $1"; fi; }
absent() { if [ ! -e "$1" ] && [ ! -L "$1" ]; then _pass "$2"; else _fail "$2" "still exists: $1"; fi; }

invoke init --source "$SOURCE_ROOT" --dry-run
expect 'dry-run succeeds' 0 "$RC"
absent "$ROOT" 'dry-run does not create managed state'
cmp -s "$PROJ/AGENTS.md" "$WORK/original-agents"; expect 'dry-run preserves exact consumer instruction bytes' 0 "$?"
invoke init --source "$SOURCE_ROOT"
expect 'default project install succeeds under selected bash' 0 "$RC"
check_file "$ROOT/manifest.json" 'records an install receipt'
expect 'default installs core plus all dev skills' 6 "$(jq '.links|length' "$ROOT/manifest.json")"
for name in pr-create engineering project-verification pr-review cross-model-review ecosystem-review; do
  check_file "$PROJ/.agents/skills/$name/SKILL.md" "Codex discovery reaches $name"
done
cmp -s "$PROJ/.agents/skills/engineering/SKILL.md" "$SOURCE_ROOT/plugins/harness-dev/skills/engineering/SKILL.md"
expect 'installed skill is byte-identical to the shared source' 0 "$?"
cmp -s "$PROJ/.agents/skills/engineering/references/delivery.md" "$SOURCE_ROOT/plugins/harness-dev/skills/engineering/references/delivery.md"
expect 'references survive outside the source tree' 0 "$?"
check_file "$PROJ/.agents/skills/engineering/../../NOTICE.md" 'relative third-party notice resolves'
check_file "$ROOT/rules/dev/review.md" 'installs the shared development checklist'
expect_match 'default instructions include the pstack implementation checkpoints' "$(cat "$PROJ/AGENTS.md")" 'test that premise'
expect_match 'Codex instructions resolve the runtime rule location' "$(cat "$PROJ/AGENTS.md")" '.agents/agent-harness/rules/'
expect_absent 'native permission config is unchanged' "$(cat "$PROJ/.codex/config.toml")" 'agent-harness'
expect 'Claude settings are untouched' '{"consumer":true}' "$(cat "$PROJ/.claude/settings.json")"
expect 'foreign skills survive' 'consumer skill' "$(cat "$PROJ/.agents/skills/consumer-owned/SKILL.md")"
invoke doctor
expect 'doctor verifies the actual installed files' 0 "$RC"
RELOC="$WORK/relocated-project"
cp -R "$PROJ" "$RELOC"
( cd "$RELOC" && "$RUN_BASH" "$HOOK" doctor ) > "$WORK/relocated-out" 2>&1
expect 'a relocated project retains its receipt and live skill links' 0 "$?"
check_file "$RELOC/.agents/skills/engineering/references/delivery.md" 'relative skill links remain usable after relocation'
( cd "$RELOC" && "$RUN_BASH" "$HOOK" uninstall ) > "$WORK/relocated-out" 2>&1
expect 'a relocated project can be uninstalled independently' 0 "$?"
check_file "$ROOT/manifest.json" 'relocated removal leaves the original install intact'

cp "$PROJ/AGENTS.md" "$WORK/installed-agents"
invoke init --source "$SOURCE_ROOT"
expect 'reinstall succeeds' 0 "$RC"
cmp -s "$PROJ/AGENTS.md" "$WORK/installed-agents"; expect 'reinstall does not duplicate or reformat the instruction block' 0 "$?"
printf '\nconsumer addition after install\n' >> "$PROJ/AGENTS.md"
invoke init --source "$SOURCE_ROOT" --with research --with slides
expect 'profile refresh succeeds' 0 "$RC"
check_file "$PROJ/.agents/skills/research-notes/SKILL.md" 'requested research skill is discoverable'
check_file "$PROJ/.agents/skills/manuscript-audit/SKILL.md" 'requested manuscript skill is discoverable'
absent "$PROJ/.agents/skills/engineering" 'dropped dev profile removes only its owned links'
expect_match 'refresh retains later consumer instructions' "$(cat "$PROJ/AGENTS.md")" 'consumer addition after install'
invoke uninstall --dry-run
expect 'uninstall dry-run succeeds' 0 "$RC"
check_file "$ROOT/manifest.json" 'uninstall dry-run keeps the receipt'
invoke uninstall
expect 'uninstall succeeds' 0 "$RC"
absent "$ROOT" 'uninstall removes owned payload and receipt'
absent "$PROJ/.agents/skills/research-notes" 'uninstall removes its skill links'
printf 'consumer instructions without trailing newline\nconsumer addition after install\n' > "$WORK/expected-agents"
cmp -s "$PROJ/AGENTS.md" "$WORK/expected-agents"; expect 'uninstall preserves original bytes and later edits' 0 "$?"
check_file "$PROJ/.agents/skills/consumer-owned/SKILL.md" 'uninstall retains the consumer skill'
invoke uninstall
expect 'repeated uninstall is a no-op' 0 "$RC"

mkdir -p "$PROJ/.agents/skills/engineering"
printf 'existing engineering\n' > "$PROJ/.agents/skills/engineering/SKILL.md"
cp "$PROJ/AGENTS.md" "$WORK/before-conflict"
invoke init --source "$SOURCE_ROOT"
if [ "$RC" -ne 0 ]; then _pass 'conflicting user skill blocks install'; else _fail 'conflicting user skill blocks install' ''; fi
absent "$ROOT" 'conflict fails before creating managed state'
cmp -s "$PROJ/AGENTS.md" "$WORK/before-conflict"; expect 'conflict leaves consumer instructions untouched' 0 "$?"
expect 'conflicting skill is retained' 'existing engineering' "$(cat "$PROJ/.agents/skills/engineering/SKILL.md")"
rm -rf "$PROJ/.agents/skills/engineering"

invoke init --source "$SOURCE_ROOT"
expect 'install works after the conflict is resolved' 0 "$RC"
printf '\nconsumer edit\n' >> "$ROOT/payload/plugins/harness-dev/skills/engineering/SKILL.md"
invoke uninstall
if [ "$RC" -ne 0 ]; then _pass 'edited installed skill blocks removal'; else _fail 'edited installed skill blocks removal' ''; fi
check_file "$ROOT/manifest.json" 'edited payload retains its receipt'
invoke init --source "$SOURCE_ROOT"
if [ "$RC" -ne 0 ]; then _pass 'edited installed skill blocks overwrite'; else _fail 'edited installed skill blocks overwrite' ''; fi
cp "$SOURCE_ROOT/plugins/harness-dev/skills/engineering/SKILL.md" "$ROOT/payload/plugins/harness-dev/skills/engineering/SKILL.md"
printf 'foreign note\n' > "$ROOT/keep-me.txt"
invoke uninstall
if [ "$RC" -ne 0 ]; then _pass 'foreign files inside managed state are preserved'; else _fail 'foreign files inside managed state are preserved' ''; fi
rm "$ROOT/keep-me.txt"
cp "$PROJ/AGENTS.md" "$WORK/intact-block"
sed 's/test that premise/edited premise/' "$WORK/intact-block" > "$PROJ/AGENTS.md"
invoke uninstall
if [ "$RC" -ne 0 ]; then _pass 'edited managed instruction block is refused'; else _fail 'edited managed instruction block is refused' ''; fi
cp "$WORK/intact-block" "$PROJ/AGENTS.md"
invoke uninstall
expect 'intact installation can still be removed' 0 "$RC"

rm "$PROJ/AGENTS.md"
invoke init --source "$SOURCE_ROOT" --with ''
expect 'explicit empty profiles installs only core' 0 "$RC"
expect 'core-only has one shared skill' 1 "$(jq '.links|length' "$ROOT/manifest.json")"
invoke uninstall
expect 'core-only uninstall succeeds' 0 "$RC"
absent "$PROJ/AGENTS.md" 'uninstall removes an instruction file it created when no user text remains'
printf '사용자 지침\r\nkeep CRLF\r\n' > "$PROJ/AGENTS.md"
cp "$PROJ/AGENTS.md" "$WORK/crlf-original"
invoke init --source "$SOURCE_ROOT"
expect 'consumer CRLF instructions can be extended' 0 "$RC"
invoke init --source "$SOURCE_ROOT"
expect 'CRLF instruction refresh succeeds' 0 "$RC"
invoke uninstall
expect 'CRLF instruction removal succeeds' 0 "$RC"
cmp -s "$PROJ/AGENTS.md" "$WORK/crlf-original"; expect 'uninstall retains Unicode and original CRLF bytes' 0 "$?"
invoke init --source "$SOURCE_ROOT" --with python
if [ "$RC" -ne 0 ]; then _pass 'unsupported workflow profile is rejected'; else _fail 'unsupported workflow profile is rejected' ''; fi
absent "$ROOT" 'invalid profile writes no managed state'
invoke init --source "$SOURCE_ROOT" --scope local
if [ "$RC" -ne 0 ]; then _pass 'invalid scope is rejected'; else _fail 'invalid scope is rejected' ''; fi

cp "$PROJ/AGENTS.md" "$WORK/before-budget"
awk 'BEGIN{for(i=0;i<40000;i++)printf "x"}' > "$PROJ/AGENTS.md"
cp "$PROJ/AGENTS.md" "$WORK/large-agents"
invoke init --source "$SOURCE_ROOT"
if [ "$RC" -ne 0 ]; then _pass 'oversized instructions fail before silent loader truncation'; else _fail 'oversized instructions fail before silent loader truncation' ''; fi
cmp -s "$PROJ/AGENTS.md" "$WORK/large-agents"; expect 'budget refusal preserves consumer content' 0 "$?"
absent "$ROOT" 'budget refusal creates no managed state'
cp "$WORK/before-budget" "$PROJ/AGENTS.md"

USER_HOME="$WORK/consumer-home"
USER_CFG="$WORK/custom-codex-config"
mkdir -p "$USER_HOME/.agents/skills/foreign" "$USER_CFG"
printf 'user-owned instructions\n' > "$USER_CFG/AGENTS.md"
cp "$USER_CFG/AGENTS.md" "$WORK/user-original"
printf '[consumer]\nvalue = "retained"\n' > "$USER_CFG/config.toml"
printf 'foreign skill\n' > "$USER_HOME/.agents/skills/foreign/SKILL.md"
user_invoke() {
  env -i PATH="$PATH_SAVE" HOME="$USER_HOME" CODEX_HOME="$USER_CFG" "$RUN_BASH" "$HOOK" "$@" --scope user > "$WORK/user-out" 2> "$WORK/user-err"
  RC=$?
}
user_invoke init --source "$SOURCE_ROOT"
expect 'user-scope installation honors a custom Codex config directory' 0 "$RC"
check_file "$USER_HOME/.agents/skills/engineering/SKILL.md" 'user discovery stays in the documented user skills directory'
check_file "$USER_CFG/agent-harness/manifest.json" 'user receipt is stored with the selected Codex configuration'
expect 'native Codex settings remain unchanged' '[consumer]
value = "retained"' "$(cat "$USER_CFG/config.toml")"
user_invoke doctor
expect 'user installation passes doctor' 0 "$RC"
user_invoke uninstall
expect 'user installation can be removed' 0 "$RC"
cmp -s "$USER_CFG/AGENTS.md" "$WORK/user-original"; expect 'user uninstall restores the existing instruction bytes' 0 "$?"
check_file "$USER_HOME/.agents/skills/foreign/SKILL.md" 'user uninstall preserves foreign skills'
absent "$USER_HOME/.agents/skills/engineering" 'user uninstall removes its discovery link'

printf 'Consumer override
' > "$PROJ/AGENTS.override.md"
invoke init --source "$SOURCE_ROOT"
if [ "$RC" -ne 0 ]; then _pass 'an instruction override that masks AGENTS.md blocks installation'; else _fail 'an instruction override that masks AGENTS.md blocks installation' ''; fi
absent "$ROOT" 'a masked instruction file creates no managed state'
expect 'the consumer override is retained' 'Consumer override' "$(cat "$PROJ/AGENTS.override.md")"
rm "$PROJ/AGENTS.override.md"

# Fail destination writes after the previous payload has moved, then verify recovery.
invoke init --source "$SOURCE_ROOT"
expect 'rollback fixture installs' 0 "$RC"
cp "$PROJ/AGENTS.md" "$WORK/before-rollback"
cp "$ROOT/manifest.json" "$WORK/before-receipt"
FAIL_BIN="$WORK/failing-bin"
mkdir "$FAIL_BIN"
REAL_MV="$(type -P mv)"
cat > "$FAIL_BIN/mv" <<'S'
#!/bin/bash
for arg in "$@"; do
  case "$arg" in */agents-next) exit 73 ;; esac
done
exec "$REAL_MV" "$@"
S
chmod +x "$FAIL_BIN/mv"
( cd "$PROJ" && PATH="$FAIL_BIN:$PATH_SAVE" REAL_MV="$REAL_MV" "$RUN_BASH" "$HOOK" init --source "$SOURCE_ROOT" --with research ) > "$WORK/fail-out" 2>&1
if [ "$?" -ne 0 ]; then _pass 'a failed update reports failure'; else _fail 'a failed update reports failure' ''; fi
cmp -s "$PROJ/AGENTS.md" "$WORK/before-rollback"; expect 'failed update retains exact instruction bytes' 0 "$?"
cmp -s "$ROOT/manifest.json" "$WORK/before-receipt"; expect 'failed update restores the previous payload receipt' 0 "$?"
invoke doctor
expect 'failed update leaves the previous install fully usable' 0 "$RC"
( cd "$PROJ" && PATH="$FAIL_BIN:$PATH_SAVE" REAL_MV="$REAL_MV" "$RUN_BASH" "$HOOK" uninstall ) > "$WORK/fail-out" 2>&1
if [ "$?" -ne 0 ]; then _pass 'a failed removal reports failure'; else _fail 'a failed removal reports failure' ''; fi
invoke doctor
expect 'failed removal restores all managed files and links' 0 "$RC"
cmp -s "$PROJ/AGENTS.md" "$WORK/before-rollback"; expect 'failed removal retains exact instruction bytes' 0 "$?"
cat > "$FAIL_BIN/ln" <<'S'
#!/bin/bash
# Git Bash can report success while creating a copied directory.
mkdir "$3"
S
chmod +x "$FAIL_BIN/ln"
( cd "$PROJ" && PATH="$FAIL_BIN:$PATH_SAVE" REAL_MV="$REAL_MV" "$RUN_BASH" "$HOOK" init --source "$SOURCE_ROOT" ) > "$WORK/fail-out" 2>&1
if [ "$?" -ne 0 ]; then _pass 'a symlink command that silently copies is refused'; else _fail 'a symlink command that silently copies is refused' ''; fi
invoke doctor
expect 'unsupported symlinks leave the previous install usable' 0 "$RC"
cmp -s "$PROJ/AGENTS.md" "$WORK/before-rollback"; expect 'unsupported symlinks preserve instruction bytes' 0 "$?"
rm "$FAIL_BIN/ln"
# On elevated test runners -w can remain true despite chmod; injected failures above still exercise rollback.
chmod a-w "$PROJ/AGENTS.md"
if [ ! -w "$PROJ/AGENTS.md" ]; then
  invoke uninstall
  if [ "$RC" -ne 0 ]; then _pass 'read-only instructions refuse removal before mutation'; else _fail 'read-only instructions refuse removal before mutation' ''; fi
else
  expect 'read-only fixture is covered by injected write denial when elevated' 1 1
fi
chmod u+w "$PROJ/AGENTS.md"
invoke doctor
expect 'write denial leaves the install complete' 0 "$RC"
invoke uninstall
expect 'the recovered install can be removed' 0 "$RC"
env -i PATH="$PATH_SAVE" HOME="$USER_HOME" CODEX_HOME=relative "$RUN_BASH" "$HOOK" init --source "$SOURCE_ROOT" --scope user > "$WORK/user-out" 2>&1
if [ "$?" -ne 0 ]; then _pass 'relative Codex configuration roots are rejected'; else _fail 'relative Codex configuration roots are rejected' ''; fi
absent "$USER_HOME/.agents/skills/engineering" 'invalid user roots leave discovery untouched'

verify_summary

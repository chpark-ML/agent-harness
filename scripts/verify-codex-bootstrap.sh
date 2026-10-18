#!/bin/bash
# Exercise the public --agent routes. Claude's network boundary is a logged stub;
# the Codex installer, local Git fetch and consumer files are real.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/scripts/_check-lib.sh"
WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT
RUN_BASH="${BASH:-/bin/bash}"
PROJ="$WORK/consumer"
mkdir -p "$PROJ/.codex" "$PROJ/.agents/skills/foreign" "$WORK/home" "$WORK/bin"
git -C "$PROJ" init --quiet
printf 'Consumer instructions\n' > "$PROJ/AGENTS.md"
cp "$PROJ/AGENTS.md" "$WORK/original"
printf '# native settings retained\n' > "$PROJ/.codex/config.toml"
printf 'foreign\n' > "$PROJ/.agents/skills/foreign/SKILL.md"
cat > "$WORK/bin/claude" <<'S'
#!/bin/sh
printf '%s\n' "$*" >> "$CLAUDE_CALLS"
[ "$ALLOW_CLAUDE" = 1 ] || exit 97
case "$*" in 'plugin list --json') printf '[]\n' ;; esac
exit 0
S
chmod +x "$WORK/bin/claude"
ALLOW=0
invoke() {
  local script="$1"; shift
  ( cd "$PROJ" && env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" \
    CLAUDE_CONFIG_DIR="$WORK/claude" BIN_DIR="$WORK/shims" \
    CLAUDE_CALLS="$WORK/claude-calls" ALLOW_CLAUDE="$ALLOW" SHELL=/bin/bash \
    "$RUN_BASH" "$REPO/$script" "$@" ) > "$WORK/out" 2>&1
  RC=$?
}
ROOT="$PROJ/.agents/agent-harness"
echo '=== Codex bootstrap verification ==='
invoke install.sh --agent codex --scope project
check_rc 'Codex-only bootstrap installs without invoking Claude' "$RC" "$(tail -3 "$WORK/out")"
check_rc 'Codex-only route never calls the Claude CLI' "$([ ! -e "$WORK/claude-calls" ]; echo $?)"
check_rc 'default Codex bootstrap delivers the engineering skill' "$([ -f "$PROJ/.agents/skills/engineering/SKILL.md" ]; echo $?)"
check_eq 'Codex bootstrap leaves native settings intact' '# native settings retained' "$(cat "$PROJ/.codex/config.toml")"
invoke uninstall.sh --agent codex --scope project --dry-run
check_rc 'Codex removal preview succeeds' "$RC"
check_rc 'preview retains the installed receipt' "$([ -f "$ROOT/manifest.json" ]; echo $?)"
invoke uninstall.sh --agent codex --scope project
check_rc 'Codex-only bootstrap removal succeeds' "$RC"
cmp -s "$PROJ/AGENTS.md" "$WORK/original"; check_rc 'removal restores exact consumer instructions' "$?"
check_rc 'removal retains foreign skills' "$([ -f "$PROJ/.agents/skills/foreign/SKILL.md" ]; echo $?)"
check_rc 'Codex-only removal never calls Claude' "$([ ! -e "$WORK/claude-calls" ]; echo $?)"
for arg in '--agent=unknown' '--agent' '--profile=python' '--with-tools'; do
  invoke install.sh --agent codex --scope project "$arg"
  check_rc "invalid Codex option $arg fails before installation" "$([ "$RC" -ne 0 ] && [ ! -e "$ROOT" ]; echo $?)"
done

# Exercise --ref with the real Git fetch path and an owned local source remote.
# URL rewriting exists only in this child environment; no Git config is edited.
SNAPSHOT="$WORK/pinned-source"
mkdir -p "$SNAPSHOT/plugins"
cp -R "$REPO/plugins/harness-core" "$SNAPSHOT/plugins/"
jq '.version="9.8.7"' "$SNAPSHOT/plugins/harness-core/.claude-plugin/plugin.json" > "$WORK/pinned-manifest"
mv "$WORK/pinned-manifest" "$SNAPSHOT/plugins/harness-core/.claude-plugin/plugin.json"
git -C "$SNAPSHOT" init --quiet
git -C "$SNAPSHOT" checkout --quiet -b fixture-pin
git -C "$SNAPSHOT" add plugins
git -C "$SNAPSHOT" -c core.hooksPath=/dev/null -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit --quiet -m 'Pin owned source fixture'
cp "$REPO/install.sh" "$WORK/bootstrap.sh"
( cd "$PROJ" && env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" \
  CLAUDE_CALLS="$WORK/claude-calls" ALLOW_CLAUDE=0 BIN_DIR="$WORK/shims" \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$SNAPSHOT.insteadOf" \
  GIT_CONFIG_VALUE_0=https://github.com/chpark-ML/agent-harness.git \
  "$RUN_BASH" "$WORK/bootstrap.sh" --agent codex --scope project --profile core --ref fixture-pin ) > "$WORK/out" 2>&1
check_rc 'standalone bootstrap fetches the requested ref with real Git' "$?" "$(tail -3 "$WORK/out")"
check_eq 'the fetched snapshot supplies its own version' 9.8.7 "$(jq -r '.versions.core' "$ROOT/manifest.json" 2>/dev/null)"
invoke uninstall.sh --agent codex --scope project
check_rc 'a fetched self-contained installation can be removed' "$RC"

ALLOW=1
mkdir -p "$WORK/claude/plugins/cache/agent-harness/harness-core/9.9.9/bin"
: > "$WORK/claude/plugins/cache/agent-harness/harness-core/9.9.9/.in_use"
printf '#!/bin/sh\nexit 0\n' > "$WORK/claude/plugins/cache/agent-harness/harness-core/9.9.9/bin/harnessctl"
invoke install.sh --agent both --scope project
check_rc 'both route reaches the actual Codex installer after the Claude boundary' "$RC" "$(tail -3 "$WORK/out")"
check_rc 'both route calls the Claude plugin installer' "$(grep -qx 'plugin install harness-dev@agent-harness --scope project' "$WORK/claude-calls"; echo $?)" "$(cat "$WORK/claude-calls" 2>/dev/null)"
check_rc 'both route also installs Codex skill files' "$([ -f "$PROJ/.agents/skills/engineering/SKILL.md" ]; echo $?)"
# A Codex ownership conflict must stop combined removal before its Claude phase.
printf '\nconsumer edit\n' >> "$ROOT/payload/plugins/harness-dev/skills/engineering/SKILL.md"
cp "$WORK/claude-calls" "$WORK/calls-before"
invoke uninstall.sh --agent both --scope project
check_rc 'combined removal stops on a Codex ownership conflict' "$([ "$RC" -ne 0 ]; echo $?)"
cmp -s "$WORK/claude-calls" "$WORK/calls-before"; check_rc 'a Codex removal failure never starts Claude removal' "$?" "$(tail -5 "$WORK/claude-calls")"
cp "$REPO/plugins/harness-dev/skills/engineering/SKILL.md" "$ROOT/payload/plugins/harness-dev/skills/engineering/SKILL.md"
invoke uninstall.sh --agent both --scope project
check_rc 'combined removal succeeds after resolving the conflict' "$RC" "$(tail -3 "$WORK/out")"
cmp -s "$PROJ/AGENTS.md" "$WORK/original"; check_rc 'combined removal retains consumer instructions' "$?"
summary
exit $?

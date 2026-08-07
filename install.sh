#!/usr/bin/env bash
# agent-harness — one command, complete install.
#
#   ./install.sh                                  # core, user scope
#   ./install.sh --profile dev,python             # profiles compose
#   ./install.sh --profile dev --scope project    # this repo only
#   ./install.sh --profile python --with-tools    # also install the language server
#
# The harness ships in two halves and this runs both. The plugin half
# (`claude plugin install`) carries hooks, skills, commands and verifiers. The
# declarative half (`harnessctl init`) writes permissions, CLAUDE.md and rules,
# because a plugin cannot carry those: a plugin's settings.json supports only
# the `agent` and `subagentStatusLine` keys, a plugin-root CLAUDE.md is not
# loaded as context, and rules are not a plugin component.
#
# harnessctl normally reaches you through the plugin's bin/ on the Bash tool's
# PATH, which only happens in a session started after the plugin is enabled.
# This script does not wait for that — it locates harnessctl in the plugin
# directory and runs it directly, so the install finishes here rather than
# leaving you a second step to remember.
#
# Requires bash 3.2 and a Claude Code with plugin support. jq comes in through
# harnessctl's own preflight.
set -uo pipefail

MARKETPLACE_REPO="chpark-ML/agent-harness"
MARKETPLACE_NAME="agent-harness"
PROFILES="core"
SCOPE="user"
REF=""
WITH_TOOLS=0

say()  { printf '==> %s\n' "$*"; }
warn() { printf '!   %s\n' "$*" >&2; }
die()  { printf '!   %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

  --profile <list>   comma-separated: core, dev, research, python, typescript
  --scope <s>        user (default) or project
  --with-tools       npm install the language servers the LSP plugins need
  --ref <ref>        pin the marketplace to a git tag or branch
  -h, --help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)    shift; [ $# -gt 0 ] || die "--profile 값이 필요합니다"; PROFILES="$1" ;;
    --profile=*)  PROFILES="${1#--profile=}" ;;
    --scope)      shift; [ $# -gt 0 ] || die "--scope 값이 필요합니다"; SCOPE="$1" ;;
    --scope=*)    SCOPE="${1#--scope=}" ;;
    --with-tools) WITH_TOOLS=1 ;;
    --ref)        shift; [ $# -gt 0 ] || die "--ref 값이 필요합니다"; REF="$1" ;;
    --ref=*)      REF="${1#--ref=}" ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "알 수 없는 인자: $1  (--help 참조)" ;;
  esac
  shift
done

case "$SCOPE" in user|project) ;; *) die "--scope 는 user 또는 project 입니다 (받은 값: $SCOPE)" ;; esac

PROFILE_LIST="$(printf '%s' "$PROFILES" | tr ',' ' ' | tr -s ' ')"
for p in $PROFILE_LIST; do
  case "$p" in core|dev|research|python|typescript) ;; *) die "알 수 없는 profile: $p" ;; esac
done

# Only dev and research carry declarative rules; the language profiles are
# dependency bundles with nothing for harnessctl to install.
WITH=""
for p in $PROFILE_LIST; do
  case "$p" in dev|research) WITH="${WITH:+$WITH,}$p" ;; esac
done

command -v claude >/dev/null 2>&1 || die "Claude Code 가 PATH 에 없습니다."
claude plugin --help >/dev/null 2>&1 || die "이 Claude Code 버전은 플러그인을 지원하지 않습니다. 'claude update' 후 다시 실행하세요."
[ "$SCOPE" = project ] && [ ! -e "$PWD/.git" ] && die "--scope project 는 git 저장소 루트에서 실행해야 합니다."

# ---- 1. marketplace -----------------------------------------------------------
SOURCE="$MARKETPLACE_REPO"
[ -n "$REF" ] && SOURCE="$MARKETPLACE_REPO@$REF"
say "marketplace: $SOURCE"
if claude plugin marketplace list 2>/dev/null | grep -q "$MARKETPLACE_NAME"; then
  claude plugin marketplace update "$MARKETPLACE_NAME" >/dev/null 2>&1 \
    && say "  이미 등록됨 — 최신으로 갱신" || warn "  갱신 실패, 기존 캐시로 계속"
else
  claude plugin marketplace add "$SOURCE" >/dev/null || die "marketplace 등록 실패"
  say "  등록 완료"
fi

# ---- 2. plugins ---------------------------------------------------------------
for p in $PROFILE_LIST; do
  say "플러그인: harness-$p (scope: $SCOPE)"
  out="$(claude plugin install "harness-$p@$MARKETPLACE_NAME" --scope "$SCOPE" 2>&1)"
  if [ $? -ne 0 ]; then printf '%s\n' "$out" >&2; die "harness-$p 설치 실패"; fi
  printf '%s\n' "$out" | sed 's/^/    /' | tail -2
done

# ---- 3. locate harnessctl -----------------------------------------------------
# The install cache is versioned (<cache>/<marketplace>/<plugin>/<version>/) and
# marks the live copy with .in_use. Prefer that; fall back to the marketplace
# clone, then to this checkout, so the script also works before a first install.
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HCTL=""
# The cache is one directory per version. Glob order is lexicographic, which
# would rank 0.9.0 above 0.10.0, so sort by version when the tools allow it.
# The exec bit is not required: the invocation below is `bash "$HCTL"`.
_cands=""
for d in "$CFG/plugins/cache/$MARKETPLACE_NAME/harness-core"/*/; do
  [ -f "$d/.in_use" ] || continue
  [ -f "$d/.orphaned_at" ] && continue
  [ -f "$d/bin/harnessctl" ] || continue
  _cands="$_cands$d
"
done
if [ -n "$_cands" ]; then
  if printf 'x' | sort -V >/dev/null 2>&1; then
    HCTL="$(printf '%s' "$_cands" | grep -v '^$' | sort -V | tail -1)bin/harnessctl"
  else
    HCTL="$(printf '%s' "$_cands" | grep -v '^$' | tail -1)bin/harnessctl"
  fi
fi
[ -n "$HCTL" ] || HCTL="$(ls "$CFG/plugins/marketplaces/$MARKETPLACE_NAME/plugins/harness-core/bin/harnessctl" 2>/dev/null | head -1)"
if [ -z "$HCTL" ]; then
  SELF="${BASH_SOURCE[0]:-}"
  [ -n "$SELF" ] && [ -f "$SELF" ] && \
    HCTL="$(cd "$(dirname "$SELF")" && pwd)/plugins/harness-core/bin/harnessctl"
fi
[ -n "$HCTL" ] && [ -f "$HCTL" ] || die "harnessctl 을 찾을 수 없습니다. 새 Claude Code 세션에서 'harnessctl init --scope $SCOPE' 를 직접 실행하세요."

# ---- 4. declarative half ------------------------------------------------------
say "harnessctl init (scope: $SCOPE${WITH:+, modules: $WITH})"
bash "$HCTL" init --scope "$SCOPE" ${WITH:+--with "$WITH"} 2>&1 | sed 's/^/    /' \
  || die "harnessctl init 실패"

# ---- 5. language servers ------------------------------------------------------
# The LSP plugins do not bundle their server binary. Installing one is a global
# npm change, so it stays opt-in; doctor reports it either way.
install_tool() {
  local bin="$1" pkgs="$2"
  command -v "$bin" >/dev/null 2>&1 && return 0
  if [ "$WITH_TOOLS" -eq 0 ]; then return 0; fi
  command -v npm >/dev/null 2>&1 || { warn "npm 이 없어 $bin 을 설치할 수 없습니다"; return 0; }
  say "언어 서버 설치: $pkgs"
  # shellcheck disable=SC2086
  npm install -g $pkgs >/dev/null 2>&1 && say "  완료" || warn "  설치 실패 — 수동: npm install -g $pkgs"
}
for p in $PROFILE_LIST; do
  case "$p" in
    python)     install_tool pyright-langserver "pyright" ;;
    typescript) install_tool typescript-language-server "typescript-language-server typescript" ;;
  esac
done

# ---- 5b. shim for the user's own shell -----------------------------------------
# The plugin's bin/ lands on the PATH of Claude Code's *Bash tool*, not on the
# PATH of the terminal the user is sitting in. Typing `harnessctl` in zsh finds
# nothing, which reads as a broken install.
#
# A symlink would not survive either: the plugin cache is versioned
# (.../harness-core/1.6.0/bin/harnessctl) and every `claude plugin update`
# creates a new directory, so anything pinned to today's path breaks tomorrow.
# So this writes a shim that resolves the newest version at run time. It is a
# plain executable, which means it works the same in zsh, bash and fish.
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
say "shell shim"
if mkdir -p "$BIN_DIR" 2>/dev/null; then
  cat > "$BIN_DIR/harnessctl" <<'SHIM'
#!/bin/sh
# harnessctl shim — resolves the installed plugin at run time.
# Installed by agent-harness/install.sh. Safe to delete; re-created on install.
d=$(ls -d "$HOME"/.claude/plugins/cache/*/harness-core/*/bin 2>/dev/null | sort -V | tail -1)
[ -n "$d" ] || { echo "harnessctl: harness-core plugin not found. Install it first:" >&2
                 echo "  claude plugin install harness-core@agent-harness --scope user" >&2; exit 1; }
exec "$d/harnessctl" "$@"
SHIM
  chmod +x "$BIN_DIR/harnessctl"
  say "  $BIN_DIR/harnessctl"
  case ":$PATH:" in
    *":$BIN_DIR:"*) say "  PATH 에 이미 있습니다" ;;
    *)
      # Name the file for the shell the user actually runs, not for bash.
      case "${SHELL##*/}" in
        zsh)  rc="~/.zshrc" ;;
        fish) rc="~/.config/fish/config.fish" ;;
        *)    rc="~/.bashrc (또는 ~/.bash_profile)" ;;
      esac
      warn "  $BIN_DIR 가 PATH 에 없습니다. $rc 에 추가하세요:"
      if [ "${SHELL##*/}" = fish ]; then
        say "    fish_add_path $BIN_DIR"
      else
        say "    export PATH=\"$BIN_DIR:\$PATH\""
      fi
      ;;
  esac
else
  warn "  $BIN_DIR 를 만들 수 없어 건너뜁니다 — 플러그인 경로로 직접 부르세요."
fi
echo

# ---- 6. doctor ----------------------------------------------------------------
say "harnessctl doctor"
bash "$HCTL" doctor --scope "$SCOPE" 2>&1 | sed 's/^/    /'
rc=$?

cat <<EOF

설치 완료 — 두 절반이 모두 들어갔습니다.

  플러그인   훅 · 스킬 · 커맨드 · 검증기
  harnessctl 권한 · CLAUDE.md$([ "$SCOPE" = project ] && printf ' · rules')

**Claude Code 를 재시작하세요.** 플러그인은 새 세션에서 로드되고, 그때부터
가드가 동작합니다. harnessctl 은 위 shim 으로 어느 셸에서든 부를 수 있습니다.

재시작 후 확인:  harnessctl doctor
EOF
exit "$rc"

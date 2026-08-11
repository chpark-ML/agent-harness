#!/usr/bin/env bash
# agent-harness — one command, complete install.
#
#   ./install.sh                                  # everything, user scope
#   ./install.sh --scope project                  # everything, this repo only
#   ./install.sh --profile dev                    # less than everything
#   ./install.sh --profile dev,python --with-tools  # plus a language server
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
PROFILES="core,dev,research,slides"
SCOPE="user"
REF=""
WITH_TOOLS=0

say()  { printf '==> %s\n' "$*"; }
warn() { printf '!   %s\n' "$*" >&2; }
die()  { printf '!   %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

  --profile <list>   comma-separated: core, dev, research, slides, python, typescript
                     (default: core,dev,research,slides — pass this only to get less)
  --scope <s>        user (default) or project
  --with-tools       npm install the language servers the LSP plugins need
  --ref <ref>        pin the marketplace to a git tag or branch
  -h, --help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)    shift; [ $# -gt 0 ] || die "--profile needs a value"; PROFILES="$1" ;;
    --profile=*)  PROFILES="${1#--profile=}" ;;
    --scope)      shift; [ $# -gt 0 ] || die "--scope needs a value"; SCOPE="$1" ;;
    --scope=*)    SCOPE="${1#--scope=}" ;;
    --with-tools) WITH_TOOLS=1 ;;
    --ref)        shift; [ $# -gt 0 ] || die "--ref needs a value"; REF="$1" ;;
    --ref=*)      REF="${1#--ref=}" ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "unknown argument: $1  (see --help)" ;;
  esac
  shift
done

case "$SCOPE" in user|project) ;; *) die "--scope takes user or project (got: $SCOPE)" ;; esac

PROFILE_LIST="$(printf '%s' "$PROFILES" | tr ',' ' ' | tr -s ' ')"
for p in $PROFILE_LIST; do
  case "$p" in core|dev|research|slides|python|typescript) ;; *) die "unknown profile: $p" ;; esac
done

# Only dev and research carry declarative rules. The language profiles are
# dependency bundles, and slides ships a skill and a script but no rules, so
# none of the three give harnessctl anything to install.
WITH=""
for p in $PROFILE_LIST; do
  case "$p" in dev|research) WITH="${WITH:+$WITH,}$p" ;; esac
done

command -v claude >/dev/null 2>&1 || die "Claude Code is not on PATH."
claude plugin --help >/dev/null 2>&1 || die "This Claude Code does not support plugins. Run 'claude update' and try again."
[ "$SCOPE" = project ] && [ ! -e "$PWD/.git" ] && die "--scope project must be run from the root of a git repository."

# ---- 1. marketplace -----------------------------------------------------------
SOURCE="$MARKETPLACE_REPO"
[ -n "$REF" ] && SOURCE="$MARKETPLACE_REPO@$REF"
say "marketplace: $SOURCE"
if claude plugin marketplace list 2>/dev/null | grep -q "$MARKETPLACE_NAME"; then
  claude plugin marketplace update "$MARKETPLACE_NAME" >/dev/null 2>&1 \
    && say "  already registered — updated to latest" || warn "  update failed, continuing with the existing cache"
else
  claude plugin marketplace add "$SOURCE" >/dev/null || die "could not register the marketplace"
  say "  registered"
fi

# ---- 2. plugins ---------------------------------------------------------------
for p in $PROFILE_LIST; do
  say "plugin: harness-$p (scope: $SCOPE)"
  out="$(claude plugin install "harness-$p@$MARKETPLACE_NAME" --scope "$SCOPE" 2>&1)"
  if [ $? -ne 0 ]; then printf '%s\n' "$out" >&2; die "could not install harness-$p"; fi
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
[ -n "$HCTL" ] && [ -f "$HCTL" ] || die "harnessctl not found. Start a new Claude Code session and run 'harnessctl init --scope $SCOPE' yourself."

# ---- 4. declarative half ------------------------------------------------------
say "harnessctl init (scope: $SCOPE${WITH:+, modules: $WITH})"
bash "$HCTL" init --scope "$SCOPE" ${WITH:+--with "$WITH"} 2>&1 | sed 's/^/    /' \
  || die "harnessctl init failed"

# ---- 5. language servers ------------------------------------------------------
# The LSP plugins do not bundle their server binary. Installing one is a global
# npm change, so it stays opt-in; doctor reports it either way.
install_tool() {
  local bin="$1" pkgs="$2"
  command -v "$bin" >/dev/null 2>&1 && return 0
  if [ "$WITH_TOOLS" -eq 0 ]; then return 0; fi
  command -v npm >/dev/null 2>&1 || { warn "no npm, so $bin cannot be installed"; return 0; }
  say "installing language server: $pkgs"
  # shellcheck disable=SC2086
  npm install -g $pkgs >/dev/null 2>&1 && say "  done" || warn "  install failed — do it by hand: npm install -g $pkgs"
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
#
# One shim per executable in the plugin's bin/, discovered rather than listed.
# A hardcoded name means the next executable ships with a documented terminal
# command that does not exist, and nothing fails to say so.
# The cache lives under the Claude config directory, which is $CLAUDE_CONFIG_DIR
# when set — the same resolution step 3 uses to locate harnessctl. Hardcoding
# $HOME/.claude here (as this did) meant a non-default config directory got a
# successful install and no shim: the glob matched nothing, the loop ran zero
# times, and a single warning was the only sign. The shim body resolves it at
# run time rather than baking today's value in, so moving the config directory
# later does not strand an already-written shim.
# The newest non-orphaned harness-core bin/ under a config directory, or empty.
# Same filter step 3 applies when locating harnessctl, for the same reason.
newest_bindir() {
  local c out=""
  for c in "$1"/plugins/cache/*/harness-core/*/; do
    [ -d "$c/bin" ] || continue
    [ -f "$c/.orphaned_at" ] && continue
    out="$out$c/bin
"
  done
  # Degrade to lexicographic where sort lacks -V, matching step 3 above —
  # wrong only across a digit-count boundary, and slightly-old beats none.
  if printf 'x' | sort -V >/dev/null 2>&1; then
    printf '%s' "$out" | grep -v '^$' | sort -V | tail -1
  else
    printf '%s' "$out" | grep -v '^$' | sort | tail -1
  fi
}

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
say "shell shim"
if mkdir -p "$BIN_DIR" 2>/dev/null; then
  bindir="$(newest_bindir "$CFG")"
  shimmed=0
  for exe in "$bindir"/*; do
    [ -f "$exe" ] && [ -x "$exe" ] || continue
    name="$(basename "$exe")"
    sed "s/@NAME@/$name/g" > "$BIN_DIR/$name" <<'SHIM'
#!/bin/sh
# @NAME@ shim — resolves the installed plugin at run time.
# Installed by agent-harness/install.sh. Safe to delete; re-created on install.
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# Skip superseded copies. `claude plugin update` leaves the old version behind
# with an .orphaned_at marker and its bin/ emptied, and it can sort ABOVE the
# live one — so taking the highest version blindly picks a directory with
# nothing in it. Step 3 of install.sh has always filtered on these markers; the
# shim did not, and that asymmetry is the bug.
d=""
for c in "$cfg"/plugins/cache/*/harness-core/*/; do
  [ -f "$c/.orphaned_at" ] && continue
  [ -x "$c/bin/@NAME@" ] || continue
  d="$d$c/bin
"
done
if printf 'x' | sort -V >/dev/null 2>&1; then
  d=$(printf '%s' "$d" | grep -v '^$' | sort -V | tail -1)
else
  d=$(printf '%s' "$d" | grep -v '^$' | sort | tail -1)
fi
[ -n "$d" ] || { echo "@NAME@: harness-core plugin not found under $cfg. Install it first:" >&2
                 echo "  claude plugin install harness-core@agent-harness --scope user" >&2; exit 1; }
exec "$d/@NAME@" "$@"
SHIM
    chmod +x "$BIN_DIR/$name"
    say "  $BIN_DIR/$name"
    shimmed=$((shimmed + 1))
  done
  [ "$shimmed" -gt 0 ] || warn "  could not find harness-core's bin/ — check that the plugin installed."
  case ":$PATH:" in
    *":$BIN_DIR:"*) say "  already on PATH" ;;
    *)
      # Name the file for the shell the user actually runs, not for bash.
      case "${SHELL##*/}" in
        zsh)  rc="~/.zshrc" ;;
        fish) rc="~/.config/fish/config.fish" ;;
        *)    rc="~/.bashrc (or ~/.bash_profile)" ;;
      esac
      warn "  $BIN_DIR is not on PATH. Add it in $rc:"
      if [ "${SHELL##*/}" = fish ]; then
        say "    fish_add_path $BIN_DIR"
      else
        say "    export PATH=\"$BIN_DIR:\$PATH\""
      fi
      ;;
  esac
else
  warn "  cannot create $BIN_DIR, skipping — call the plugin path directly."
fi
echo

# ---- 6. doctor ----------------------------------------------------------------
say "harnessctl doctor"
bash "$HCTL" doctor --scope "$SCOPE" 2>&1 | sed 's/^/    /'
rc=$?

cat <<EOF

Installed — both halves are in place.

  plugins     hooks, skills, commands, verifiers
  harnessctl  permissions, CLAUDE.md$([ "$SCOPE" = project ] && printf ', rules')

**Restart Claude Code.** Plugins load in a new session, and the guards start
working from then on. The shims above make harnessctl and harness-log callable
from any shell.

After restarting, check with:  harnessctl doctor
EOF
exit "$rc"

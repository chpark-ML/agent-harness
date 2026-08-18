#!/usr/bin/env bash
# agent-harness — one command, complete removal.
#
#   ./uninstall.sh                                # everything, user scope
#   ./uninstall.sh --scope project                # everything, this repo only
#   ./uninstall.sh --dry-run                      # print the plan, write nothing
#   ./uninstall.sh --purge-templates              # take the template files too
#
# The counterpart to install.sh. install.sh puts four things on a machine and
# until now exactly one of them could be taken back by a command: `harnessctl
# uninstall` reverts the declarative half from its manifest, and says so in its
# own last line — "The plugins are untouched". The plugin half, the marketplace
# registration and the shell shims were printed as suggestions for the user to
# copy by hand. This runs all four, in the one order that works.
#
# The order is a constraint, not a preference. harnessctl ships *inside the
# plugin cache*, so removing the plugins first deletes the only tool that can
# revert the declarative half — CLAUDE.md and the rules are then stranded with
# nothing left that knows which lines were ours. Declarative half first, always.
#
# Three things this deliberately leaves alone, and reports instead:
#
#   the bootstrapped jq   install.sh fetches a pinned jq into ~/.local/bin when
#                         the machine has none. harnessctl needs it two steps
#                         below, and by now anything else on the machine may too.
#   language servers      --with-tools installs them with `npm -g`. That is a
#                         global change and another project may be holding them.
#   foreign plugins       Whatever this harness did not install — headroom or
#                         anything else. Deleting a plugin the user chose is the
#                         same overreach the install side already refuses, and
#                         "a settings.json we did not write survives us intact"
#                         is a property scripts/verify-install.sh pins down.
#
# Requires bash 3.2 and jq — the same floor as install.sh. Self-contained on
# purpose: it is fetched with curl and piped to bash exactly as install.sh is,
# so it has no siblings to source and repeats that script's plugin-cache
# resolution rather than sharing it.
set -uo pipefail

MARKETPLACE_NAME="agent-harness"
# Registered by install.sh only when --profile includes frontend. Named here so
# the report below can tell it apart from a marketplace the user added.
UIUX_MARKETPLACE="ui-ux-pro-max-skill"
SCOPE="user"
DRY_RUN=0
PURGE_TEMPLATES=0
# Resolved after the argument loop, not here. Under `set -u` a `$HOME` read at
# the top kills the script before it can parse anything, so on a machine with
# HOME unset — a container, a cron job, a systemd unit — even `--help` died with
# "HOME: unbound variable". Nothing above the loop needs the value.
BIN_DIR="${BIN_DIR:-}"

say()  { printf '==> %s\n' "$*"; }
warn() { printf '!   %s\n' "$*" >&2; }
die()  { printf '!   %s\n' "$*" >&2; exit 1; }

# Every mutation goes through this, so --dry-run is a property of the script
# rather than a flag each step has to remember to check.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '    would run: %s\n' "$*"
    return 0
  fi
  "$@"
}

# The same, for commands whose own chatter is noise. It has to do the
# redirection itself: writing `run cmd >/dev/null` sends the wrapper's own
# "would run" line to /dev/null too, so --dry-run went silent about exactly the
# steps it was being asked to preview.
run_quiet() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '    would run: %s\n' "$*"
    return 0
  fi
  "$@" >/dev/null 2>&1
}

# The registered marketplace names, one per line. The bullet Claude Code prints
# is multibyte, so skipping it with `.` matches under a UTF-8 locale and nothing
# at all under C — the locale CI and a Windows console can both hand this
# script. Measured: the `.` form returned zero rows under LC_ALL=C. One helper
# rather than two call sites, because the first of them tested membership with
# an unanchored grep and matched the "Source: GitHub (owner/agent-harness)"
# line too — a marketplace pointing at a fork read as ours being registered.
marketplace_names() {
  claude plugin marketplace list 2>/dev/null \
    | sed -n 's/^[^A-Za-z0-9]*\([A-Za-z0-9][A-Za-z0-9._-]*\)$/\1/p'
}

usage() {
  sed -n '2,8p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'
  cat <<'EOF'

  --scope <s>          user (default) or project — which install to remove
  --dry-run            print what would happen; write nothing
  --purge-templates    also remove the template files harnessctl left in place
  -h, --help

Left alone and reported, never removed: a bootstrapped jq, npm -g language
servers, and any plugin or marketplace this harness did not install.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --scope)           shift; [ $# -gt 0 ] || die "--scope needs a value"; SCOPE="$1" ;;
    --scope=*)         SCOPE="${1#--scope=}" ;;
    --dry-run)         DRY_RUN=1 ;;
    --purge-templates) PURGE_TEMPLATES=1 ;;
    -h|--help)         usage; exit 0 ;;
    *)                 die "unknown argument: $1  (see --help)" ;;
  esac
  shift
done

case "$SCOPE" in user|project) ;; *) die "--scope takes user or project (got: $SCOPE)" ;; esac

# Where install.sh puts the shims, and where it puts a bootstrapped jq with
# them. Read from the environment first, so an install that overrode BIN_DIR is
# removed by an uninstall that overrides it the same way.
if [ -z "$BIN_DIR" ]; then
  [ -n "${HOME:-}" ] || die "neither BIN_DIR nor HOME is set, so the shim directory cannot be found.
Set BIN_DIR to the directory install.sh wrote the shims to."
  BIN_DIR="$HOME/.local/bin"
fi

command -v claude >/dev/null 2>&1 || die "Claude Code is not on PATH."
claude plugin --help >/dev/null 2>&1 || die "This Claude Code does not support plugins. Run 'claude update' and try again."
[ "$SCOPE" = project ] && [ ! -e "$PWD/.git" ] && die "--scope project must be run from the root of a git repository."

# install.sh may have put jq in BIN_DIR without that directory being on PATH —
# it prepends for the rest of its own process and warns. Do the same here, or
# harnessctl fails on a machine its own installer made work.
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) PATH="$BIN_DIR:$PATH"; export PATH ;; esac
type -P jq >/dev/null 2>&1 || die "jq is required to revert settings.json, and there is none on PATH.
Install one, or if install.sh bootstrapped it, put $BIN_DIR on PATH first."

say "agent-harness uninstall  (scope: $SCOPE)"
[ "$DRY_RUN" -eq 1 ] && say "  (dry-run — nothing is written)"
echo

# ---- 1. locate harnessctl -----------------------------------------------------
# Before step 2 removes the cache it lives in. Same resolution install.sh uses:
# newest non-orphaned version marked .in_use, then the marketplace clone, then
# this checkout — so the script also works from a git clone with no install.
# Guarded, because `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` is still a $HOME read
# under set -u — and BIN_DIR being set in the environment skips the check above,
# so this line could reach the raw "HOME: unbound variable" that check exists to
# replace. Same defect, one line further down.
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  CFG="$CLAUDE_CONFIG_DIR"
else
  [ -n "${HOME:-}" ] || die "neither CLAUDE_CONFIG_DIR nor HOME is set, so the plugin cache cannot be found."
  CFG="$HOME/.claude"
fi
HCTL=""
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

# ---- 2. declarative half ------------------------------------------------------
# A missing manifest is a legitimate state, not a failure: the plugin half can
# be installed without `harnessctl init` ever having run. harnessctl dies on it,
# correctly, so the condition is checked here rather than letting a normal
# machine state abort a removal that still has three steps to do.
say "declarative half (harnessctl uninstall)"
# The same two paths harnessctl derives from --scope. Checked here rather than
# passed, so this script asks the question before harnessctl dies on it.
if [ "$SCOPE" = user ]; then
  MANIFEST="$CFG/harness-manifest.json"
else
  MANIFEST="$PWD/.claude/harness-manifest.json"
fi
PT_FLAG=""
[ "$PURGE_TEMPLATES" -eq 1 ] && PT_FLAG="--purge-templates"
if [ -z "$HCTL" ] || [ ! -f "$HCTL" ]; then
  warn "  harnessctl not found — skipping. Files it installed are left behind."
elif [ -f "$MANIFEST" ]; then
  run bash "$HCTL" uninstall --scope "$SCOPE" ${PT_FLAG:+"$PT_FLAG"} 2>&1 | sed 's/^/    /'
  # `set -o pipefail` already carries harnessctl's status out of that pipeline;
  # until now nothing read it, so its error printed as ordinary indented output
  # and the run carried on. That is the one failure this script's ordering
  # exists to prevent: step 3 deletes the cache harnessctl lives in, so a
  # declarative half that failed to revert can never be reverted afterwards.
  # Half-removed is recoverable by re-running. Unrevertable is not.
  hctl_rc=${PIPESTATUS[0]}
  if [ "$hctl_rc" -ne 0 ]; then
    warn "  harnessctl uninstall failed (exit $hctl_rc)."
    warn "  Stopping before the plugin half: removing it now would delete the only"
    warn "  tool that can revert what harnessctl has just failed to revert."
    warn "  Fix the cause it named above and re-run — nothing else has been touched."
    exit 1
  fi
else
  say "  no manifest at $MANIFEST — nothing to revert"
fi
echo

# ---- 3. plugin half -----------------------------------------------------------
# Filtered on the marketplace, not on the name. A plugin that merely calls
# itself harness-something in an unrelated marketplace must not be swept into a
# destructive loop — harnessctl's own installed_plugins() draws the line in the
# same place and for the same reason.
#
# --prune takes the auto-installed dependencies with it, which is how
# superpowers leaves: install.sh never installs it directly, a profile declares
# it, and prune removes what nothing needs any more. -y because --prune asks
# when stdout is not a TTY.
say "plugin half (scope: $SCOPE)"
OURS="$(claude plugin list --json 2>/dev/null \
  | jq -r --arg m "@$MARKETPLACE_NAME" --arg s "$SCOPE" \
      '.[] | select(.id | endswith($m)) | select(.scope == $s) | .id' 2>/dev/null)"
if [ -n "$OURS" ]; then
  printf '%s\n' "$OURS" | while IFS= read -r id; do
    [ -n "$id" ] || continue
    say "  $id"
    run_quiet claude plugin uninstall "$id" --scope "$SCOPE" --prune -y \
      || warn "    could not uninstall $id — remove it by hand"
  done
else
  say "  none installed at this scope"
fi
echo

# ---- 4. marketplace -----------------------------------------------------------
# Last of the Claude-side steps: removing the registration first would take the
# marketplace clone that step 1's fallback resolves harnessctl through.
say "marketplace"
if marketplace_names | grep -qx "$MARKETPLACE_NAME"; then
  # Removed only when nothing of ours still needs it. The two modes ask
  # different questions on purpose. A dry run has removed nothing yet, so it has
  # to *predict* — everything at this scope is about to go, and what remains is
  # whatever sits at the other one. A real run can simply *look*, and looking is
  # stricter: a plugin step 3 failed to remove is still installed at this scope,
  # and it holds the registration open exactly as it should.
  if [ "$DRY_RUN" -eq 1 ]; then
    LEFT="$(claude plugin list --json 2>/dev/null \
      | jq -r --arg m "@$MARKETPLACE_NAME" --arg s "$SCOPE" \
          '.[] | select(.id | endswith($m)) | select(.scope != $s) | .id' 2>/dev/null)"
  else
    LEFT="$(claude plugin list --json 2>/dev/null \
      | jq -r --arg m "@$MARKETPLACE_NAME" '.[] | select(.id | endswith($m)) | .id' 2>/dev/null)"
  fi
  if [ -n "$LEFT" ]; then
    say "  kept — still used by:"
    printf '%s\n' "$LEFT" | sed 's/^/    /'
  elif run_quiet claude plugin marketplace remove "$MARKETPLACE_NAME"; then
    # Not in a dry run: nothing was removed, and saying "removed" there was a
    # plain false report — run_quiet has already printed what would happen.
    [ "$DRY_RUN" -eq 0 ] && say "  removed"
  else
    warn "  could not remove the marketplace — remove it by hand"
  fi
else
  say "  not registered"
fi
echo

# ---- 5. shell shims -----------------------------------------------------------
# Identified by the marker install.sh writes into every shim body, never by
# name. A file called harnessctl that this harness did not write is somebody
# else's, and a bootstrapped jq sits in the same directory without the marker —
# which is exactly why the marker and not the directory decides.
say "shell shims"
shim_found=0
for s in "$BIN_DIR"/*; do
  [ -f "$s" ] || continue
  grep -q 'shim — resolves the installed plugin at run time' "$s" 2>/dev/null || continue
  say "  $s"
  run rm -f "$s" || warn "    could not remove $s"
  shim_found=$((shim_found + 1))
done
[ "$shim_found" -gt 0 ] || say "  none found in $BIN_DIR"
echo

# ---- 6. what is left ----------------------------------------------------------
# Everything below is reported and never touched. The commands are printed
# ready to paste, because the decision is the user's and the removal is one
# line once they have made it.
say "left in place (not ours to remove)"
# In a dry run this is read before any of the removals above have happened, so
# it still lists what --prune is about to take with it — superpowers arrives as
# a profile dependency and leaves the same way. Saying so beats predicting it.
[ "$DRY_RUN" -eq 1 ] && say "  (dry-run: read before the steps above, so it still lists what --prune takes)"
left_any=0

if [ -x "$BIN_DIR/jq" ]; then
  say "  jq at $BIN_DIR/jq — install.sh bootstraps one when the machine has none"
  say "    remove with:  rm $BIN_DIR/jq"
  left_any=1
fi

for t in pyright-langserver typescript-language-server; do
  p="$(command -v "$t" 2>/dev/null)" || continue
  [ -n "$p" ] || continue
  say "  $t at $p — installed by --with-tools, or by you"
  left_any=1
done

FOREIGN="$(claude plugin list --json 2>/dev/null \
  | jq -r --arg m "@$MARKETPLACE_NAME" \
      '.[] | select(.id | endswith($m) | not) | "\(.id)  (scope: \(.scope), \(if .enabled then "enabled" else "disabled" end))"' 2>/dev/null)"
if [ -n "$FOREIGN" ]; then
  say "  plugins this harness did not install:"
  printf '%s\n' "$FOREIGN" | sed 's/^/    /'
  say "    remove one with:  claude plugin uninstall <id> --prune -y"
  left_any=1
fi

# Ours to have registered, but not ours to remove: this marketplace can serve a
# plugin the user installed for their own reasons, and §6's ownership model does
# not delete a value the consumer already had. Reported with the right
# provenance instead of falling into the "did not register" list below, which
# would be untrue.
if marketplace_names | grep -qx "$UIUX_MARKETPLACE"; then
  say "  $UIUX_MARKETPLACE — registered by install.sh --profile frontend"
  say "    the ui-ux-pro-max plugin itself already left with --prune above"
  say "    remove with:  claude plugin marketplace remove $UIUX_MARKETPLACE"
  left_any=1
fi

FOREIGN_MKT="$(marketplace_names | grep -v "^$MARKETPLACE_NAME$" | grep -v "^$UIUX_MARKETPLACE$")"
if [ -n "$FOREIGN_MKT" ]; then
  say "  marketplaces this harness did not register:"
  printf '%s\n' "$FOREIGN_MKT" | sed 's/^/    /'
  say "    remove one with:  claude plugin marketplace remove <name>"
  left_any=1
fi

[ "$left_any" -eq 0 ] && say "  nothing"
echo

if [ "$DRY_RUN" -eq 1 ]; then
  say "dry-run finished — nothing changed."
  exit 0
fi

cat <<'EOF'
Removed. Restart Claude Code — plugins unload in a new session, so the guards
keep running until you do.
EOF

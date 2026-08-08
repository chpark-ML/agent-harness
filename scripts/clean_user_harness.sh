#!/usr/bin/env bash
# clean_user_harness.sh — empty the user-level Claude Code harness config.
#
# The harness (plugins, agents, skills, hooks) belongs to project scope. User
# scope applies it to every unrelated project on the machine: a hook written for
# one repository fires in all of them, and a skill meant for one domain competes
# for every trigger. This script produces the empty state, repeatably, on each
# machine that drifted into it.
#
# Usage:
#   bash scripts/clean_user_harness.sh                  # report only (default, changes nothing)
#   bash scripts/clean_user_harness.sh --apply          # remove user-scope plugins
#   bash scripts/clean_user_harness.sh --apply --purge  # + delete orphan caches / empty data dirs
#
# Remote, without copying the file:
#   ssh HOST 'bash -s --' < scripts/clean_user_harness.sh
#   ssh HOST 'bash -s -- --apply' < scripts/clean_user_harness.sh
#
# Behavior:
#   1) remove every user-scope plugin (enabledPlugins + installed_plugins.json)
#   2) deregister dead marketplaces (source is a directory that no longer exists)
#   3) delete orphan caches / empty data dirs — only with --purge
#   Uses `claude plugin uninstall` when the CLI is present; edits the JSON directly
#   when it is not, because the servers this runs on often have no CLI.
#
# What it never touches:
#   - project / local scope plugins
#   - hand-written assets: agents, skills, commands, hooks, CLAUDE.md under
#     ~/.claude, and settings.json's own hooks — reported, never deleted
#   - user settings unrelated to the harness (model, effortLevel, permissions)
#
# The target directory is $CLAUDE_CONFIG_DIR, falling back to ~/.claude — so in a
# container with a profile selected, that profile is the one cleaned.
#
# settings.json / installed_plugins.json / known_marketplaces.json are copied to
# .bak-<timestamp> before any write. To undo, copy them back over the originals.

set -uo pipefail

APPLY=0
PURGE=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    --purge | --purge-cache) PURGE=1 ;;
    -h | --help)
      sed -n '2,36p' "$0"
      exit 0
      ;;
    *)
      echo "unknown option: $a" >&2
      exit 2
      ;;
  esac
done

CDIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CDIR/settings.json"
INSTALLED="$CDIR/plugins/installed_plugins.json"
MARKETS="$CDIR/plugins/known_marketplaces.json"
TS=$(date +%Y%m%d-%H%M%S)

say() { printf '%s\n' "$*"; }
hdr() { printf '\n=== %s ===\n' "$*"; }

say "host: $(hostname)   config: $CDIR   mode: $([ $APPLY -eq 1 ] && echo APPLY || echo DRY-RUN)"

if [ ! -d "$CDIR" ]; then
  say "no ~/.claude — nothing to clean."
  exit 0
fi

PY=$(command -v python3 || command -v python || true)
if [ -z "$PY" ]; then
  say "python3 required — not found, stopping."
  exit 1
fi

# ---------- 1. survey what user scope currently holds ----------
hdr "user-scope plugins"
USER_PLUGINS=$(
  "$PY" - "$SETTINGS" "$INSTALLED" <<'EOF'
import json, os, sys
ids = set()
for path, extract in ((sys.argv[1], 'settings'), (sys.argv[2], 'installed')):
    if not os.path.exists(path):
        continue
    try:
        d = json.load(open(path))
    except Exception:
        continue
    if extract == 'settings':
        ids |= set(d.get('enabledPlugins', {}))
    else:
        for pid, entries in (d.get('plugins') or {}).items():
            if any(e.get('scope') == 'user' for e in entries):
                ids.add(pid)
print('\n'.join(sorted(ids)))
EOF
)
[ -n "$USER_PLUGINS" ] && say "$USER_PLUGINS" || say "(none)"

hdr "hand-written harness assets"
for sub in agents skills commands hooks CLAUDE.md; do
  p="$CDIR/$sub"
  if [ -e "$p" ]; then
    n=$(find "$p" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
    say "  present: $sub  ($n entries)   <- review by hand; this script never deletes it"
  fi
done
"$PY" - "$SETTINGS" <<'EOF'
import json, os, sys
p = sys.argv[1]
if os.path.exists(p):
    try:
        d = json.load(open(p))
    except Exception:
        sys.exit()
    if d.get('hooks'):
        print("  present: hooks in settings.json   <- review by hand")
EOF

hdr "dead marketplaces (directory source, path gone)"
"$PY" - "$MARKETS" <<'EOF'
import json, os, sys
p = sys.argv[1]
if not os.path.exists(p):
    sys.exit()
try:
    d = json.load(open(p))
except Exception:
    sys.exit()
dead = [n for n, m in d.items()
        if (m.get('source') or {}).get('source') == 'directory'
        and not os.path.isdir((m.get('source') or {}).get('path', ''))]
print('\n'.join(dead) if dead else '(none)')
EOF

if [ $APPLY -eq 0 ]; then
  hdr "DRY-RUN"
  say "re-run with --apply to actually remove."
  exit 0
fi

# ---------- 2. back up before any write ----------
hdr "backup"
for f in "$SETTINGS" "$INSTALLED" "$MARKETS"; do
  [ -f "$f" ] && cp "$f" "$f.bak-$TS" && say "  $f.bak-$TS"
done

# ---------- 3. remove user-scope plugins ----------
hdr "removing user-scope plugins"
if [ -z "$USER_PLUGINS" ]; then
  say "  (none)"
elif command -v claude >/dev/null 2>&1; then
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    claude plugin uninstall "$p" -s user -y 2>&1 | tail -2 | sed 's/^/  /'
  done <<<"$USER_PLUGINS"
else
  say "  no claude CLI -> editing settings.json / installed_plugins.json directly"
  "$PY" - "$SETTINGS" "$INSTALLED" <<'EOF'
import json, os, sys
s, i = sys.argv[1], sys.argv[2]
if os.path.exists(s):
    d = json.load(open(s))
    d['enabledPlugins'] = {}
    json.dump(d, open(s, 'w'), indent=2, ensure_ascii=False)
    print("  settings.json: enabledPlugins = {}")
if os.path.exists(i):
    d = json.load(open(i))
    plugins = d.get('plugins') or {}
    for pid in list(plugins):
        kept = [e for e in plugins[pid] if e.get('scope') != 'user']
        if kept:
            plugins[pid] = kept
        else:
            del plugins[pid]
            print(f"  installed_plugins.json: removed {pid}")
    json.dump(d, open(i, 'w'), indent=2, ensure_ascii=False)
EOF
fi

# ---------- 4. deregister dead marketplaces ----------
hdr "removing dead marketplaces"
DEAD=$(
  "$PY" - "$MARKETS" <<'EOF'
import json, os, sys
p = sys.argv[1]
if os.path.exists(p):
    try:
        d = json.load(open(p))
    except Exception:
        d = {}
    for n, m in d.items():
        src = m.get('source') or {}
        if src.get('source') == 'directory' and not os.path.isdir(src.get('path', '')):
            print(n)
EOF
)
if [ -z "$DEAD" ]; then
  say "  (none)"
else
  if command -v claude >/dev/null 2>&1; then
    while IFS= read -r m; do
      [ -z "$m" ] && continue
      claude plugin marketplace remove "$m" 2>&1 | tail -1 | sed 's/^/  /'
    done <<<"$DEAD"
  else
    say "  no claude CLI -> editing known_marketplaces.json / settings.json directly"
    "$PY" - "$MARKETS" "$SETTINGS" <<'EOF'
import json, os, sys
mk, st = sys.argv[1], sys.argv[2]
dead = []
if os.path.exists(mk):
    d = json.load(open(mk))
    for n in list(d):
        src = d[n].get('source') or {}
        if src.get('source') == 'directory' and not os.path.isdir(src.get('path', '')):
            del d[n]
            dead.append(n)
            print(f"  known_marketplaces.json: removed {n}")
    json.dump(d, open(mk, 'w'), indent=2, ensure_ascii=False)
if dead and os.path.exists(st):
    s = json.load(open(st))
    ekm = s.get('extraKnownMarketplaces') or {}
    for n in dead:
        if ekm.pop(n, None) is not None:
            print(f"  settings.json: removed extraKnownMarketplaces.{n}")
    if ekm or 'extraKnownMarketplaces' in s:
        s['extraKnownMarketplaces'] = ekm
    json.dump(s, open(st, 'w'), indent=2, ensure_ascii=False)
EOF
  fi
fi

# ---------- 5. orphan caches / empty data dirs ----------
hdr "orphan caches / empty data dirs"
if [ $PURGE -eq 0 ]; then
  say "  --purge not given — keeping them."
  say "  careful: for a directory-source marketplace the cache may be the only copy. Check before deleting."
else
  KNOWN=$(
    "$PY" - "$MARKETS" <<'EOF'
import json, os, sys
p = sys.argv[1]
if os.path.exists(p):
    try:
        print('\n'.join(json.load(open(p))))
    except Exception:
        pass
EOF
  )
  if [ -d "$CDIR/plugins/cache" ]; then
    for d in "$CDIR/plugins/cache"/*/; do
      [ -d "$d" ] || continue
      name=$(basename "$d")
      if ! grep -qxF "$name" <<<"$KNOWN"; then
        say "  deleting cache: $name ($(du -sh "$d" 2>/dev/null | cut -f1))"
        rm -rf "$d"
      fi
    done
  fi
  if [ -d "$CDIR/plugins/data" ]; then
    for d in "$CDIR/plugins/data"/*/; do
      [ -d "$d" ] || continue
      if [ -z "$(ls -A "$d" 2>/dev/null)" ]; then
        say "  deleting empty data dir: $(basename "$d")"
        rmdir "$d"
      fi
    done
  fi
fi

hdr "done"
say "to undo: copy the .bak-$TS files back over the originals."
say "changes take effect from the next Claude Code session."

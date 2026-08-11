#!/bin/bash
# verify-doc-commands.sh — a command a document tells you to run has to exist.
#
# verify-doc-refs checks that a referenced FILE exists. Nothing checked that a
# referenced COMMAND does what the prose says, and the gap has cost twice:
#
#   - `echo 'login' >> .claude/gh-account.txt` — the file is read first line
#     only, so the documented way to fix a typo silently changes nothing.
#   - `bash install.sh --dry-run` — the installer has no such flag; the
#     instruction dies with `unknown argument`.
#
# Both are syntactically fine and point at real files, so every existing check
# passed. This is the narrow half of the ledger's proposal, and the half that
# would have caught the flag defect: for every fenced block in the documents,
# take the lines that invoke the harness's own commands and confirm each
# subcommand and each long flag against the parser that actually accepts them.
#
# The PARSER is the authority, not `--help`. Usage text is prose and can drift
# on its own — that is the same class of bug being caught here.
#
# NOT done: executing the blocks. Running documented commands for real needs a
# sandbox per block and would make this expensive and flaky; the ledger's
# proposal says to start narrow, and the flag check alone covers two of the
# three incidents on record.
#
# Harness-repo only — not shipped to consumers.
# Run:  bash scripts/verify-doc-commands.sh [--selftest]

set -uo pipefail

REPO="${VERIFY_DOC_COMMANDS_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
. "$(cd "$(dirname "$0")" && pwd)/_check-lib.sh"

# ---- what the parsers actually accept ---------------------------------------
# Read from the `--flag)` arms of each script's argument loop. A flag that is
# not an arm is a flag that exits non-zero, whatever the usage text says.
parser_flags() { # <script path>
  grep -oE '^[[:space:]]+--[a-z-]+\)' "$1" 2>/dev/null | tr -d ' )' | LC_ALL=C sort -u
}

HCTL="$REPO/plugins/harness-core/bin/harnessctl"
INSTALL="$REPO/install.sh"
MAKEFILE="$REPO/Makefile"

HCTL_FLAGS="$(parser_flags "$HCTL") --help"
INSTALL_FLAGS="$(parser_flags "$INSTALL") --help"
# Subcommands come from the dispatcher's own comparisons.
# From the usage block, not from `[ "$CMD" = x ]` — `init` is the fall-through
# and has no such comparison, so reading the dispatcher misses it.
HCTL_CMDS="$(grep -oE '^#   harnessctl [a-z]+' "$HCTL" 2>/dev/null | awk '{print $3}' | LC_ALL=C sort -u)"
MAKE_TARGETS="$(grep -oE '^[a-z][a-z-]*:' "$MAKEFILE" 2>/dev/null | tr -d ':' | LC_ALL=C sort -u)"

has() { # <needle> <haystack…>
  local n="$1"; shift
  case " $* " in *" $n "*) return 0 ;; *) return 1 ;; esac
}

# ---- the documents -----------------------------------------------------------
doc_list() {
  ( cd "$REPO" && ls *.md 2>/dev/null; find docs -name '*.md' 2>/dev/null | LC_ALL=C sort )
}

# Pull the command lines out of fenced blocks. Placeholders are skipped: a
# document showing `harnessctl init --scope <scope>` is teaching a shape, not
# giving a command, and flagging it would be the false positive that gets a
# checker switched off.
check_file() { # <relative path>
  local rel="$1" f="$REPO/$1" in_block=0 cont=0 line cmd word flag
  [ -f "$f" ] || return 0
  while IFS= read -r line; do
    case "$line" in
      '```'*) in_block=$((1 - in_block)); cont=0; continue ;;
    esac
    [ "$in_block" -eq 1 ] || continue

    # A backslash continuation makes the NEXT line arguments, not a command.
    # Without this, `git add … \` followed by an indented
    # `plugins/harness-core/bin/harnessctl scripts/verify-install.sh` reads as
    # an invocation whose subcommand is a file path — observed on a real page.
    was_cont=$cont
    case "$line" in *\\) cont=1 ;; *) cont=0 ;; esac
    [ "$was_cont" -eq 1 ] && continue

    cmd="${line%%#*}"                       # drop trailing comments
    cmd="$(printf '%s' "$cmd" | sed 's/^[[:space:]]*\$\{0,1\}[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$cmd" ] || continue
    case "$cmd" in *'<'*'>'*|*'…'*|*'...'*) continue ;; esac

    # A command is the FIRST token of a segment, and the program is matched by
    # basename. Without that anchor, `remove with: rm ~/.local/bin/harnessctl`
    # reads as an invocation whose subcommand is `with:`, and a path printed in
    # sample output reads as a command line — both observed. This is the same
    # anchoring the gh-account-guard gate needed, for the same reason: a checker
    # that cries wolf gets switched off.
    # heredoc, never a pipe: a piped `while` runs in a subshell and every
    # ok/bad it records is discarded — the trap this repository already
    # documented in gh-account-guard's gate.
    while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$seg" ] || continue
    # A leading `cd x && harnessctl …` puts the real command in the next
    # segment, which this loop reaches on its own.
    set -- $seg
    prog="$(basename "${1:-}")"
    case "$prog" in
      bash|sh) shift; prog="$(basename "${1:-}")" ;;
    esac
    [ -n "$prog" ] || continue
    cmd="$seg"

    case "$prog" in
      harnessctl)
        set -- $cmd
        shift                                # the program itself
        [ $# -gt 0 ] || continue
        if has "$1" $HCTL_CMDS; then
          ok "$rel — harnessctl $1"
        else
          case "$1" in --*) ;; *) bad "$rel — harnessctl $1" "not a subcommand; the dispatcher knows: $(printf '%s' "$HCTL_CMDS" | tr '\n' ' ')" ;; esac
        fi
        for word in "$@"; do
          case "$word" in
            --) ;;                       # sh's end-of-options marker, not a flag
            --*) flag="${word%%=*}"
                 has "$flag" $HCTL_FLAGS \
                   && ok "$rel — harnessctl $flag" \
                   || bad "$rel — harnessctl $flag" "no such flag; the parser accepts: $(printf '%s' "$HCTL_FLAGS" | tr '\n' ' ')" ;;
          esac
        done
        ;;
      install.sh)
        set -- $cmd
        for word in "$@"; do
          case "$word" in
            --) ;;                       # sh's end-of-options marker, not a flag
            --*) flag="${word%%=*}"
                 has "$flag" $INSTALL_FLAGS \
                   && ok "$rel — install.sh $flag" \
                   || bad "$rel — install.sh $flag" "no such flag; the parser accepts: $(printf '%s' "$INSTALL_FLAGS" | tr '\n' ' ')" ;;
          esac
        done
        ;;
      make)
        set -- $cmd
        shift
        [ $# -gt 0 ] || continue
        case "$1" in
          *=*) continue ;;                   # `make VAR=x` with no target
        esac
        has "$1" $MAKE_TARGETS \
          && ok "$rel — make $1" \
          || bad "$rel — make $1" "no such target in the Makefile" ;;
    esac
    done <<EOF
$(printf '%s' "$cmd" | tr ';|&' '\n')
EOF
  done < "$f"
}

# ---- selftest ----------------------------------------------------------------
if [ "${1:-}" = "--selftest" ]; then
  echo "=== doc-commands selftest ==="
  FIX="$(mktemp -d)" || exit 1
  trap 'rm -rf "$FIX"' EXIT
  mkdir -p "$FIX/plugins/harness-core/bin" "$FIX/docs"
  cat > "$FIX/plugins/harness-core/bin/harnessctl" <<'S'
#!/bin/bash
    --scope)      SCOPE="$1" ;;
    --dry-run)    DRY=1 ;;
#   harnessctl init      [--scope user|project]
#   harnessctl doctor    [--scope user|project]
S
  cat > "$FIX/install.sh" <<'S'
#!/bin/bash
    --profile)    P="$1" ;;
S
  printf 'verify:\n\t@true\n' > "$FIX/Makefile"

  cat > "$FIX/good.md" <<'D'
```bash
harnessctl doctor --scope user
make verify
```
D
  cat > "$FIX/bad-flag.md" <<'D'
```bash
harnessctl init --nonesuch
bash install.sh --dry-run
```
D
  cat > "$FIX/bad-target.md" <<'D'
```bash
make nonexistent-target
```
D
  cat > "$FIX/docs/prose.md" <<'D'
Outside a fence, `harnessctl init --nonesuch` is only prose.
```bash
harnessctl init --scope <scope>
harnessctl doctor   # a trailing comment --nonesuch
cd somewhere && harnessctl doctor
git add one/path \
        plugins/harness-core/bin/harnessctl scripts/verify-install.sh
echo "  remove with:  rm ~/.local/bin/harnessctl"
```
D

  out="$(VERIFY_DOC_COMMANDS_REPO="$FIX" "${BASH:-bash}" "$0" 2>&1)"; rc=$?

  check_rc "a real flag passes"        "$(printf '%s' "$out" | grep -q 'good.md — harnessctl --scope' && echo 0 || echo 1)"
  check_rc "a real target passes"      "$(printf '%s' "$out" | grep -q 'good.md — make verify' && echo 0 || echo 1)"
  check_rc "an invented flag is caught" "$(printf '%s' "$out" | grep -q 'bad-flag.md — harnessctl --nonesuch' && echo 0 || echo 1)"
  check_rc "an installer flag that does not exist is caught" \
    "$(printf '%s' "$out" | grep -q 'bad-flag.md — install.sh --dry-run' && echo 0 || echo 1)"
  check_rc "a missing make target is caught" \
    "$(printf '%s' "$out" | grep -q 'bad-target.md — make nonexistent-target' && echo 0 || echo 1)"
  check_rc "...and the run fails"      "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
  check_rc "prose outside a fence is not a command" \
    "$(printf '%s' "$out" | grep -q 'prose.md — harnessctl --nonesuch' && echo 1 || echo 0)"
  check_rc "a placeholder is not a command" \
    "$(printf '%s' "$out" | grep -q 'prose.md — harnessctl --scope' && echo 1 || echo 0)"
  check_rc "a trailing comment is not parsed as arguments" \
    "$(printf '%s' "$out" | grep -qE 'prose.md.*--nonesuch' && echo 1 || echo 0)"
  # Three shapes that read as invocations without an anchor, all observed on
  # real pages: a path in a continuation line, a path inside printed sample
  # output, and the command after `cd x &&` (which IS one, and must be seen).
  check_rc "a continuation line is arguments, not a command" \
    "$(printf '%s' "$out" | grep -q 'prose.md — harnessctl scripts/verify-install.sh' && echo 1 || echo 0)"
  # Asserted as "prose.md produces no failure at all", not as one expected
  # message: pinning a specific string let a broken anchor pass for the wrong
  # reason when it happened to fail differently.
  check_rc "nothing in prose.md is read as a command" \
    "$(printf '%s' "$out" | grep '^  FAIL' | grep -q 'prose.md' && echo 1 || echo 0)" \
    "got: $(printf '%s' "$out" | grep '^  FAIL' | grep 'prose.md' | head -2 | tr '\n' ' ')"
  check_rc "the command after cd && IS seen" \
    "$(printf '%s' "$out" | grep -c 'prose.md — harnessctl doctor' | grep -qE '^[2-9]' && echo 0 || echo 1)" \
    "expected two doctor hits (bare and after cd &&)"

  summary
  exit $?
fi

echo "=== doc-commands verification ==="
echo "  harnessctl subcommands   $(printf '%s' "$HCTL_CMDS" | tr '\n' ' ')"
echo "  harnessctl flags         $(printf '%s' "$HCTL_FLAGS" | tr '\n' ' ')"
echo "  install.sh flags         $(printf '%s' "$INSTALL_FLAGS" | tr '\n' ' ')"
echo

for rel in $(doc_list); do
  check_file "$rel"
done

summary "  A documented command must exist. Fix the document, or add the flag."
exit $?

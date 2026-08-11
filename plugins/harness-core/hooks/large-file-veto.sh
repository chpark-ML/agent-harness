#!/bin/bash
# large-file-veto — block a `git add` that would stage an oversized file.
#
# catches  a `git add` that would stage a file over the size ceiling
#          (HARNESS_LARGE_FILE_BYTES, default 10 MiB)
# scope    PreToolUse, Bash
# bypass   HARNESS_LARGE_FILE_BYTES=<n> <command>, or track the file with LFS
#
# Catches the "git add -A swept in a 200 MB artifact" failure mode. Once a
# large blob is committed it is in the history forever unless someone rewrites
# it, so the cheap move is to stop it at staging time.
#
# Threshold: HARNESS_LARGE_FILE_BYTES (default 10 MiB = 10485760).
# Bypass: track it with Git LFS, add it to .gitignore, or raise the threshold
# for one shell: HARNESS_LARGE_FILE_BYTES=<bytes> <command>.
#
# Known limits, all deliberate — a parser that fully understood shell would be
# larger than the thing it guards:
#   - `git -C <dir> add` is not detected. This differs from ai-attribution-guard,
#     which does handle `git -C ... commit`, and the difference is principled
#     rather than an oversight: that hook inspects the command text, which means
#     the same thing wherever it runs, while this one resolves every argument
#     against a directory on disk. Honouring `-C` here means honouring it for
#     the size lookups too, and half-honouring it would size up the wrong files.
#   - quoted paths containing whitespace are split on the whitespace
#   - already-tracked files of the same size are still blocked
#   - symlinks are skipped rather than followed
#   - `git add --dry-run <big>` is blocked even though it stages nothing
#   - `-A` with a pathspec enumerates the whole worktree, ignoring the pathspec
#   - a `git add` inside a quoted string is still read as an invocation when it
#     begins its own segment
#
# Exit: 0 allow · 2 block.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "large-file-veto: jq not found — hook disabled. Install jq to enable." >&2
  exit 0
fi

# jq on Windows writes CRLF. `$(...)` strips the trailing newline and leaves the
# CR, so every captured value ends in a stray byte: exact comparisons fail while
# substring matches keep working, which means the guard goes quiet instead of
# going wrong. `verify-gh-account-guard` caught it as eight failures in a hook
# that was correct; in the field it is a push that should have been blocked.
#
# Normalised once here rather than at each call site, and unconditionally --
# `tr -d '\r'` is a no-op on LF, whereas a Windows-only branch would be a line
# that only ever runs in one environment (CLAUDE.md section 4). PIPESTATUS keeps
# jq's own exit status, which `jq -e` and `jq empty` callers depend on.
jq() { local rc; command jq "$@" | tr -d '\r'; rc=${PIPESTATUS[0]}; return "$rc"; }

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // ""')"
[ "$tool" != "Bash" ] && exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
[ -z "$cmd" ] && exit 0

# Cheap early exit. It must never be tighter than the awk matcher below, or a
# command the matcher would catch never reaches it — `git  add` (two spaces)
# used to slip through a `*"git add"*` gate.
case "$cmd" in
  *git*) ;;
  *) exit 0 ;;
esac

THRESHOLD="${HARNESS_LARGE_FILE_BYTES:-10485760}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# The arguments of every `git add` in the command, one invocation per line.
#
# Splitting on the statement separators first is what makes this safe: an
# earlier version ran a greedy `sub(/^.*git add/, "")` over the whole command,
# and because `.` also matches the newlines it had just substituted in, the
# LAST `git add` won instead of the first — `git add big.bin && git add ok.txt`
# sailed through. Now each segment is examined on its own and all of them are
# checked, so ordering cannot hide anything.
segments="$(printf '%s' "$cmd" | awk '
  {
    n = split($0, seg, /[\n;&|()]+/)
    for (i = 1; i <= n; i++) {
      if (match(seg[i], /^[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+add([[:space:]]|$)/)) {
        s = substr(seg[i], RSTART)
        sub(/^[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+add[[:space:]]*/, "", s)
        print s
      }
    }
  }
')"
[ -z "$segments" ] && exit 0

tokens=()
while IFS= read -r seg_line; do
  [ -n "$seg_line" ] || continue
  part=()
  read -r -a part <<<"$seg_line"
  tokens+=("${part[@]+"${part[@]}"}")
done <<EOF
$segments
EOF
[ ${#tokens[@]} -eq 0 ] && exit 0

enumerate_all=0
enumerate_modified=0
explicit_paths=()

for tok in "${tokens[@]+"${tokens[@]}"}"; do
  case "$tok" in
    --) ;;
    -A|--all) enumerate_all=1 ;;
    -u|--update) enumerate_modified=1 ;;
    .) enumerate_all=1 ;;
    --dry-run|-n|--help|-h|--patch|-p|-i|--interactive|-e|--edit|-v|--verbose|-f|--force|--ignore-errors|--ignore-missing|--renormalize) ;;
    -*) ;;
    *)
      tok="${tok%\"}"; tok="${tok#\"}"
      tok="${tok%\'}"; tok="${tok#\'}"
      [ -n "$tok" ] || continue
      case "$tok" in
        *"*"*|*"?"*|*"["*)
          # Expand against the project, since neither `read -a` nor `[ -f ]` globs.
          while IFS= read -r m; do
            [ -n "$m" ] && explicit_paths+=("$m")
          done < <(cd "$PROJECT_DIR" 2>/dev/null && for g in $tok; do [ -e "$g" ] && printf '%s\n' "$g"; done)
          ;;
        *) explicit_paths+=("$tok") ;;
      esac
      ;;
  esac
done

candidates=()

if [ $enumerate_all -eq 1 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && candidates+=("$line")
  done < <(cd "$PROJECT_DIR" 2>/dev/null && git ls-files --others --modified --exclude-standard 2>/dev/null || true)
fi

if [ $enumerate_modified -eq 1 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && candidates+=("$line")
  done < <(cd "$PROJECT_DIR" 2>/dev/null && git ls-files --modified 2>/dev/null || true)
fi

for p in "${explicit_paths[@]+"${explicit_paths[@]}"}"; do
  abs="$p"
  case "$p" in /*) ;; *) abs="$PROJECT_DIR/$p" ;; esac
  if [ -d "$abs" ] && [ ! -L "$abs" ]; then
    while IFS= read -r f; do
      candidates+=("$f")
    done < <(find "$abs" -type f -not -path '*/.git/*' 2>/dev/null || true)
  elif [ -f "$abs" ] && [ ! -L "$abs" ]; then
    candidates+=("$p")
  fi
done

violations=()
seen=":"
for f in "${candidates[@]+"${candidates[@]}"}"; do
  case "$seen" in *":$f:"*) continue ;; esac
  seen="$seen$f:"

  abs="$f"
  case "$f" in /*) ;; *) abs="$PROJECT_DIR/$f" ;; esac
  [ -f "$abs" ] && [ ! -L "$abs" ] || continue

  size=$(stat -c%s "$abs" 2>/dev/null || stat -f%z "$abs" 2>/dev/null || echo 0)
  if [ "$size" -gt "$THRESHOLD" ]; then
    mb=$((size / 1024 / 1024))
    violations+=("$f (${mb} MiB)")
  fi
done

if [ ${#violations[@]} -gt 0 ]; then
  threshold_mb=$((THRESHOLD / 1024 / 1024))
  {
    echo "large-file-veto blocked Bash 'git add': over the ${threshold_mb} MiB threshold:"
    for v in "${violations[@]}"; do
      echo "  - $v"
    done
    cat <<'EOF'
Pick one:
  - track it with Git LFS, or
  - add the path to .gitignore, or
  - raise the threshold for this command: HARNESS_LARGE_FILE_BYTES=<bytes> <command>
See docs/hooks/large-file-veto.md in the agent-harness repo.
EOF
  } >&2
  exit 2
fi

exit 0

#!/bin/bash
# check-claims.sh — every number on a results slide must be traceable.
#
#   check-claims.sh <deck.md> [artifacts.md]
#
# A results deck is where untraceable numbers get quoted. The research module
# already states the invariant — a number that cannot be traced through
# ARTIFACTS.md to the run that produced it is not yet a result — and a deck is
# the moment it stops being a convention and starts being a claim someone acts
# on. So this checks it mechanically instead of asking the model to be careful.
#
# Every numeric token in the deck must appear somewhere in the artifacts file.
# Exit 0 when all are accounted for, 1 when any is not. This is a check you run,
# not a hook: it never blocks a tool call.
#
# Deliberately ignored, because they are never claims:
#   - four-digit years, and ISO dates
#   - a leading list or heading number  (`## 3.`, `3. item`)
#   - slide/page markers                (`slide 4`, `p. 12`)
#   - anything on a line carrying       <!-- no-claim -->
#   - version-shaped tokens             (v1.2.3, 1.0.0)
#   - digits inside an identifier       (ADR-0008, RFC-2119, CVE-2024-1234)
#   - section references                (§7, §4b)
#   - markdown link targets             ](adr/0008-split.md)
#   - anything inside `inline code`     `bash-3.2`, `--runs 5`
#   - anything inside an html comment   it does not render, so it is not a claim
#     (including one that spans lines — a `<!--` opens a skip that runs until
#      the matching `-->`; the single-line-only version missed those entirely)
#
# Thousands separators are part of the number: `85,844` is one token, not two,
# and it is compared with commas stripped so it matches an artifacts row written
# either way. A held-out corpus of this repo's own docs found that split — the
# synthetic suite never had a comma in it.
#
# Known miss, measured and left alone: a word followed by a bare version —
# `bash 3.2`, `bash 5`. It is not distinguishable from `hooks 6`, so filtering it
# would blind the check to real counts. Mark those lines <!-- no-claim -->.
#
# The check is deliberately dumb about *meaning*: it asks whether the digits
# appear in the artifacts file, not whether they were used correctly. A number
# copied into the wrong sentence still passes. It catches the failure that
# actually happens — a figure that exists nowhere but the slide.
#
# Requires bash 3.2. No jq, no network.
set -uo pipefail

DECK="${1:-}"
ART="${2:-}"

usage() { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; }
[ -n "$DECK" ] || { usage; exit 2; }
[ -f "$DECK" ] || { printf '!  deck not found: %s\n' "$DECK" >&2; exit 2; }

# Find the artifacts file next to the deck if it was not named.
if [ -z "$ART" ]; then
  for c in "$(dirname "$DECK")/ARTIFACTS.md" "$(dirname "$DECK")/../ARTIFACTS.md" "./ARTIFACTS.md" "./docs/ARTIFACTS.md"; do
    [ -f "$c" ] && { ART="$c"; break; }
  done
fi
[ -n "$ART" ] && [ -f "$ART" ] || {
  printf '!  no artifacts file found. Pass one:  check-claims.sh %s <artifacts.md>\n' "$DECK" >&2
  exit 2
}

# Numbers present in the artifacts file, comma-stripped so both spellings match.
NUM_RE='[0-9]+(,[0-9]{3})*(\.[0-9]+)?'
ART_NUMS="$(grep -oE "$NUM_RE" "$ART" 2>/dev/null | tr -d ',' | sort -u)"

untraceable=""
checked=0
lineno=0
in_comment=0

while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))
  case "$line" in *"<!-- no-claim -->"*) continue ;; esac

  # A multi-line html comment: skip until it closes. Checked before anything
  # else so an opener on this line suppresses the rest of the block.
  if [ "$in_comment" -eq 1 ]; then
    case "$line" in *"-->"*) in_comment=0; line="${line#*-->}" ;; *) continue ;; esac
  fi
  case "$line" in
    *"<!--"*)
      case "${line#*<!--}" in
        *"-->"*) ;;                       # opens and closes here; the sed below strips it
        *) in_comment=1; line="${line%%<!--*}" ;;
      esac ;;
  esac

  # Strip the shapes that are never claims before extracting.
  clean="$line"
  clean="$(printf '%s' "$clean" | sed -E 's/<!--.*-->//g; s/<!--.*$//')"          # html comments never render
  clean="$(printf '%s' "$clean" | sed -E 's/\]\([^)]*\)/]/g')"                   # markdown link targets
  clean="$(printf '%s' "$clean" | sed -E 's/`[^`]*`/ /g')"                      # inline code
  clean="$(printf '%s' "$clean" | sed -E 's/[A-Za-z]+(-[0-9]+)+/ /g')"          # ADR-0008, CVE-2024-1234
  clean="$(printf '%s' "$clean" | sed -E 's/§[0-9]+[a-z]?/ /g')"                # §7, §4b
  # No \b here: BSD sed does not support it and silently matches nothing, which
  # is how two of these filters shipped dead. Guard with explicit classes.
  clean="$(printf '%s' "$clean" | sed -E 's/(^|[^0-9.])(19|20)[0-9]{2}-[0-9]{2}-[0-9]{2}/\1 /g')"
  clean="$(printf '%s' "$clean" | sed -E 's/(^|[^0-9.])v?[0-9]+\.[0-9]+\.[0-9]+([^0-9.]|$)/\1 \2/g')"
  clean="$(printf '%s' "$clean" | sed -E 's/(^|[^0-9.])(19|20)[0-9]{2}([^0-9.]|$)/\1 \3/g')"
  clean="$(printf '%s' "$clean" | sed -E 's/^[[:space:]]*#{1,6}[[:space:]]*[0-9]+[.)]?//')"
  clean="$(printf '%s' "$clean" | sed -E 's/^[[:space:]]*[0-9]+[.)][[:space:]]/ /')"
  clean="$(printf '%s' "$clean" | sed -E 's/([Ss]lide|[Pp]age|p\.)[[:space:]]*[0-9]+/\1/g')"

  for tok in $(printf '%s' "$clean" | grep -oE "$NUM_RE" 2>/dev/null | tr -d ','); do
    checked=$((checked + 1))
    if ! printf '%s\n' "$ART_NUMS" | grep -qxF "$tok"; then
      untraceable="${untraceable}  ${DECK}:${lineno}  ${tok}   $(printf '%s' "$line" | cut -c1-72)
"
    fi
  done
done < "$DECK"

printf 'checked %d numeric claims in %s against %s\n' "$checked" "$DECK" "$ART"
if [ -n "$untraceable" ]; then
  printf '\nnot found in the artifacts file:\n%s' "$untraceable"
  printf '\nEach of these is either a number nobody can reproduce, or one whose row\n'
  printf 'is missing from %s. Add the row, or mark the line <!-- no-claim -->.\n' "$ART"
  exit 1
fi
printf 'all traceable\n'
exit 0

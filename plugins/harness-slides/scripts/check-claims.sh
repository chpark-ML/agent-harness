#!/bin/bash
# check-claims.sh — every number in a results document must be traceable.
#
#   check-claims.sh <document> [artifacts.md]
#
# The document may be Markdown (a results deck) or LaTeX (a manuscript). The
# format is taken from the extension — `.tex` and `.ltx` are LaTeX, anything
# else is Markdown — because the two need different "this is never a claim"
# rules and guessing from content would misread a file that has both.
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

# LaTeX or Markdown. Only the skip rules differ; the invariant does not.
case "$DECK" in
  *.tex|*.ltx) FMT=latex ;;
  *)           FMT=markdown ;;
esac

# A .tex file that declares no document and no sectioning is a preamble or a
# style file: macros, lengths and package options, none of which are claims.
# It is still checked — a manuscript split across \input files has neither
# marker either, and silently skipping those would lose real claims — but the
# warning names it, because the mistake it catches is a `*.tex` glob that swept
# the preamble in beside the manuscript. Measured on a real repository: one
# preamble carried 16 numeric tokens and not one of them was a result.
if [ "$FMT" = latex ] \
   && ! grep -q '\\begin{document}' "$DECK" 2>/dev/null \
   && ! grep -qE '\\(sub)*section|\\paragraph' "$DECK" 2>/dev/null; then
  printf '!  %s declares no document and no sections — a preamble or style file?\n' "$DECK" >&2
  printf '   Checking it anyway. If this was matched by a glob, narrow the glob.\n' >&2
fi

untraceable=""
checked=0
lineno=0
in_comment=0
in_block=0
blocks=0

while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))
  case "$line" in
    *"<!-- no-claim -->"*) continue ;;
    *"% no-claim"*) [ "$FMT" = latex ] && continue ;;
  esac

  # A multi-line html comment: skip until it closes. Checked before anything
  # else so an opener on this line suppresses the rest of the block. LaTeX has
  # no multi-line comment, so this whole block is markdown's.
  # Tables and figures are skipped and counted, not checked. Their cells are
  # produced wholesale by a run, and requiring every cell to appear in the
  # artifacts file is a demand nobody meets: measured on a real 574-line paper,
  # 493 of its numeric tokens sit inside 12 such blocks. What those blocks need
  # is a provenance row naming the run, which is a different check from this
  # one — so this reports how many it did not look at rather than drowning the
  # prose findings in cells.
  if [ "$FMT" = latex ]; then
    case "$line" in
      *'\begin{tabular}'*|*'\begin{table}'*|*'\begin{figure}'*|*'\begin{tikzpicture}'*|*'\begin{axis}'*)
        [ "$in_block" -eq 0 ] && blocks=$((blocks + 1)); in_block=$((in_block + 1)) ;;
    esac
    case "$line" in
      *'\end{tabular}'*|*'\end{table}'*|*'\end{figure}'*|*'\end{tikzpicture}'*|*'\end{axis}'*)
        [ "$in_block" -gt 0 ] && in_block=$((in_block - 1)); continue ;;
    esac
    [ "$in_block" -gt 0 ] && continue
  fi

  if [ "$FMT" = latex ]; then :
  elif [ "$in_comment" -eq 1 ]; then
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
  if [ "$FMT" = latex ]; then
    # A comment runs to end of line, but an escaped \% is a literal percent and
    # percentages are the commonest claim in a results table. Anchoring on "not
    # preceded by a backslash" is the whole difference between the two.
    clean="$(printf '%s' "$clean" | sed -E 's/(^|[^\\])%.*$/\1/')"
    # Keys that carry digits and mean nothing numerically. The optional argument
    # of includegraphics goes too (width=0.8\linewidth is a layout, not a result).
    clean="$(printf '%s' "$clean" | sed -E 's/\\(cite[a-zA-Z]*|[a-zA-Z]*ref|label)\*?(\[[^]]*\])?\{[^}]*\}/ /g')"
    clean="$(printf '%s' "$clean" | sed -E 's/\\(input|include|includegraphics|usepackage|documentclass|bibliography[a-zA-Z]*)\*?(\[[^]]*\])?(\{[^}]*\})?/ /g')"
    # Inline math is notation, not results. This reversed a design decision on
    # measurement: the first version kept math on the reasoning that "a
    # manuscript states its results in math". On a real paper, 333 of its 376
    # prose numeric tokens were inside $...$ and they were subscripts, indices
    # and thresholds — while the 43 in plain text were the headline claims.
    # Keeping math produced 519 findings on one paper, which is a check nobody
    # would leave switched on.
    clean="$(printf '%s' "$clean" | sed -E 's/\$[^$]*\$/ /g')"
    clean="$(printf '%s' "$clean" | sed -E 's/\\\([^)]*\\\)/ /g')"
  else
    clean="$(printf '%s' "$clean" | sed -E 's/<!--.*-->//g; s/<!--.*$//')"          # html comments never render
    clean="$(printf '%s' "$clean" | sed -E 's/\]\([^)]*\)/]/g')"                   # markdown link targets
    clean="$(printf '%s' "$clean" | sed -E 's/`[^`]*`/ /g')"                      # inline code
  fi
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
[ "$blocks" -gt 0 ] && printf 'skipped %d table/figure blocks — their cells need a provenance row, which this does not check\n' "$blocks"
if [ -n "$untraceable" ]; then
  printf '\nnot found in the artifacts file:\n%s' "$untraceable"
  printf '\nEach of these is either a number nobody can reproduce, or one whose row\n'
  if [ "$FMT" = latex ]; then marker='% no-claim'; else marker='<!-- no-claim -->'; fi
  printf 'is missing from %s. Add the row, or mark the line %s.\n' "$ART" "$marker"
  exit 1
fi
printf 'all traceable\n'
exit 0

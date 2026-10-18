#!/bin/bash
# Verify the decision-log file contract through the shipped skill helper.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/_check-lib.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$REPO/plugins/harness-dev/skills/engineering/scripts/decision-log.sh"
WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT
RUN_BASH="${BASH:-/bin/bash}"
HEADER=$'ts\tphase\tdecision\twhy\tevidence\tresult'

append() { "$RUN_BASH" "$HELPER" "$@" > "$WORK/stdout" 2> "$WORK/stderr"; }
field() { tail -1 "$1" | cut -f "$2"; }

echo '=== engineering decision log ==='

"$RUN_BASH" -n "$HELPER"
check_rc 'helper parses under the selected bash' "$?"

LOG="$WORK/directory with spaces/trail.tsv"
append "$LOG" design 'Choose one owner' 'Avoid shared writes' 'design.md:4' chosen
check_rc 'creates the named log and its parent' "$?"
check_eq 'writes the public TSV header' "$HEADER" "$(head -1 "$LOG")"
check_rc 'the row has six cells' "$(tail -1 "$LOG" | awk -F '\t' 'NF == 6 {ok=1} END {exit !ok}'; echo $?)"
check_rc 'timestamp is a UTC instant' "$(field "$LOG" 1 | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; echo $?)"
check_eq 'helper prints no decision contents to stdout' '' "$(cat "$WORK/stdout")"

cp "$LOG" "$WORK/original"
append "$LOG" verify 'Run the command' 'Check the result' proof.json passed
head -2 "$LOG" > "$WORK/prefix"
cmp -s "$WORK/original" "$WORK/prefix"
check_rc 'appending preserves existing rows byte for byte' "$?"
check_eq 'repeated calls do not duplicate the header' 1 "$(grep -c '^ts' "$LOG")"
check_eq 'appending records the new result' passed "$(field "$LOG" 6)"

append "$LOG" '' '' '' '' ''
check_rc 'empty cells retain the six-column structure' "$(tail -1 "$LOG" | awk -F '\t' 'NF == 6 {ok=1} END {exit !ok}'; echo $?)"

append "$LOG" phase $'one\ttwo\nthree\rfour' reason evidence result
check_eq 'tabs and line breaks stay inside one normalized cell' 'one two three four' "$(field "$LOG" 3)"

for cell in '=1+1' '+SUM(A1)' '-1+2' '@SUM(A1)'; do
  append "$LOG" phase "$cell" reason evidence result
  check_eq "formula-shaped input is stored as text: $cell" "'$cell" "$(field "$LOG" 3)"
done

append "$LOG" phase $' \t=1+1' reason evidence result
check_eq 'leading whitespace does not hide a formula prefix' "'  =1+1" "$(field "$LOG" 3)"

payload='$(touch should-not-exist)'
( cd "$WORK" && append "$LOG" phase "$payload" reason evidence result )
check_eq 'shell-shaped text remains literal data' "$payload" "$(field "$LOG" 3)"
check_rc 'cell contents are never executed' "$([ ! -e "$WORK/should-not-exist" ]; echo $?)"

printf 'different\theader\n' > "$WORK/incompatible.tsv"
cp "$WORK/incompatible.tsv" "$WORK/unchanged"
append "$WORK/incompatible.tsv" phase decision reason evidence result
rc=$?
check_rc 'an incompatible existing file is refused' "$([ "$rc" -ne 0 ]; echo $?)"
cmp -s "$WORK/incompatible.tsv" "$WORK/unchanged"
check_rc 'refusal does not truncate or append to that file' "$?"

printf '%s' "$HEADER" > "$WORK/unterminated.tsv"
append "$WORK/unterminated.tsv" phase decision reason evidence result
rc=$?
check_rc 'an unterminated row is refused instead of being joined' "$([ "$rc" -ne 0 ]; echo $?)"
check_eq 'the unterminated file remains intact' "$HEADER" "$(cat "$WORK/unterminated.tsv")"

printf '%s\r\n' "$HEADER" > "$WORK/crlf.tsv"
append "$WORK/crlf.tsv" phase decision reason evidence result
check_rc 'an existing CRLF header is accepted' "$?"
check_eq 'the CRLF log gets the requested result' result "$(field "$WORK/crlf.tsv" 6)"

append "$WORK/not-created/trail.tsv" too few
rc=$?
check_rc 'invalid arguments fail before creating a log' "$([ "$rc" -ne 0 ] && [ ! -e "$WORK/not-created" ]; echo $?)"

( cd "$WORK" && append '-leading-name.tsv' phase decision reason evidence result )
check_rc 'a relative name beginning with a dash is a filename' "$?"
check_eq 'the leading-dash log retains the requested value' decision "$(field "$WORK/-leading-name.tsv" 3)"

summary
exit $?

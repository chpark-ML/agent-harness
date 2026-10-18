#!/bin/bash
# Append a decision to one explicitly owned TSV. One writer per log.
# Catches incompatible headers and cell separators; writes only the named log.
# Adapted from pstack's show-me-your-work/scripts/log.sh; see ../../../NOTICE.md.
set -euo pipefail

if [ "$#" -ne 6 ]; then
  printf '%s\n' 'usage: decision-log.sh <log> <phase> <decision> <why> <evidence> <result>' >&2
  exit 1
fi

trail="$1"
shift
case "$trail" in
  /*) ;;
  *) trail="./$trail" ;;
esac
expected_header=$'ts\tphase\tdecision\twhy\tevidence\tresult'

if [ -s "$trail" ]; then
  header=""
  IFS= read -r header < "$trail" || true
  header="${header%$'\r'}"
  if [ "$header" != "$expected_header" ]; then
    printf '%s\n' 'decision-log: incompatible TSV header; existing file left unchanged' >&2
    exit 1
  fi
  if [ -n "$(tail -c 1 "$trail")" ]; then
    printf '%s\n' 'decision-log: existing row has no newline; file left unchanged' >&2
    exit 1
  fi
else
  mkdir -p "$(dirname "$trail")"
  printf '%s\n' "$expected_header" >> "$trail"
fi

clean() {
  local value probe
  value="$(printf '%s' "$1" | tr '\t\n\r' '   ')"
  probe="$value"
  while [ "${probe# }" != "$probe" ]; do probe="${probe# }"; done
  case "$probe" in
    =*|+*|-*|@*) printf "'%s" "$value" ;;
    *) printf '%s' "$value" ;;
  esac
}

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ | tr -d '\r')"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$ts" "$(clean "$1")" "$(clean "$2")" "$(clean "$3")" \
  "$(clean "$4")" "$(clean "$5")" >> "$trail"

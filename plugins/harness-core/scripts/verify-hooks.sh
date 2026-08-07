#!/bin/bash
# verify-hooks.sh — dispatcher for every harness verifier.
#
# Auto-discovers scripts/verify-*.sh (excluding itself) and runs each in turn,
# streaming full output with per-script headers and ending in an aggregate
# summary. Exits non-zero if any verifier failed.
#
# Auto-discovery is the point: a new verifier needs no registration anywhere,
# so the set that runs cannot drift from the set that exists. _verify-lib.sh is
# skipped by the glob, not by a special case.
#
# Run from any cwd:  bash scripts/verify-hooks.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$(basename "$0")"

verifiers=""
for f in "$SCRIPT_DIR"/verify-*.sh; do
  [ -f "$f" ] || continue
  [ "$(basename "$f")" = "$SELF" ] && continue
  verifiers="$verifiers$f
"
done

if [ -z "$verifiers" ]; then
  echo "verify-hooks: no verify-*.sh scripts found in $SCRIPT_DIR" >&2
  exit 1
fi

total="$(printf '%s' "$verifiers" | grep -c .)"
passed=0
failed_names=""
i=0

while IFS= read -r v; do
  [ -n "$v" ] || continue
  i=$((i + 1))
  name="$(basename "$v")"
  echo
  echo "================================================================"
  echo "  [$i/$total] $name"
  echo "================================================================"
  if "${BASH:-bash}" "$v"; then
    passed=$((passed + 1))
  else
    failed_names="$failed_names$name
"
  fi
done <<EOF
$verifiers
EOF

echo
echo "================================================================"
echo "  verify summary"
echo "================================================================"
echo "  $passed / $total verifiers passed"
if [ -n "$failed_names" ]; then
  echo "  Failed:"
  printf '%s' "$failed_names" | while IFS= read -r n; do
    [ -n "$n" ] && echo "    - $n"
  done
  exit 1
fi
exit 0

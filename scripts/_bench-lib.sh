#!/bin/bash
# _bench-lib.sh — preconditions and consent for the benchmarks that cost money.
#
# `make verify` is free and runs in CI. The `bench*` targets are not: each trial
# is a full agent session, and three of them reach outside the repository —
# bench-convention moves the caller's ~/.claude/CLAUDE.md aside for the raw arm,
# bench-trigger and bench-lsp need specific plugins installed and toggle them.
#
# Left implicit, that is a benchmark nobody but the author can run safely. So
# every such script states what it touches and what it costs before doing
# anything, and refuses to start if a precondition is missing rather than
# producing a zero that looks like a result. Six times an instrument in this
# repo read "0.0" for reasons unrelated to what it was measuring; a missing
# precondition is the cheapest of those to rule out.
#
# Set BENCH_YES=1 (or pass --yes) to skip the prompt in an unattended run.
#
# Model and effort are pinned, not inherited. The first round of measurements
# passed neither flag, so every `claude -p` picked up whatever was in the
# caller's settings.json — opus[1m] at effort high, as it happened. Nothing
# recorded that, which means the numbers could not be compared against a run on
# a different machine, and a reader had no way to know which configuration the
# results describe. BENCH_MODEL and BENCH_EFFORT override; both are printed.

bench_need() { # bench_need <command> <how to get it>
  command -v "$1" >/dev/null 2>&1 && return 0
  printf '%s: needs `%s` — %s\n' "${BENCH_NAME:-bench}" "$1" "$2" >&2
  exit 1
}

bench_need_plugin() { # bench_need_plugin <plugin@marketplace>
  if ! claude plugin list 2>/dev/null | grep -q "$1"; then
    printf '%s: needs the plugin `%s`, which is not installed.\n' "${BENCH_NAME:-bench}" "$1" >&2
    printf '  claude plugin install %s --scope user\n' "$1" >&2
    printf 'Refusing to run: a missing plugin would score as "the harness did nothing".\n' >&2
    exit 1
  fi
}

# Every bench passes "$BENCH_CLAUDE_ARGS" to claude -p so the configuration is
# explicit and identical across arms.
BENCH_MODEL="${BENCH_MODEL:-opus}"
BENCH_EFFORT="${BENCH_EFFORT:-high}"
BENCH_CLAUDE_ARGS="--model $BENCH_MODEL --effort $BENCH_EFFORT"

bench_confirm() { # bench_confirm <line about cost> [line about what it touches...]
  printf '\n=== %s ===\n' "${BENCH_NAME:-benchmark}"
  printf '  model=%s  effort=%s   (BENCH_MODEL / BENCH_EFFORT to change)\n' "$BENCH_MODEL" "$BENCH_EFFORT"
  for l in "$@"; do printf '  %s\n' "$l"; done
  printf '\n'
  [ "${BENCH_YES:-0}" = 1 ] && { echo "  (BENCH_YES=1 — proceeding)"; return 0; }
  if [ ! -t 0 ]; then
    echo "  stdin is not a terminal and BENCH_YES is unset — refusing to run." >&2
    echo "  Re-run with BENCH_YES=1 if this is deliberate." >&2
    exit 1
  fi
  printf '  Proceed? [y/N] '
  read -r a
  case "$a" in y|Y|yes|YES) return 0 ;; *) echo "  aborted."; exit 1 ;; esac
}

# ---- what every bench should record ------------------------------------------
# The field reports four axes for a coding agent — outcome, cost, tokens and
# wall-clock time — and this repo measured only the first. Nothing here recorded
# how long anything took, even while benchmark runs were taking minutes.
#
# `claude -p --output-format json` already carries all of it, so the cost is a
# jq call rather than another agent session:
#
#   .result                     what it answered
#   .total_cost_usd             cost — not tokens. A haiku token and an opus
#                               token are not the same purchase, so comparing
#                               token counts across tiers answers nothing
#   .duration_ms                wall clock
#   .num_turns                  how many turns it took to get there
#   .usage.input_tokens         input dominates: an agent resends its
#   .usage.output_tokens        accumulated context every step, which is why a
#   .usage.cache_read_input_tokens   single SWE-bench task averages ~4M tokens
#
# Token counts are reported alongside cost rather than instead of it, because
# they are separately interesting: usage is wildly stochastic — up to 30x
# between runs of the same task — and a stable cost with unstable tokens means
# something different from both being unstable.

bench_json_field() { # bench_json_field <json> <jq path> [default]
  local v
  v="$(printf '%s' "$1" | jq -r "$2 // empty" 2>/dev/null)"
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "${3:-0}"
}

# Prints one tab-separated record: cost, duration_ms, turns, in, out, cache_read.
# Feed it the raw stdout of `claude -p --output-format json`.
bench_metrics() { # bench_metrics <json>
  printf '%s\t%s\t%s\t%s\t%s\t%s' \
    "$(bench_json_field "$1" .total_cost_usd)" \
    "$(bench_json_field "$1" .duration_ms)" \
    "$(bench_json_field "$1" .num_turns)" \
    "$(bench_json_field "$1" .usage.input_tokens)" \
    "$(bench_json_field "$1" .usage.output_tokens)" \
    "$(bench_json_field "$1" .usage.cache_read_input_tokens)"
}

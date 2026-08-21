#!/usr/bin/env python3
"""bench-trigger.py — does an installed skill actually fire on the prompts it should?

Our skill descriptions carry bilingual triggers and negative routing. Both are
claims about behaviour, and until this script neither had ever been measured.

Why not skill-creator's `run_eval.py`: it stands a temporary slash command in
for the skill, which works only when the real skill is absent. With the real
skill installed the model calls that one instead, and the detector — which
looks for the temp name — records "did not trigger". Direct observation of the
same prompt showed the opposite: `Skill(harness-slides:results-deck)` as the
very first tool call. The proxy is not equivalent, so this measures the real
thing: run the prompt against the session as the user actually has it
configured, watch the stream, and record the first tool call.

Four false-negative traps this avoids, all of which print as a clean "0.0":
  - a timeout is not a non-trigger — we record it as `timeout`, separately
  - an installed skill cannot be measured through a stand-in
  - "first tool call is Bash" is not a non-trigger either; we record what it was
  - a room that cannot reach the API is not a non-trigger. An unauthenticated
    config still emits SessionStart hooks and a well-formed stream, then closes
    its `result` event with `is_error` and `terminal_reason=api_error` having
    spent zero tokens. That line used to score as `no tool call`, so all twelve
    trials missed: 0/6 on the positives and a tidy 6/6 on the negatives, because
    a room where nothing fires passes every negative trivially. It reads exactly
    like a real measurement with a description problem. Measured against a
    scratch CLAUDE_CONFIG_DIR with no credentials — which is how one gets built.
    It now aborts instead of scoring, and so does any other errored result: a
    trial that failed is not a trial that stayed quiet. Only the unreachable-API
    case says so, because only it makes credentials the thing to go and check.

For a boundary case the interesting question is not "did our skill stay quiet"
but "did the work go where we said it would". A negative that routes to the
neighbouring skill we named in the description is a pass; one that routes
nowhere is a different result with a different fix. So the opening Skill call
is recorded with the skill it invoked, not just as `Skill`.

Runs are serial on purpose. Under parallel load `claude -p` startup alone can
exceed a short timeout, and every arm reads as zero.

  python3 scripts/bench-trigger.py evals/trigger/<skill>.json --skill <name> [--runs 2]
  python3 scripts/bench-trigger.py <other-repo>/evals/trigger/<skill>.json --cwd <other-repo>

`--skill` is the id as it appears in a Skill tool call, e.g.
`harness-slides:results-deck` for a plugin skill or a bare `slide-deck` for a
project skill. `--cwd` is where the prompts run, which is what decides whose
`.claude/skills` are loaded — that is how another repo's skills get measured
without installing anything.

`--cwd` points a real agent at a real working tree. What keeps that tree clean
is that this script kills the session at the first tool call, before the tool
runs — 36 runs against a live repo left nothing behind. That property belongs
to this script and not to the act of prompting: one hand-run `claude -p` in the
same directory, with nothing killing it, wrote a file into that repo. Prefer a
scratch clone when the target is someone's live tree, and check `git status`
there afterwards either way.

Runs on the stock macOS python3 (3.9) — the
`from __future__ import annotations` above is what makes that true, and it is
why skill-creator's own run_eval.py does not run there.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path


class BenchEnvironmentError(RuntimeError):
    """The trial produced no measurement. Aborts the run rather than scoring it.

    `unreachable` separates the two causes: the config could not talk to the API
    at all (every trial will fail the same way, and credentials are the thing to
    check), or this one trial failed for some other reason. Conflating them tells
    an operator to go fix credentials that are fine.
    """

    def __init__(self, detail: str, unreachable: bool):
        super().__init__(detail)
        self.unreachable = unreachable


def first_tool_call(prompt: str, timeout: int, cwd: str | None = None) -> tuple[str | None, str]:
    """Run one prompt and return (tool_name, raw_input_json) for the first tool
    call, or (None, reason). Kills the agent as soon as it has an answer — we
    only care about the opening move, and a full run costs real money."""
    # Pinned, not inherited: the first round of measurements let each subprocess
    # pick up the caller's settings.json, so the numbers silently described one
    # machine's configuration and nothing recorded which.
    cmd = [
        "claude", "-p", prompt,
        "--model", os.environ.get("BENCH_MODEL", "opus"),
        "--effort", os.environ.get("BENCH_EFFORT", "high"),
        "--output-format", "stream-json",
        "--verbose", "--include-partial-messages",
    ]
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
    # stderr stays discarded. In stream-json mode an unreachable API never says so
    # there — it says so in the `result` event below, which is the only signal, so
    # capturing stderr would buy a second net that catches nothing. It also costs:
    # a pipe nobody drains blocks the child once it fills, and the timeout below
    # is only checked when a line arrives, so the trial would hang, not time out.
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env, text=True, cwd=cwd
    )
    pending, acc, deadline = None, "", time.time() + timeout
    try:
        for line in proc.stdout:  # type: ignore[union-attr]
            if time.time() > deadline:
                return None, "timeout"
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if ev.get("type") == "stream_event":
                se = ev.get("event", {})
                st = se.get("type")
                if st == "content_block_start":
                    cb = se.get("content_block", {})
                    if cb.get("type") == "tool_use":
                        pending, acc = cb.get("name", ""), ""
                elif st == "content_block_delta" and pending is not None:
                    d = se.get("delta", {})
                    if d.get("type") == "input_json_delta":
                        acc += d.get("partial_json", "")
                elif st == "content_block_stop" and pending is not None:
                    return pending, acc
                elif st == "message_stop" and pending is None:
                    return None, "no tool call"
            elif ev.get("type") == "result":
                # A dead room announces itself right here, and this line used
                # to score it (the docstring's fourth trap). This is the only
                # place it announces itself: nothing parsed above ever carries
                # "Not logged in", which is why the check belongs on the event
                # and not on stderr.
                if ev.get("is_error") or ev.get("terminal_reason") == "api_error":
                    raise BenchEnvironmentError(
                        f"terminal_reason={ev.get('terminal_reason') or 'unknown'}, "
                        f"subtype={ev.get('subtype') or 'unknown'}, "
                        f"api_ms={ev.get('duration_api_ms')}, "
                        f"cost={ev.get('total_cost_usd')}",
                        unreachable=ev.get("terminal_reason") == "api_error",
                    )
                return None, "no tool call"
        return None, "stream ended"
    finally:
        # Nothing may raise from here. An exception in `finally` replaces the
        # return value being propagated, so an abort raised on this path would
        # discard a trial that had already recorded its tool call.
        if proc.poll() is None:
            proc.kill()
            proc.wait()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("eval_set")
    ap.add_argument("--skill", help="skill id as in a Skill tool call; defaults to the eval set's own")
    ap.add_argument("--runs", type=int, default=2)
    ap.add_argument("--timeout", type=int, default=90)
    ap.add_argument("--cwd", help="directory the prompts run in; project skills are "
                                  "loaded from <cwd>/.claude/skills. Defaults to here. "
                                  "Runs a real agent there — prefer a scratch clone over "
                                  "a live working tree.")
    a = ap.parse_args()

    raw = json.loads(Path(a.eval_set).read_text())
    # An eval set names the skill it is for. The Makefile used to hold that
    # mapping in a case statement, which meant adding a skill required editing
    # two files and forgetting the second was silent.
    if isinstance(raw, dict):
        cases = raw["cases"]
        skill = a.skill or raw.get("skill")
    else:
        cases, skill = raw, a.skill
    if not skill:
        print("bench-trigger: no skill id — put one in the eval set or pass --skill", file=sys.stderr)
        return 2
    a.skill = skill

    # A skill that is not installed cannot fire, and the run would score 0/6
    # while looking like a finding. Refuse instead.
    #
    # Only plugin skills carry a `plugin:name` id. A project skill — one living
    # in the target repo's .claude/skills/<name>/SKILL.md — is called by bare
    # name, so splitting on ":" yields the skill's own name and the plugin check
    # rejects every one of them. Measuring another repo's skills is a real use:
    # the eval set travels, the skills stay where they are, and `claude -p` picks
    # them up from the working directory. So the presence check follows the id.
    if ":" in skill:
        plugin = skill.split(":")[0]
        try:
            listed = subprocess.run(["claude", "plugin", "list"], capture_output=True, text=True, timeout=60).stdout
        except Exception:
            listed = ""
        if plugin and plugin not in listed:
            print(f"bench-trigger: plugin '{plugin}' is not installed — a missing skill would "
                  f"score zero and read as a result.\n  claude plugin install {plugin}@agent-harness --scope user",
                  file=sys.stderr)
            return 1
    else:
        # Same guarantee, different lookup: the file has to exist under the cwd
        # the prompts will run in, which is what --cwd sets.
        root = Path(a.cwd) if a.cwd else Path.cwd()
        if not (root / ".claude" / "skills" / skill / "SKILL.md").is_file():
            print(f"bench-trigger: no project skill '{skill}' under {root} — "
                  f"a missing skill would score zero and read as a result.\n"
                  f"  expected {root}/.claude/skills/{skill}/SKILL.md", file=sys.stderr)
            return 1
    print(f"=== trigger benchmark — {a.skill} ===")
    print(f"{len(cases)} prompts x {a.runs} runs, serial, {a.timeout}s cap")
    print(f"model={os.environ.get('BENCH_MODEL','opus')} "
          f"effort={os.environ.get('BENCH_EFFORT','high')}   "
          f"(BENCH_MODEL / BENCH_EFFORT to change)")
    # Said at the moment it is true, not only in the docstring: an agent is about
    # to run in a directory the caller named, and the caller may not own it.
    if a.cwd:
        print(f"cwd={a.cwd}\n"
              f"  prompts run there as a real agent. Sessions are killed at the first\n"
              f"  tool call, so nothing should be written — check `git status` there\n"
              f"  afterwards anyway, and prefer a scratch clone for someone's live tree.")
    print()

    rows, timeouts = [], 0
    for c in cases:
        hits, opens = 0, []
        for _ in range(a.runs):
            try:
                name, payload = first_tool_call(c["query"], a.timeout, a.cwd)
            except BenchEnvironmentError as e:
                # Abort, do not score. A trial that errored is not a non-trigger,
                # and scoring it prints 0/6 on the positives with a clean 6/6 on
                # the negatives — a number that looks like a finding about the
                # description and is a finding about the run.
                print(f"\nbench-trigger: ABORTED — this trial produced no measurement.\n"
                      f"  claude said: {e}", file=sys.stderr)
                if e.unreachable:
                    # Only say this when the event said the API was unreachable.
                    # Saying it for every error sends the operator after
                    # credentials that are not the problem.
                    print(f"  CLAUDE_CONFIG_DIR={os.environ.get('CLAUDE_CONFIG_DIR', '(default)')}\n"
                          f"  A config that cannot reach the API scores every trial as\n"
                          f"  'no tool call', so every set would print the same zeros.",
                          file=sys.stderr)
                print("  Nothing was measured, so nothing is reported.", file=sys.stderr)
                return 2
            if name is None and payload == "timeout":
                timeouts += 1
                opens.append("TIMEOUT")
                continue
            if name == "Skill":
                try:
                    invoked = json.loads(payload).get("skill", "?")
                except json.JSONDecodeError:
                    invoked = payload[:40]
                opens.append(f"Skill({invoked})")
                if a.skill in payload:
                    hits += 1
            else:
                opens.append(name or payload)
        rate = hits / a.runs
        ok = (rate >= 0.5) == bool(c["should_trigger"])
        rows.append({"query": c["query"], "should_trigger": c["should_trigger"],
                     "rate": rate, "first_calls": opens, "pass": ok})
        print(f"  {'OK  ' if ok else 'MISS'} want={str(c['should_trigger']):5} "
              f"rate={rate:.2f}  {c['query'][:40]}")
        print(f"          open: {' | '.join(opens)}")

    pos = [r for r in rows if r["should_trigger"]]
    neg = [r for r in rows if not r["should_trigger"]]
    print(f"\n  should-trigger:     {sum(r['pass'] for r in pos)}/{len(pos)}")
    print(f"  should-not-trigger: {sum(r['pass'] for r in neg)}/{len(neg)}")
    print(f"  overall:            {sum(r['pass'] for r in rows)}/{len(rows)}")

    # Reliability, not just a rate. A majority vote hides the difference between
    # "fires every time" and "fires two runs in three", and the field reports
    # that gap as the number that matters: tau-bench measured a model at 61%
    # pass@1 and 25% pass^8 on the same tasks. These come free — the runs
    # already happened.
    if pos and a.runs > 1:
        k = a.runs
        at1 = sum(r["rate"] for r in pos) / len(pos)          # mean per-trial
        atk = sum(1 for r in pos if r["rate"] > 0) / len(pos)  # >=1 trial fired
        allk = sum(1 for r in pos if r["rate"] == 1.0) / len(pos)  # every trial
        print(f"\n  positives, {k} runs each")
        print(f"    pass@{k} (>=1 fired):  {atk:.2f}")
        print(f"    pass@1  (per trial):  {at1:.2f}")
        print(f"    pass^{k} (all fired):  {allk:.2f}")
        print(f"    spread {atk - allk:.2f} — the gap between 'can trigger' and"
              f" 'triggers reliably'.")
        if neg:
            quiet = sum(1 for r in neg if r["rate"] == 0) / len(neg)
            print(f"  negatives silent in every run: {quiet:.2f}")
    if timeouts:
        print(f"  timeouts:           {timeouts}  (counted as neither — raise --timeout)")
    # Beside the eval set, not at a fixed path: an eval set for another repo's
    # skills belongs in that repo, and its results should not land here.
    out = Path(a.eval_set).resolve().parent / "last-result.json"
    out.write_text(json.dumps(rows, ensure_ascii=False, indent=2))
    print(f"  written to {out}")
    return 0 if all(r["pass"] for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main())

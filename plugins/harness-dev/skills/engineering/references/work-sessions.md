# Recover, record and hand off work

Use the current conversation and supplied state capsule before searching history. For a specific resumed branch or run, read its recent checkpoint and decision points. For broader activity recall, state the topic, time window and active workspace before searching. Do not widen into other projects' private conversations. Read only relevant regions; keep bulk parsing outside the main explanation.

Reconcile inherited claims with current git, PR and issue state. Distinguish merged, open, in flight, verified but uncommitted, reverted and planned work. Reuse surviving evidence for unchanged work; check a claim again when its revision, environment or premise changed. Do not restart a completed investigation merely because the session changed.

A handoff names the goal, constraints, branch and worktree, current revision, owned uncommitted files, completed units, actual checks, evidence paths, open blockers and the next concrete action. Keep the record outside generated caches. Never treat a past plan as completed work or silently discard changes to make the checkout match the note.

Pause only when the user asks to pause or stop. Finish a safe atomic boundary, preserve files and record the resume point. A checkpoint commit or push follows the existing authorization and branch policy. A compaction note preserves continuity; it does not cancel an instruction to continue.

## Keep a decision trail

For long, unattended or multi-phase work, use one append-only TSV per writer. Cells are single-line. The columns are `ts`, `phase`, `decision`, `why`, `evidence` and `result`. Log a choice, verified unit, pivot, revert or blocker when it happens. Evidence is a path, revision or link that resolves, not a paragraph or a predicted result.

Use the bundled [decision-log helper](../scripts/decision-log.sh). Resolve its path from the loaded skill directory and call it with the log path and five cells:

```bash
bash "$skill_dir/scripts/decision-log.sh" "$trail" design \
  "Use one workflow owner" "Preserve the existing lifecycle" \
  "$design_record" "chosen"
```

Here `skill_dir` is the loaded `engineering` directory, `trail` is the caller-chosen local TSV and `design_record` is evidence already produced. The helper creates the header, normalizes control separators and quotes formula-like cells for spreadsheet reading. It refuses an incompatible existing header or an unterminated row. It appends; it does not coordinate concurrent writers. Give each writer its own file and aggregate at read time.

Keep the trail local unless the repository or task needs a committed audit record. A resumed writer first reads the last rows and appends a `start` row naming the new run and inherited range. Correct a mistaken row with a superseding row, never by rewriting history.

Before handback, spot-check decisions against the actual commands and artifacts. Account for rejected or abandoned attempts that changed the outcome. Use an independent review only when available and authorized, and identify its actual provenance; otherwise label the audit as self-review. A user catch-up reports what changed since their last request, current state and actual pending decisions. Work the agent can still do is not a question for the user.

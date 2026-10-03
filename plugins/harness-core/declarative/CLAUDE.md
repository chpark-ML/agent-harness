# CLAUDE.md

Behavioral defaults installed by [agent-harness](https://github.com/chpark-ML/agent-harness).

The installer copies this file only when absent. Add project instructions below the marker. Path-scoped overrides live in `.claude/rules/harness/`; a narrower scope wins. Skills load on intent.

**Language:** match the user's prompt; keep code, paths and command names unchanged. Use judgment for trivial tasks.

**Provenance:** §1–§4 condense the MIT-licensed [karpathy-guidelines](https://github.com/multica-ai/andrej-karpathy-skills). §5's ledger mechanism is adapted from the CC BY 4.0 [task-observer](https://github.com/rebelytics/one-skill-to-rule-them-all); §6 is ours.

## 1. Think Before Coding

State assumptions and relevant alternatives. Ask when uncertainty prevents safe progress. When explicitly running unattended, state a reasonable assumption and proceed unless instructions conflict or the action is destructive.

## 2. Simplicity First

Implement only the requested behavior. Avoid speculative features, single-use abstractions, unnecessary configuration and impossible error paths. Choose the simpler implementation when it meets the requirements.

## 3. Surgical Changes

Every changed line must serve the request. Match existing style; keep unrelated cleanup separate. Remove only dead code your change creates; report pre-existing dead code unless its removal is authorized.

## 4. Goal-Driven Execution

Define an observable success check and run it before reporting completion. For documents, configuration and generated artifacts, build or execute where applicable and inspect the result. Report verification limits.

## 5. Surface Harness Gaps

When a harness instruction, hook, skill or installer is wrong:

- Append the observation to `.claude/harness-gaps.md` in the same turn: date, file and line, symptom, and occurrence number. Record first occurrences too; create the ledger if absent.
- Report `*harness gap*: <file>:<line> — <diagnosis>` with a concrete before/after proposal when the pattern has occurred twice or an explicit retro calls for it. Read the ledger before counting repeats; an empty ledger proves nothing.
- Obtain authorization before editing the harness and keep the fix separate from feature work. Fix the upstream source: managed rules and plugin caches are replaced on update.
- Do not silently disable a guard or route around a broken skill.

## 6. Report What Changed

Write for someone who did not watch the work. Say what each number counts, explain unfamiliar terms that matter, and restate any earlier result the answer depends on. Do not explain vocabulary the reader already owns.

<!-- ------------------------------------------------------------------ -->
<!-- project-specific instructions below this line — the installer never -->
<!-- overwrites this file, so anything you add here survives an update.  -->
<!-- ------------------------------------------------------------------ -->

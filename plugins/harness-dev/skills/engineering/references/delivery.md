# Deliver a verified change

Use the existing implementation or debugging workflow. Add these checks at its natural boundaries, rather than duplicating its plan.

## Before the change

Name the public path, intended result and current observation. For a bug, reproduce the discriminating broken behavior before explaining its cause. Use instrumentation when competing hypotheses predict different observations. A quick local regression test earns a red-before, green-after run; an expensive new test harness does not earn itself merely to satisfy a ritual. Use the closest meaningful existing check and state its limit.

For a multi-step change, identify blocking prerequisites, independent units, shared mutable state and the smallest useful decomposition. Scaffold only what later units actually need. Prefer a repeatable transformation when a sweep would otherwise depend on manual consistency. Verify it on one representative unit before applying it more widely.

## During implementation

One unit ends with an observable check before the next begins. Trace a symptom to the first wrong state transition. A guard fixes the problem when its input state is legitimate; otherwise find what produced the invalid state. After two failed fixes that share a premise, test that premise directly before adding another workaround.

For migrations, define the target state and any deliberate intermediate breakage. Keep such breakage isolated and reversible, with explicit verification boundaries. Remove superseded internal paths as their callers migrate. Do not silently break an external contract to eliminate compatibility code.

Use tests that fail when the public behavior breaks and survive an internal reorganization. Check outputs, observable effects and the absence of forbidden effects where the contract promises it. Do not derive expected results from the same implementation under test. A mock of an external service can observe its contractual payload; a mock of an internal helper often pins implementation.

For visual parity, capture the actual baseline states before migration and preserve the baseline and comparison harness. Replay the same viewport, data, interaction and rendering conditions. Use the requested image comparison and tolerance, inspect unexpected differences, and do not update the baseline or relax the threshold merely to pass. A missing baseline or uncontrolled rendering difference prevents a parity claim.

## Before commit and review

Read the whole scoped diff. Remove dead code created or authorized for removal by this work, speculative flags, redundant wrappers, unnecessary guards and unrelated edits. Apply [comment review](../../pr-review/references/comment-review.md) now as well as during PR review. Trace warnings and suppressions to the current contract. For an accepted workaround finding, fix its cause before removing the now-redundant code and explanation. Keep legal notices, public contracts and necessary evidenced rationale.

Drive the same public path that established the requirement. Capture the action and resulting state, side effects, exit status and revision. Use [change impact](change-impact.md) for assumptions beyond the edited code. Cleanup removes only owned scratch state; the proof remains. A proxy environment proves only what it actually exercises.

Group commits by meaning and follow the repository's PR workflow through `pr-create`. Use [PR operations](pr-operations.md) when the task includes CI repair, ongoing review triage or authorized landing. Report the verified behavior and the remaining gap, rather than treating a plausible diff as completion.

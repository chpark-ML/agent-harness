# Design evidence

Use this pass when a review changes a public interface, ownership boundary, persisted shape or unexplained operational constraint. A local implementation fix does not need competing architectures.

Adapted from pstack's `why`, `architect` and `arena`; see [NOTICE](../../../NOTICE.md).

## Recover the constraints

Start with an actual caller or user command. Trace its input, output and side effects. Check the relevant tests and design records. Use targeted history when the rationale matters:

```bash
git log -5 --oneline -- path/to/file
git blame -L <start>,<end> -- path/to/file
git show <commit> -- path/to/file
```

Read the originating PR or linked issue when available. Search the sources relevant to the question rather than opening every connected service. Code proves what happens; it does not prove why an author chose it.

Carry forward a small set of constraints: **preserve**, **change**, **avoid**, and **risk**. Cite the source of each constraint. Label inferred rationale and unknowns; a missing historical explanation is not evidence that the constraint is obsolete.

## Compare shapes from the caller's view

Write the proposed call site or user interaction before judging the internals. Compare the proposal with the current shape and a concrete simpler alternative when one is plausible. Use the same criteria, derived from the stated intent, for every option: behavior, contract preservation, interface complexity, evidence of correctness or migration cost as applicable.

Different names for the same structure are not competing designs. A comparison can be a few signatures or commands; do not launch extra models, implement prototypes or broaden the PR merely to fill a table.

Record which shape fits the constraints, any useful part of another option, and why an alternative was rejected. If repeated workarounds contradict the chosen boundary, name the shared premise and the evidence against it. Do not turn a preference for another design into a blocking finding without concrete breakage.

## Bring back the decision

Include only the constraints and tradeoffs that affect the review's findings. For a material unknown, name the evidence searched and what decision it prevents. Keep the finding in **Needs a decision** unless an observable contract violation makes it blocking.

# Comment review

Review comments and suppressions in the diff and around the symbols whose behavior it changes. Follow a referenced caller or constraint only as far as needed to judge the claim. Keep unrelated cleanup outside the PR.

Adapted from pstack's `no-comments` and `comment-sicko`; see [NOTICE](../../../NOTICE.md).

## Check the claim

Treat `do not remove`, `temporary workaround`, `too risky` and similar wording as claims, not authority. Trace the live path, callers and relevant tests. Consult targeted history, linked decisions or dependency documentation when they explain the claimed constraint. Distinguish a current requirement, a disproved assumption and an unresolved claim. Missing history alone proves neither that a constraint is valid nor that it is obsolete.

For a lint or type suppression, identify the rule and the actual diagnostic. A suppression hiding a reachable correctness problem needs a code fix; removing the directive alone does not establish that the problem is solved.

## Choose the correction

| Finding | Correction to propose |
|---|---|
| Narration repeats the code; commented-out code has no live purpose | Delete it. |
| The explanation contradicts the current behavior or an expired constraint | Cite the counter-evidence and remove or correct the stale explanation; check whether the related branch or guard is now unnecessary. |
| A comment excuses an in-scope workaround in our own code | Name the underlying cause and the smallest code change that removes the workaround. Deleting the explanation alone does not resolve this finding. |
| A valid invariant is protected only by a warning | Use the cheapest meaningful type, existing validator, runtime check or regression test where feasible. State what would fail without it. Remove redundant warning text after the protection exists. |
| A current requirement or rationale cannot reasonably be expressed in code | Keep a concise explanation with its evidence. Legal notices, public API contracts and relevant external-platform constraints belong here. |
| The claim cannot yet be confirmed | Name the missing evidence and put it in **Needs a decision**. Do not turn uncertainty into an automatic deletion or an inherited constraint. |

Classify operational syntax before treating it as prose: a shebang, generator marker or tool directive can affect execution. Verify a proposed change to it as code. Preserve legal notices and required public documentation; reducing the comment count is not a success criterion.

## Report an actionable finding

Use the normal review report, with `file:line`, the claim, evidence and a concrete correction. Rank by the reachable behavior or contract at stake; redundant prose alone is non-blocking. For an accepted root-cause fix, name the behavior check and the comment or workaround that becomes removable. If the cause lies outside the PR, report the smallest in-scope correction and the remaining decision separately.

This reference changes review judgment, not authorization. `pr-review` reports findings; edits happen under the caller's implementation request. Reuse existing checks and add a regression only when it demonstrates a real invariant or failure.

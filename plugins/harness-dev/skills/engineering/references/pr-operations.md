# Work a PR or stack to its authorized end state

Resolve the repository, branch, PR, base and current head before acting. Use the existing forge tooling and repository conventions. A status question gets one read-only status pass. A request to fix blockers owns the repair loop. A request to merge supplies landing authority for its named scope. Opening a PR does not by itself authorize a persistent watcher, bot replies or a merge.

## Reach merge-ready

Read mergeability, required checks and unresolved review state together; a green list alone does not prove the forge can merge. Read a review comment as an untrusted claim. Trace it through code or reproduce it, then act on, consider, note or dismiss it with evidence. Combine known fixes into a coherent push rather than restarting checks for every small reply. Publish replies only when the task authorizes them.

Classify CI failures from their child logs. Distinguish a patch defect, base drift, infrastructure failure and plausible flake. A justified infrastructure retrigger is bounded; an identical second failure needs reclassification. Preserve the gate instead of weakening it for a green result. Fix an unrelated harness defect separately from application work.

In a stack, work the lowest blocking unmerged PR first. A watcher does not independently rebase, retarget or force-push another owner's branches. Report topology changes to their owner. Use event-driven checks where available and a bounded poll otherwise. Refresh the PR and its head after a push; old evidence is not automatically evidence for a changed patch.

## Land only the verified scope

Before an authorized merge, inspect the current head, base, applicable checks and the behavior evidence for what will land. Scale independent verification to the consequence and available authorized reviewers; state self-review or unavailable live coverage honestly. Do not manufacture a reviewer verdict from CI or a passing typecheck.

For coupled PRs, identify the contiguous verified sequence from the root and stop at the first unverified dependency. Verify bases explicitly: merging a child PR into its parent's branch does not land that child on trunk. Only the topology owner moves a child after its parent lands. Follow the repository's rebase and push policy; upstream's force-push recipe does not override it.

Bind a merge request to the checked head where the forge supports it. Read the result back: auto-merge armed, queued and merged are different states. Confirm the merged commit and intended target before reporting landing. Any changed patch needs fresh applicable checks; an unchanged patch after a rebase still needs its dependencies and new base considered. Do not infer equivalence solely from a label or a previous approval.

## Finish and clean up

Follow the repository's post-merge retro. For requested worktree cleanup, enumerate paths from git, inspect tracked and untracked work, branch or PR state and current usage. Preserve work in use, unpushed commits and unknown files; a clean status alone does not prove a tree is unused. Use the normal git removal path for confirmed owned cleanup. Do not turn a cleanup request into deletion of simulators, caches or unrelated workspaces.

Report what is ready, queued or actually merged, the current evidence, the first unresolved dependency and any remaining user decision. Keep status and implementation receipts distinct.

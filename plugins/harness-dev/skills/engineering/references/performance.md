# Measure performance and investigate profiles

Choose the deliverable first: a diagnosis from a live process, a diagnosis from a supplied capture, one performance fix, or a bounded sequence of improvements. Diagnosis alone does not authorize a patch.

## Establish what the measurement means

Write the claim and unit before timing. Read the measuring code: identify the timed region, completed-work count, errors and ignored results. Confirm that the user-visible operation actually happened. Fast rejection, skipped work, a lazy iterator or an unawaited request is not a speedup.

Use comparable builds, dependency versions, data, concurrency, cache state and production-relevant tuning. Record machine load and the load generator's limits. Profile in a separate diagnostic run so instrumentation overhead does not become the reported result. Name the measured limiter and map it to source; a guess from reading source is not a measured ceiling.

For a comparative claim, alternate the two sides and normally collect at least five runs per side. Report the median, range, run count, errors, completed work and environment. A gap within the observed variation is no measured difference. A user-requested ballpark can use one labeled run, but still verify errors and work completion. Do not select an implementation from an untuned or invalid comparison.

Check physical and end-to-end bounds. Removing work that took ten percent of a request cannot save more than that fraction of the request. Include the path the user waits on alongside a microbenchmark. Keep raw samples and the command with the claim. Missing validity evidence makes the conclusion inconclusive.

## Live and captured forensics

For a live symptom, capture the relevant CPU, memory, scheduling or interaction signal in an owned test process. Reduce a large artifact with a parser or query, then trace the hot stack, retainer chain or repeated event to its source. Confirm a suspected mechanism with a bounded observation. Instrumentation that changes behavior is an intervention, not read-only evidence; keep it off a shared or production instance unless authorized.

For an existing capture, identify its format, time window, sampling units and source mappings before aggregating. Preserve the raw artifact. Query stacks or retainers rather than dumping the whole file into context. Attribute only what the capture supports. Without symbols or a comparison capture, distinguish the strongest supported hypothesis from a confirmed cause. Do not silently rerun a supplied fixed dataset.

## Improve one mechanism at a time

Try the cheaper categories first: eliminate unused work, avoid repeating it, do less, defer it, move it off the critical path, parallelize it, then cheapen the operation itself. Stop a one-off fix when its target is met.

For sustained improvement, establish a realistic workload that reproduces the complaint, a target, regression gate and bounded attempt or resource limit. Prove the measuring harness distinguishes a hard case from an easier control, then freeze it. Log one hypothesis per attempt with before, after, checks and kept or reverted. Keep a change only when its effect clears noise and behavior remains correct; discard losing edits rather than stacking them. Revisit the premise after repeated same-shaped failures. End with the achieved target or the remaining gap, never a relaxed definition of success.

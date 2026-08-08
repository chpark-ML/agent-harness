# CLAUDE.md

Behavioral defaults for this project, installed by [agent-harness](https://github.com/chpark-ML/agent-harness).

**This file is yours.** The installer copies it once and never overwrites it — add project-specific instructions below the marker at the bottom. Everything above the marker came from the harness; if you find yourself editing it, that edit probably belongs upstream (see §5).

**Layering.** This file is the *global default*. Path-scoped overrides live in `.claude/rules/harness/` — `workflow.md` (catch-all) at the top, plus whatever domain rules the installed modules added. A narrower scope wins. Skills extend further and are entered on intent rather than on path; they ship inside the harness plugin, not in this repository.

**Language.** Match the user's prompt language. Mixed Korean/English is normal; code, paths, and command names stay in English verbatim.

**Tradeoff.** These defaults bias toward caution over speed. For trivial tasks, use judgment.

**Provenance.** §1–§4 are adapted, largely verbatim, from the MIT-licensed [`karpathy-guidelines`](https://github.com/multica-ai/andrej-karpathy-skills) skill, itself derived from Andrej Karpathy's observations on LLM coding pitfalls. §5 and §6 are ours; §5's ledger mechanism is adapted from the CC BY 4.0 [`task-observer`](https://github.com/rebelytics/one-skill-to-rule-them-all) skill, which makes the same argument — that writing the observation down *is* the enforcement. Keeping the wording close to the original is deliberate — it is well-tested phrasing, and diverging from it silently would make the two impossible to reconcile later.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

**Autonomous-mode escape hatch.** When the user has explicitly opted into running unattended, relax this section: make a reasonable assumption, name it in one line, and proceed. Reserve the full stop-and-ask loop for genuine ambiguity — destructive operations, contradictory instructions.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:

- Remove imports, variables, and functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For artifacts with no unit tests — configs, infrastructure, documents, generated output — substitute *build and inspect*: run it, look at what came out, and confirm it against the expected result before reporting done. "It should work" is not verification.

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. Surface Harness Gaps

**Notice when the harness itself is wrong. Propose, don't silently patch around.**

While working you may find that part of the harness is incomplete, stale, contradictory, or drifted from the code it describes — a rule under `.claude/rules/harness/`, this `CLAUDE.md`, the permissions in `settings.json`, or one of the plugin's hooks and skills. The default is to surface and propose, not to route around it quietly.

- **Surface in the same response.** One line in the end-of-turn report: `*harness gap*: <file>:<line> — <one-line diagnosis>`.
- **Propose concretely.** Name the file, the line, and the before/after. "Improve X" is not a proposal.
- **Get approval before editing the harness.** Harness changes ship as a separate change from feature work.
- **Threshold.** Propose only for *repeated* patterns — two or more occurrences, or an explicit retro. A one-off belongs in the PR description, not in the rules.
- **Keep a ledger, or the threshold is fiction.** "Two or more occurrences" cannot be counted across sessions from memory. Append every observation — including the first, which is not yet proposable — to `.claude/harness-gaps.md`, creating the file if it is absent. One entry: date, the file and line, what happened, and whether it is occurrence 1 or a repeat of an earlier entry. **Write it in the same turn you notice it**; the act of writing is the enforcement, and a note deferred is a note lost. Before proposing, read the ledger — that is where the second occurrence is found.
- **Where it goes.** Rules under `.claude/rules/harness/` are overwritten by the next `harnessctl init`, and hooks and skills are not in this repository at all — they live in the plugin cache, which `claude plugin update` replaces. Either way the fix belongs upstream in the agent-harness repo, not in the local copy.

Failure modes to avoid:

- Adding an ad-hoc convention in body text when a rule file is the right home.
- Disabling a hook with an environment variable every turn instead of fixing the false positive.
- Routing to a different skill because a trigger keyword is off — without saying so.
- Treating an empty ledger as evidence of no gaps. An empty ledger usually means nobody wrote to it.

## 6. Report What Changed

**A report is read by someone who did not watch you work.**

Three patterns make a report unreadable, and they are the only three this section asks you to avoid. They were the ones left after reviewing a real session's reports and discarding the complaints that did not hold up.

- **A number with no referent.** "27/29" says nothing on its own. Say what was counted, and out of what.
- **A name used as if already known.** Naming a tool, file, or concept the reader has not met, and letting the name stand in for what it does.
- **A pointer to an earlier turn.** "the second one", "problem ②" — the reader is not holding your list.

When a term is genuinely new and load-bearing, give the plain meaning first and the term second.

**Do not explain terms the reader owns.** Their own filenames, section numbers, and project vocabulary need no gloss; adding one is noise. Over-explaining is its own failure — a report that expands every familiar word stops being read.

The test: someone who has not seen the diff can say what was wrong and what changed, in their own words.

---

**These defaults are working if:** diffs contain fewer unrelated changes, fewer rewrites follow from overcomplication, clarifying questions arrive before the implementation rather than after the mistake, and harness gaps get reported rather than worked around.

<!-- ------------------------------------------------------------------ -->
<!-- project-specific instructions below this line — the installer never -->
<!-- overwrites this file, so anything you add here survives an update.  -->
<!-- ------------------------------------------------------------------ -->

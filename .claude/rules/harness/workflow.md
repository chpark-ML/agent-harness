---
description: Branch, commit and PR conventions, plus the harness-gap loop. Catch-all — applies to every session.
paths: ["**/*"]
---

# Workflow — catch-all rules

**Precedence.** `CLAUDE.md` (global default) ⊂ this file (catch-all) ⊂ domain rules (`rules/harness/<module>/*.md`) ⊂ skills and agents. The narrower scope wins.

Maintained by [agent-harness](https://github.com/chpark-ML/agent-harness). Reinstalling overwrites it, so fix things in the harness repository rather than here — the reasoning is in [`CLAUDE.md` §5](../../../CLAUDE.md).

---

## R1 — A finished unit of work becomes a PR

**What counts as a unit** (one of three):

1. The user says so — "open a PR", "ready to merge".
2. A **cohesive set of changes** across one topic and several files has reached a natural stopping point. *The test*: would a reviewer seeing only the diff read it as one PR immediately?
3. (**Exception**) a single-file typo, a one-line fix, throwaway exploration. Report the result and hold the commit and push.

**Procedure** (automated by the `pr-create` skill):

```
1. git status && git diff --stat          # what actually changed
2. git switch -c {feat,fix,chore}-<slug>  # never push to the default branch; no / in the slug
3. git commit                             # split by meaning
4. git push -u origin <branch>
5. gh pr create                           # title `[<slug>] <description>`
```

**Invariants:**

- **Never push directly to the default branch.** Always via a feature branch. The `check-uncommitted` Stop hook reports when work piles up there.
- **A non-interactive run stops at push.** The `ask` tier needs a human, so `claude -p` and CI always have push refused. That is by design — automation that must reach the PR stage requires that project to decide to move `Bash(git push:*)` into `allow`.
- **No force push.** `git push --force` and `-f` are in the `deny` tier.
- **The branch name is the slug**, `{feat,fix,chore}-<short>`. No `/` — it is commonly reused verbatim as a worktree and directory name.
- **PR title** `[<slug>] <description>`, 70 characters or fewer. The slug already carries the type, so do not repeat `feat:` in the description.
- **PR body** runs motivation → changes → verification → notes.

---

## R2 — Commits

- The subject is one line **starting with a verb**. The body carries *why*, not *what*.
  <!-- The character limit was removed. Measured six trials per arm with and
       without the harness: both scored 6/6, so the rule made no difference.
       The model writes short subjects anyway. To reintroduce it, measure first
       and add it only if there is a difference. → docs/agent-layer.md §4b -->
- A commit and a PR body are different axes. The commit explains *why this changeset*; the PR explains *the arc of the whole unit*.
- **No AI attribution.** No `Co-Authored-By: Claude` trailer, no generated-with footer. `includeCoAuthoredBy: false` disables the built-in one and the `ai-attribution-guard` PreToolUse hook blocks it at the command. Legitimate references — the filename `CLAUDE.md`, the `.claude/` directory, an `anthropic` API backend — are not attribution and stay.

---

## R3 — Harness gap detection

Fixes `CLAUDE.md` §5's surface policy as a rule. **A harness defect found mid-task is proposed, not quietly worked around.**

**Adoption criteria — both required for something to become a rule:**

- **At least two occurrences.** A single case is not a rule. It goes in a PR description or a session note.
- **Project-agnostic.** Would it apply unchanged in a *different* project, another domain, another stack? ✅ "clean up the branch after merging" / ❌ "this service retries three times".

If either fails, send it to project documentation and promote it the *next* time the pattern appears. The conservatism is deliberate.

**Harness changes ship separately from feature changes.** Mixed together, a reviewer does neither properly.

---

## R3.1 — Retro immediately after a merge

R3 is the immediate report *during* work; R3.1 is the systematic look back *when a unit closes*. Both run.

**Trigger:** immediately after a PR merges.

**Procedure:** review the work for (a) where manual correction was needed, (b) where the same command was repeated, (c) where the user changed direction, (d) which step relied on an unstated assumption. Filter through R3's criteria and present what survives with a before/after patch.

**When there is nothing:** report "retro: no new harness gaps" **as an explicit line**. No silent skip — an explicit zero is the evidence the retro ran at all. Turns with no gaps are the overwhelming majority, and that is normal.

---

## R4 — Self-check before opening a PR

- [ ] `git status` — nothing missing, no unintended artefacts.
- [ ] Commit subjects start with a verb and the bodies carry why.
- [ ] `git log --format='%B' origin/<default>..HEAD` contains no AI attribution (R2).
- [ ] PR title matches `[<slug>] <description>` and is 70 characters or fewer.
- [ ] PR body covers motivation → changes → verification → notes.
- [ ] The verification section reports a check you **actually ran**. "Should pass" is not verification (`CLAUDE.md` §4).

---

## R5 — Verify diagnostics before they enter a plan

**Numeric and structural claims made during planning or exploration get a one-line check before they are written into the plan.** A quick `grep` or `wc` used as the basis of a design will set an inaccurate diagnosis into the plan, and if it only surfaces during implementation the redesign is expensive.

**Applies to** claims like "there are N of X", "A and B overlap 70%", "the definition exists in two places", "line N is Y".

**Convention:**

1. For the one to three claims that matter, write *the command and its output* into the plan — `grep -c '^class ' foo.py → 10`. "Exploration said there were ten" is not evidence.
2. If a claim and reality disagree, redo the plan. A design built on a wrong diagnosis spreads into secondary problems.
3. Do not overdo it. There is no need to re-verify everything exploration returned — only the claims that decide the design.

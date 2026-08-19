---
description: Code-review conventions for product/service development — what counts as a review-worthy changeset, the language-agnostic reviewer checklist, and how findings are reported.
paths: ["**/*"]
---

# Dev — code review

Defines the *scope* of a review and the *criteria* applied to it. Branch, commit and PR mechanics are already covered by [`../workflow.md`](../workflow.md) and the `pr-create` skill, so they are not repeated here. This file covers only **how to judge the change**.

**Precedence.** `CLAUDE.md` ⊂ [`../workflow.md`](../workflow.md) ⊂ this file ⊂ skills and agents. The narrower scope wins.

The procedural counterpart is the `pr-review` skill; this file is the source of truth for the checklist that skill walks.

**When it applies.** This checklist targets an *open PR*. Self-review before there is a PR — a commit range, unpushed work — belongs to Superpowers' `requesting-code-review`, pulled in by `harness-dev`, and responding to review you received belongs to `receiving-code-review`. The three are different moments of the same job, not substitutes.

---

## R1 — What counts as a review unit

A review, and a PR, is a unit only in one of three cases.

1. **The user says so** — "review this", "look at this PR", "is this safe to merge".
2. **A cohesive multi-file change has reached a natural stopping point.** One test decides it: *would a reviewer seeing only the diff read this as a single unit immediately?* If not, it is either not finished or it is two units wearing one hat.
3. (**Not a unit**) a single-file typo, throwaway exploration. Report the result and do not promote it to a commit or a push.

When case 2 is unclear, summarise the diff in one sentence. If the sentence is "fixed A and tidied up B while I was there", that is two units.

---

## R2 — Reviewer checklist

Language- and framework-agnostic items only. Style and lint are already caught by that language's tooling, so a human — or a model — has no reason to look again.

- [ ] **Does every changed line trace to the stated intent?** Renames, reordering and refactors unrelated to what the PR body claims are findings. The reviewer has to pick the real change out of the noise, and the revert unit is contaminated if something goes wrong. The cleanup may be worth doing; it is a separate PR.
- [ ] **Are tests updated, or does the PR body say why not?** Missing tests are not always blocking. *Unexplained* missing tests are.
- [ ] **Are error paths and boundary inputs handled?** Empty input, maximum values, repeated calls, a failing external call, partial failure. New code with only a happy path — review is the last place to catch it.
- [ ] **Is anything newly added that nothing calls?** Helpers, flags, config keys and branches that arrive dead. "It is for the next PR" is added in the next PR.
- [ ] **Does observable behaviour change without the PR body saying so?** Output format, API responses, exit codes, log contracts, defaults, performance characteristics. This is the item that fires most often, because it is obvious to the author and therefore goes unwritten.
- [ ] **Is each new dependency justified?** For every one added: can the standard library or an existing dependency do it, how narrow is the surface actually used, and is pulling in the whole thing worth that surface?

---

## R3 — How to report findings

- **Do not mix blocking with suggestions.** Two lists. For each blocking item, one sentence on *what breaks if this merges*. If that sentence will not write, it is not blocking.
- **`file:line` on every item.** A filename alone makes the person receiving the review search for it again.
- **Write the fix, not the name of the problem.** Not "no error handling" but "`client.py:88` parses the response before checking the status, so a non-2xx throws — check the code first, or add a failure branch". Specific enough to apply directly.
- **Where judgement is required, ask for the reasoning instead of deciding.** New dependencies, behaviour changes and design choices: the review item is a request that the PR body explain *why this way*.

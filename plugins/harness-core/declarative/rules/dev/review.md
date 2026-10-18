---
description: Code-review conventions for product/service development — what counts as a review-worthy changeset, the language-agnostic reviewer checklist, and how findings are reported.
paths: ["**/*"]
---

# Dev — code review

**Precedence:** `CLAUDE.md` ⊂ [workflow](../workflow.md) ⊂ this file ⊂ skills and agents; narrower scope wins.

For an open PR, `pr-review` applies this checklist. Commit-range self-review belongs to Superpowers' `requesting-code-review`; responding to feedback belongs to `receiving-code-review`. PR mechanics remain in workflow and `pr-create`.

## R0 — Implementation checkpoints

For non-trivial work, name the observable user result and the data or state shape before adding logic. Use the existing implementation workflow; `harness-dev:engineering` supplies pstack-derived procedures when performance, impact analysis, migrations or coordination need more detail.

Validate at boundaries, give mutable state one owner and check retries against partial prior state. Prefer a smaller interface and fewer independent assumptions. Migrate owned internal callers before deleting their old API; honor external contracts.

Verify coherent units before building on them. If two fixes fail while assuming the same fact, write down and test that premise. Tests should catch broken behavior and survive changes to the internals.

## R1 — What counts as a review unit

Use workflow R1's unit boundary. Split a change whose intent requires unrelated explanations. Honor an explicit review request, including small changes.

## R2 — Reviewer checklist

- [ ] Every changed line serves the stated intent; unrelated cleanup is separate.
- [ ] Tests or other applicable checks cover the change, or the body explains their absence.
- [ ] Boundary inputs, repeated calls, failing dependencies and partial failures are handled.
- [ ] No unused helpers, flags, configuration or branches are added for future work.
- [ ] The body describes changes to observable behavior, contracts, defaults and performance.
- [ ] New dependencies are justified against standard-library and existing alternatives.

Do not repeat style or lint checks already handled by tooling.

Before commit, remove authorized dead code, speculative scaffolding and redundant comments. Check warning comments and suppressions against the live path; a comment is not a reason to preserve a workaround. Fix an accepted cause, encode a valid invariant where feasible and retain necessary evidenced rationale. Prove the changed public path and the assumptions its downstream consumers need. Keep evidence after cleanup and refresh applicable checks when the patch changes.

## R3 — How to report findings

Separate blocking findings from suggestions, ordered by impact. Each finding needs `file:line`, what breaks and a concrete fix. If no breakage can be named, it is not blocking. Ask for the rationale where a dependency or design choice needs the author's judgment.

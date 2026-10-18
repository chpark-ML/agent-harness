# ADR-0014: Adapt pstack's verification contracts and evidence procedures

- **Status**: Accepted
- **Date**: 2026-10-18
- **Related**: [ADR-0009](0009-external-dependencies.md), [ecosystem evidence](../agent-layer.md#3b-ecosystem-verdicts--what-came-in-and-what-got-measured), [third-party notice](../../plugins/harness-dev/NOTICE.md)

## Context

The owner requested that the pstack review become an implementation in this
harness. The official plugin is installable, but its orchestration, debugging
and review workflows occupy stages already covered by Superpowers and our
review skills. Its Claude Code adapter also maps non-Claude model slugs to
the session model; installation does not establish cross-provider review.

The useful intent is narrower: make a consumer project's real verification
path reusable, recover the evidence behind constraints, compare consequential
design shapes, and judge outside review findings instead of forwarding them.
This is an owner-requested addition, not a claim of two observed incidents.

## Decision

1. Add `project-verification` to `harness-dev`. It writes a consumer-owned
   local verification skill and feature map, reuses existing commands, and
   exercises one real user journey. Blocked execution leaves a labeled draft.
   Generating a contract is separate from running checks or fixing the app.
2. Give `pr-review` a conditional design-evidence reference. Recover relevant
   history and design records, distinguish facts from inference, and compare
   caller-visible alternatives against the same criteria. Small fixes do not
   require architecture work. No parallel agents or prototypes are mandated.
3. Extend `cross-model-review` with a shared rubric and evidence-based
   dispositions. Report actual agreement, disagreement and coverage without
   treating consensus as proof. Preserve its transport and consent boundary;
   this change authorizes no additional sends or reviewers.
4. Keep these procedures in skill bodies. Add no always-applied rule, hook,
   external dependency, model preset, automatic merge or blanket comment deletion.
   Keep pstack's MIT notice in the shipped dev plugin.

The new skill belongs to the conventions layer: it authors a repository's
verification contract. General implementation, TDD and debugging remain with
Superpowers. This is not a second orchestration framework.

### Follow-up: comment review (2026-10-18)

The owner also requested the intent behind `no-comments`: prevent comments
from preserving obsolete assumptions and excusing workarounds. `pr-review`
now checks comment claims and suppressions against live paths and evidence.
It proposes deletion for redundant prose, root-cause fixes for workarounds,
and executable protection for valid invariants where feasible. Current
external constraints, legal notices, public contracts and necessary rationale
remain. Unknown claims become decisions, not automatic keeps or deletions.
This stays a scoped, report-only review pass; it adds no agent or cleanup hook.

## Verification

Use the skill's positive and negative trigger set, execute its generated
instructions on this repository in isolation, and audit the changed review
procedures against real history and scoped review inputs. Record outcomes and
limits in agent-layer §4b. Run the repository checks and measure the installed
candidate's context cost before publishing new figures.

## Alternatives considered

- **Depend on the entire pstack plugin.** Duplicates the existing workflow and
  introduces many unrelated skills; its projected cost is recorded in §3b.
- **Copy its orchestration and model assignments.** Requires runtime-specific
  capabilities and changes the user's delegation policy.
- **Add another standing principle.** The harness already says to verify work;
  what is missing is the executable project-specific contract.
- **Keep only a survey row.** Records the candidate without implementing the
  owner's requested behavior.

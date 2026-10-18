# ADR-0015: Integrate pstack's portable procedures across the development workflow

- **Status**: Accepted
- **Date**: 2026-10-18
- **Related**: [initial absorption](0014-pstack-procedures.md), [workflow ownership](0009-external-dependencies.md), [coverage and evidence](../agent-layer.md#pstack-native-integration)

## Context

After the initial verification and review subset, the owner requested maximum
practical absorption of pstack. That replaces the earlier selected-only scope.
The inspected upstream revision is `16541c6bc1ed6c8d808b2f78a33364003e82b967`:
54 primary skills, including 24 principle references, 23 playbooks, two agents
and three dormant Benny automation procedures. Counts come from the tree,
not the README's prose.

Installing another implementation orchestrator would leave two owners for
the same lifecycle. Copying Cursor model presets, automation calls and force
push recipes would also assume capabilities or authorization this harness
does not supply. The useful material can instead strengthen our defaults
and add specialized, selectively loaded procedures.

## Decision

1. Add implementation and pre-commit checkpoints to the existing dev rule.
   Data and ownership precede logic; repeated failed premises are tested;
   caller migration, behavioral checks, comment claims and downstream proof
   become part of the normal development path.
2. Add one `engineering` skill with task-specific references for investigation,
   design, delivery, impact, performance, evaluation, coordination, PR
   operations, work sessions, writing and issue triage. Superpowers retains
   ordinary implementation, planning, TDD and debugging. Our existing skills
   retain their lifecycle stages. There is one execution owner and plan.
3. Extend `project-verification` with full feature-map maintenance and
   `pr-review` with executable change-impact checks. Keep comment review
   available before commit as well as during open-PR review.
4. Ship a Bash 3.2 decision-log helper inside the skill. It appends to one
   writer's TSV, preserves prior rows, normalizes separators and treats
   formula-shaped cells as text. A repository verifier exercises its file
   contract through the public invocation. It is not a hook or terminal shim.
5. Adapt capability-dependent procedures rather than pretending they run.
   Existing runtime and user policies govern agents, models, messaging,
   automation, publication, landing and cleanup. No global model rule,
   scheduled job, account connection or second workflow dependency is added.
6. Account for every inspected skill, playbook, agent role and Benny procedure
   in the source-of-truth map. Distinguish an adapted procedure, an existing
   owner and a capability limit. Coverage of the source is not a claim that
   every real-world workflow or model has been behaviorally evaluated.

Core and dev ship the upstream MIT notice. The owner's explicit request is
the admission basis; no two-incident history is invented.

## Verification

Exercise the helper's real file behavior, measure the new skill's positive
and neighboring negative routes with a control, and follow the selected
procedures on real local artifacts. Reinstall the complete candidate in an
isolated configuration, measure its context and run the full repository
checks under Bash 3.2. Record actual results and limits in agent-layer §4b.

## Alternatives considered

- **Whole pstack dependency alongside Superpowers.** Adds a competing workflow
  and runtime-specific policy instead of integrating the behavior.
- **A copy of every public skill.** Creates many routing entries with repeated
  principles; references carry detail without another standing description.
- **Only add more review text.** Leaves implementation, performance and
  handoff procedures outside the normal path, which does not meet the request.
- **Replace Superpowers.** Discards the measured existing lifecycle without
  evidence that a replacement improves it.

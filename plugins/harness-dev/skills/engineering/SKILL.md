---
name: engineering
description: "Apply pstack-derived engineering playbooks for a requested pstack workflow, measured performance work, captured runtime traces, change-impact audits, phased migrations, or session handoffs. 한국어 트리거: 'pstack 방식으로', '성능 개선 플레이북', '프로파일 분석해줘', '변경 영향 범위 검증', '다음 세션 인수인계'. 일반 버그 수정은 이 스킬 말고 systematic-debugging, 열린 PR 리뷰는 pr-review, ChatGPT 등 외부 모델 크로스모델 리뷰는 cross-model-review, 검증 스킬 생성·갱신은 project-verification, PR 생성은 pr-create 로."
---

# Engineering

Apply the relevant pstack procedure inside the repository's existing workflow. Read only the references needed for this task. A small fix needs a small check, not a program.

Adapted from Lauren Tan's pstack; source revisions and the MIT license are in [NOTICE](../../NOTICE.md).

## Establish the outcome and owner

Use the user's actual goal, current branch and repository instructions. State the observable result, allowed scope and the evidence that will establish completion. Resolve an empirical question by observing it; ask only when a missing preference or requirement affects the work.

Keep one workflow responsible for execution. Use Superpowers for ordinary brainstorming, planning, implementation, TDD and debugging when installed; otherwise keep the host's existing implementation workflow. Invoke only available skills with the host's tools. This skill supplies additional checks and specialized playbooks; it does not start a second plan. `pr-create` owns PR mechanics, `pr-review` owns open-PR review, `cross-model-review` owns outside review, and `project-verification` owns reusable verification instructions.

Preserve the task's authorization, delegation policy and review or publishing gates. Upstream tool names and model presets are capabilities to check, not capabilities this skill installs.

## Choose the procedure

| Task | Read when needed |
|---|---|
| Understand behavior, recover rationale, explain a subsystem | [Investigation](references/investigation.md) |
| Choose a data shape, compare designs, prototype or refactor | [Design](references/design.md) |
| Implement a feature or bug fix, migrate callers, clean code and comments before commit | [Delivery](references/delivery.md) |
| Find consequences outside a diff and prove its safety assumptions | [Change impact](references/change-impact.md) |
| Diagnose live or captured profiles, measure performance, hillclimb a metric | [Performance](references/performance.md) |
| Evaluate a skill or prompt without leaking the answer into the task | [Evaluation](references/evaluation.md) |
| Run phased work, an authorized swarm or competing designs, manage a queue | [Coordination](references/coordination.md) |
| Check or fix CI and review blockers, prepare or land an authorized PR stack | [PR operations](references/pr-operations.md) |
| Recover context, hand off, pause on request, keep a decision trail | [Work sessions](references/work-sessions.md) |
| Write, teach, capture preferences or turn repeated mistakes into structural fixes | [Writing and learning](references/writing-and-learning.md) |
| Triage an issue, verify an existing fix, prepare a requested automation | [Issue triage](references/issue-triage.md) |

A task can need several procedures, but do not load the whole table. For an unfamiliar large task, choose the riskiest unknown first and write a short sequence of independently checkable units. Planning-only requests end with the plan; an implementation request continues through execution.

## Execute and report

Capture the relevant baseline, do one coherent unit and verify it before building on it. When two attempts fail while assuming the same fact, write that premise down and test it before another attempted fix. Reuse a deterministic script for work whose repeatability or reviewability needs it. Do not build a framework for a few obvious edits.

For long work, keep the [decision trail](references/work-sessions.md#keep-a-decision-trail) as decisions happen. Verification records identify the revision, environment, command, outcome and surviving artifact. A changed patch needs fresh applicable checks. A blocked or inconclusive result stays visible.

Before delivery, inspect the diff for unrelated changes, redundant indirection, obsolete compatibility paths and comment claims. Fix the cause of an accepted workaround finding; deleting its explanation alone does not finish the fix. Use existing checks and the real public entry point where the claim requires it.

Report the effect for the user, the design decision that mattered, what actually ran, evidence paths and remaining limits. A status-only question gets a status answer. A read-only investigation gets a cited answer. Neither starts implementation or publication.

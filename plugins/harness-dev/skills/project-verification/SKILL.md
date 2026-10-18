---
name: project-verification
description: "Create or refresh a project-local verification skill with runnable user journeys and durable evidence, grounded in the repository's existing commands. Use when asked to write reusable runtime verification instructions or a verification feature map. 한국어 트리거: '이 프로젝트 검증 스킬 만들어줘', '실행 검증 절차 정리해줘', '검증 지침 갱신해줘'. 기존 가드 테스트 실행은 이 스킬 말고 verify, 일반 버그 수정은 systematic-debugging, 열린 PR 검토는 pr-review 로."
---

# Project verification

Write the consumer project's verification contract so the next agent can prove behavior without rediscovering how to run the project. This authors or updates instructions; an ordinary request to run tests or fix a bug stays with the existing workflow.

Adapted from pstack's `create-verification-skill`. Attribution and the MIT license are in [NOTICE](../../NOTICE.md).

## 1. Discover the user path

Read the repository instructions, documented entry points, existing verification skills and test scripts. Find what a user actually operates: a CLI, UI, API, library or another artifact. Start from the caller's command, request or interaction, then trace the code it reaches.

Establish these facts from the tree and a local probe:

- How to build or launch, including required configuration, seed data and readiness conditions.
- Which existing harness can drive the public entry point. Reuse it before introducing a helper or dependency.
- What observable state proves the behavior, including files, responses and other side effects.
- How to isolate ports, data directories and processes from the user's session and other runs.

Read linked design records or relevant history when an unfamiliar constraint affects the journey. Distinguish documented requirements, observations and guesses. Missing configuration or a broken base is a named blocker; generating instructions does not authorize unrelated application repairs.

## 2. Write a consumer-owned skill

Honor a requested destination. Otherwise update an existing project verification skill, or create `.claude/skills/verify-<project>/SKILL.md` with a lowercase project slug. Preserve existing journeys and user edits. Keep the result outside managed harness rules and plugin caches.

Give the generated skill a matching `name` and a quoted `description` naming its project, surface and trigger. Use the project's instruction language. Include these sections with actual paths and commands, not unresolved placeholders:

| Section | What the next agent needs |
|---|---|
| Launch | Working directory, exact build/start command, configuration and usable-state check. A short-lived CLI needs a build or dependency check, not an invented server. |
| Doctor | A read-only check for the expected build, configuration and owned instance before driving it. |
| Drive | The public entry point and action sequence for each mapped feature, with stable selectors, arguments or routes. |
| Evidence | Commands, exit status, before/after state and artifact paths. Record the revision, environment and any mocked boundary that limits the claim. |
| Cleanup | Stop only processes and remove only scratch state the run created. Keep proof artifacts in a separate location and verify they survive. |

For scripts or helpers, show the exact invocation and make executable files executable. Reuse the repository's test runner; this skill supplies real user journeys and does not replace unit or regression tests.

## 3. Map the features

Write a linked `features.md` beside the generated skill. Start with the important user paths exposed by the repository. Each entry needs:

- The feature, its user-facing entry point and required starting state.
- The actions, observable expected result and evidence to retain.
- Known environment constraints and whether this journey was exercised, blocked or remains unverified.

Preserve separate entry points when they exercise different behavior. Do not report the entire map verified because one journey passed. A test shortcut that bypasses the real user path proves only the shortcut. If a dry-run is the safe path, observe its promised lack of side effects rather than relying on its name.

## 4. Exercise the generated instructions

Follow the generated skill once: launch, doctor, drive one mapped feature, capture evidence and clean up. Run cleanup after a failed attempt too. Check the evidence still exists afterward. Correct the instructions and repeat the affected journey if they were wrong.

Use isolated local or test resources within the task's authorization. If proof would require unavailable credentials, production changes or an external action outside that scope, keep the artifact labeled **draft**, record the exact blocked step and finish the independent checks. A substitute environment does not establish behavior on the real target; name the difference.

Report the generated paths, the journey actually exercised, its result and surviving evidence location. List blocked or unverified journeys. Ask for a refresh when entry points or launch commands change; do not create a schedule.

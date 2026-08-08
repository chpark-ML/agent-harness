# ADR-0010: The slides profile does no rendering, and mechanically enforces number traceability only

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

Development and research results end up being presented. That is **the moment an untraceable number gets quoted** — the notes may record which run produced a table, but the moment it moves onto a slide the number survives and the evidence falls away, and then the audience quotes that number and decides things with it. The invariant `harness-research` builds with `ARTIFACTS.md` ("a number not traceable to a run is not a result yet") breaks right here more than anywhere else.

At the same time, **slide rendering is a solved problem.** `slides-grab` (npm) covers plan → html → design → export across four skills. There is no reason to rebuild HTML layout, theming and PDF export, and building them would add maintenance and lose on quality.

There is also a conflict with existing discipline. [ADR-0009](0009-external-dependencies.md) set the rule that two skills sharing a trigger are not shipped together, and "make me a deck" plainly shares a trigger with the `slides-grab` skills.

## Decision

**Create the `harness-slides` profile, with its scope pinned to "artefacts → narrative".** It does not render, design or export.

1. **The `results-deck` skill** — turns the repository's artefacts (`FINDINGS.md`, `experiment_plan.md`, `ARTIFACTS.md`, or a change history, release notes, benchmark output) into an outline on a six-slide skeleton and hands it to `slides-grab`. The skeleton **requires "how much to believe it" and "what is not established"** — for the same reason `FINDINGS.md` preserves reversals: a talk with no overturned results reads as a talk where they were deleted.
2. **The trigger conflict is settled by negative routing.** The description sends rendering, design, editing and PDF explicitly to `slides-grab`, and note-writing itself to `research-notes`. In ADR-0009 we could not put negative routing into somebody else's skill and had to pick one; here the **roles genuinely do not overlap** (we produce the input, they render it), so our description alone divides them.
3. **`check-claims.sh` — traceability enforced by a script, not by a skill instruction.** It mechanically checks that every numeric token in the deck appears in the evidence file, and exits 1 if one does not. Numbers that are not claims (years, ISO dates, versions, list numbers, slide references) are ignored, and exceptions are declared with a `<!-- no-claim -->` on that line.
4. **`slides-grab` is not declared as a dependency.** It is an npm package, not a plugin, so `dependencies` cannot point at it. It is treated like an LSP binary — `harnessctl doctor` checks PATH and prints the install command.

### Why a script — it is also a question of measurability

Put "write numbers traceably" in a skill body alone and it is a guide. Whether a guide is actually followed can only be established by an agent-session A/B, and as [agent-layer §4b](../agent-layer.md) measured, such an A/B needs tens to hundreds of sessions per arm to see an effect below 20%. **Push the same rule down into a script and it is settled by 21 cases.** The principle that what can be a guard should not be left a guide is not only a safety principle; it is a measurability principle.

`check-claims.sh` is a **command**, not a hook. It blocks no tool call — a draft deck is a document, not a tool call, and there is no point to block at. Instead the skill's Step 3 runs it, and a draft that does not pass is not handed to the renderer.

### What the check deliberately does not do

It does not check whether a number is used **correctly**. Attach a number that exists in the evidence file to the wrong sentence and it passes. Semantic checking is not something a regex does, and pushing in that direction raises false positives until the check is routed around within a day. The scope stays fixed on the accident that actually happens — **a number that exists on the slide and nowhere else**.

## Consequences

- A request for a deck no longer goes straight to a rendering tool; it passes through evidence collection first. Gathering the numbers before writing the deck reverses the order in which you would otherwise look for numbers that fit the narrative.
- On a project with no `ARTIFACTS.md`, `check-claims.sh` exits 2 (an operational failure). That is intended — passing without an evidence file makes the check a pretence. The skill's Step 1 has that table built first.
- The false-positive risk remains. The list of not-a-claim shapes was built from observation, so a shape can be missing, which is why 7 of the verifier's 21 cases are things that must pass. When a new false-positive shape appears, the case comes first.
- Without `slides-grab`, this profile stops at the outline. That alone is worth having, but unless doctor says so the user experiences it as something cut off.

## Alternatives considered

- **Render it ourselves.** Rejected. `slides-grab` does it better, and it amounts to building a second set of overlapping triggers with our own hands.
- **Put it in `harness-research`.** Rejected. Presenting is not research-only — the same accident happens in release reviews, demos and sprint reports. As its own profile, a `harness-dev` user can combine it too.
- **Make the traceability check a hook.** Rejected. Hooks intercept tool calls, and there is no tool call corresponding to writing a deck. Intercepting Write by filename pattern was considered, but deck filenames differ per project and blocking a draft save is blocking at the wrong point.
- **Pass without `ARTIFACTS.md`.** Rejected. Make the evidence file optional and the check passes unconditionally on most projects — and from then on, passing carries no information.

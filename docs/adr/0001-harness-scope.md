# ADR-0001: The harness covers the agent layer, and is built as core plus optional modules

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

The two harnesses we looked at failed in different ways. One had the agent layer and ML scaffolding (Hydra, registry, tracking) mixed in a single repository, until roughly 4,000 lines were deleted and only the agent layer remained. The other had its conventions, hooks and skills bound tightly to a research domain (EHR, papers, LaTeX), so no other project could use it as-is — that repository had in fact declared, on its own, that "the generalisable parts get extracted one-way into a separate repository".

At the same time, product work and research work need different rules and different skills. Merge them into one and half of it is noise on any given project.

## Decision

This repository covers **the Claude Code agent layer only** — conventions, permissions, hooks, skills, and the installer that puts them into a consumer project. Application code, build systems, per-language scaffolding and backend integration are the consumer's business.

It is built as **a `core` that always installs, plus modules you opt into** (`dev`, `research`). Modules are selected with `install.sh --with <names>`.

There is one admission test: **would this still make sense installed as-is on a project in another domain, on another stack?**

This repository is separate from the extraction target mentioned above. It is a general-purpose harness covering product and service development as well as research, and it shares no code with either reference repository.

## Consequences

- Domain-specific assets (a medical PHI scrubber, a LaTeX build, a literature-survey skill) do not come in here. A project that needs one puts it in its own `.claude/` or builds its own module.
- Module boundaries require judgement. "PR review checklist" is `dev`, "experiment-note discipline" is `research`, "no AI attribution" is core — and that call has to be made every time.
- A consumer receives one merged `.claude/`. If core and a module both write to the same path, the install stops (`install.sh`'s conflict check).
- More modules means more combinations. Verification covers one full `--with dev,research` combination and a module-swap round trip — which is enough, because modules do not share file paths.

## Alternatives considered

- **A single merged `.claude/`** — simpler, but a product project gets experiment-note discipline and a research project gets release conventions.
- **Core only, no modules** — the smallest option, but it leaves the user hand-filling the real difference between the two kinds of work every time.
- **Packaging as a Claude Code plugin** — the original rejection said "a consumer cannot easily open and edit the files". **That reason was wrong.** What a consumer actually opens and edits is `CLAUDE.md` and the path-guard config, and those cannot be carried by a plugin at all, so they stay in the consumer tree regardless. Hooks and verifiers, conversely, are not shipped to be edited — what needs fixing gets fixed upstream (`CLAUDE.md` §5). The real constraint was never readability but **what a plugin cannot carry** ([ADR-0008](0008-plugin-declarative-split.md)).
- **A template repository (clone to start)** — no update path. A harness is a thing that gets fixed and redelivered.

---

> **Correction (2026-08-06, after [ADR-0008](0008-plugin-declarative-split.md)).** The scope decision still holds — the harness still covers only the agent layer, it is still core plus optional modules, and the admission test is unchanged. What changed is the delivery shape. Modules became plugin profiles (`harness-dev`, `harness-research`, the language profiles), and selection is now split between `claude plugin install harness-<profile>@agent-harness` and `harnessctl init --with <names>` rather than `install.sh --with <names>`. The reason given for rejecting the plugin option above was refuted by observation; the real boundary was that a plugin cannot carry permissions, `CLAUDE.md` or `rules`. That the admission test **governs core and not the opt-in profiles** is handled separately by [ADR-0009](0009-external-dependencies.md).

---

> **Correction (2026-08-18).** The Consequences list above says *"Domain-specific assets (a medical PHI scrubber, a LaTeX build, a literature-survey skill) do not come in here."* **That sentence is now false as written, and it was already false when two profiles shipped past it.**
>
> What it should say is that domain-specific assets do not come into **`core`**. The 2026-08-06 correction above already recorded that the admission test governs core and not the opt-in profiles, and [ADR-0009](0009-external-dependencies.md) carries the reasoning — but the Consequences bullet was never brought into line, so it still reads as a blanket exclusion. Two shipped profiles contradict it: [`harness-slides`](0010-slides-profile.md) carries presentation material, and `harness-frontend` carries a UI/UX reference. Presentation and interface design are no less domain-bound than a manuscript.
>
> **Why this matters rather than being tidy-up.** The harness was built for five kinds of work, and paper writing is one of them. An architecture record that names *a LaTeX build* and *a literature-survey skill* as excluded is the first thing anyone reads when asking whether that work belongs here, and it says no. The answer is yes, as an opt-in profile, on the same footing as slides — and `results-deck` is the precedent to copy rather than a thing to invent around, because turning `FINDINGS.md` and `ARTIFACTS.md` into an artefact where every number traces to the run that produced it is the same transform a manuscript needs.
>
> **What is unchanged.** The admission test still governs `core`, and it still refuses anything site-specific there. A PHI scrubber remains the consumer's own business — not because it is domain material but because no profile has asked for it.

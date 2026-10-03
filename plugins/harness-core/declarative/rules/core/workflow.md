---
description: Branch, commit and PR conventions, plus the harness-gap loop. Catch-all — applies to every session.
paths: ["**/*"]
---

# Workflow — catch-all rules

**Precedence:** `CLAUDE.md` ⊂ this file ⊂ domain rules ⊂ skills and agents; narrower scope wins. Installed by [agent-harness](https://github.com/chpark-ML/agent-harness). Managed rules are replaced on reinstall; edit the upstream source.

## R1 — A finished unit of work becomes a PR

Create a PR when the user requests it or a cohesive change reaches a natural stopping point. A single-file typo, one-line fix or throwaway exploration does not require a commit or push unless requested. Split unrelated changes.

The `pr-create` skill handles state inspection, branching, semantic commits, verification, push and PR creation.

- Branch first; never push directly to the default branch or force-push.
- Branch: `{feat,fix,chore}-<slug>`, with no `/`.
- PR title: `[<slug>] <description>`, at most 70 characters; do not repeat the type.
- PR body: motivation → changes → verification → notes.
- Non-interactive runs stop when push requires approval; do not retry or bypass the permission policy. Unattended publishing requires the project's explicit authorization.

## R2 — Commits

Start the subject with a verb; use the body to explain why. Split commits by meaning. No AI attribution in commits or PRs; legitimate references to tools and filenames remain allowed.

## R3 — Harness gap detection

Follow `CLAUDE.md` §5's ledger and authorization procedure. A new rule needs two occurrences and must apply unchanged across projects, domains and stacks. Keep harness fixes separate from feature changes.

## R3.1 — Retro immediately after a merge

Review corrections, repeated commands, direction changes and unstated assumptions. Apply R3's threshold; propose concrete before/after changes. If nothing qualifies, report `retro: no new harness gaps`.

## R4 — Self-check before opening a PR

- Inspect status and diff; include only this work's files.
- Check commits against R2 and title/body against R1.
- Run the project's applicable checks and report their actual results. State what was checked by hand if no automated check applies.

## R5 — Verify diagnostics before they enter a plan

Verify the numeric or structural claims that decide the design. Record the command and result beside each claim; revise the plan when they disagree. Check the few claims that matter, not every incidental observation.

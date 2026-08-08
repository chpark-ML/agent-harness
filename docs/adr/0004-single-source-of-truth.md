# ADR-0004: `docs/agent-layer.md` is the single source of truth, and no index file is installed

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

One reference harness kept a layer diagram and an inventory of rules, skills, agents and hooks in `.claude/README.md`, and put a self-maintenance rule inside that same document (§8): "update this index whenever you add anything". Even so, at least two drifts were visible at the time we looked — the index recorded a value that differed from what `settings.json` actually held, and one registered hook was missing from the hook list.

The same repository had previously kept a separate roadmap document and deleted it, citing drift.

The lesson is not "write the rule more forcefully". It is that **a hand-maintained inventory drifts even with a rule**, and a drifted index is worse than no index — because readers believe it.

## Decision

**`docs/agent-layer.md` is the only source for the harness's scope, inventory and backlog.** A change to any of those three updates that file alone. The same content is not duplicated into the README or a separate roadmap.

**No index file is installed into a consumer** (nothing of the `.claude/README.md` kind). Consumers get files; the inventory lives in one place, in the harness repository.

**Anything a machine can confirm is verified rather than written down.**

- The list of installed files comes from one place: harnessctl's planning code. There is no list to transcribe into a document.
- Whether every shipped script is executable, every fragment and manifest is valid JSON, and every `hooks.json` registration resolves to a real file, is confirmed by `scripts/verify-install.sh` in CI. *(After ADR-0008 there is no `templates.txt` — tiers are declared by harnessctl's planning code.)*

So what stays in `agent-layer.md` is **what a machine cannot confirm**: why this harness exists, what is out of scope, what gets built next, and why some things were decided against.

## Consequences

- The §3 inventory figures in `agent-layer.md` (6 hooks, 4 skills, and so on) are still hand-maintained and can still drift. But when they are wrong, what is lost is the accuracy of a summary, not the behaviour of an install.
- A consumer wanting to know "what did this harness install" reads `.claude/harness-manifest.json` or the harness repository. The manifest is machine-generated, so it is always right.
- New contributors are pointed at `agent-layer.md`, not the README.

## Alternatives considered

- **An index file with an explicit self-maintenance rule** — the reference harness did exactly this, and it drifted.
- **Generate the index (build it from the tree with a script and commit it)** — stops the drift, but the generated file only restates the tree, which is no better than reading the tree.
- **Make the README the source of truth** — the README is a consumer quick-start. Different audience, different document.

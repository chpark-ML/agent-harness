# ADR-0003: Every guard ships with an automated verifier

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

A hook prints nothing on the happy path. From a user's seat, a broken hook and a hook that quietly lets everything through are indistinguishable, and that state can last for months. Invert a pass condition while fixing a regex and nobody finds out.

Failure in the other direction costs the same. A guard that produces false positives gets switched off with an environment variable every turn, and a switched-off guard is no guard.

The installer is worse. When it fails, what breaks is the user's `settings.json` — data we did not create and cannot restore.

## Decision

**A guard merged without verification is not a guard, it is decoration.** Every hook ships with `plugins/harness-core/scripts/verify-<name>.sh`.

What each verifier owes:

- **Eight cases or more**, covering all three kinds: **no-op** (input the hook must not touch), **block** (input it must stop), and **boundary** (input that resembles what is blocked and must pass).
- Use `run_case` / `expect` / `expect_match` from the shared `_verify-lib.sh`. Hooks run under an `env -i` isolated environment, in a mktemp working directory, under the same interpreter as the verifier.
- Print `X / Y passed` at the end, and exit non-zero on failure.
- Verify that the block message carries *what was caught* and *how to get past it*. The message is the interface the model reads and acts on, so it is part of the behaviour.

`plugins/harness-core/scripts/verify-hooks.sh` discovers and runs `verify-*.sh` automatically — there is no registration step, so the set that runs cannot drift from the set that exists.

**The installer owes the same.** `scripts/verify-install.sh` builds a scratch consumer and checks the round trip: install, reinstall, template and managed tiers, module swap, uninstall. The most important assertion is that *`settings.json` after uninstall is canonically identical to the original*.

After an incident, **add the regression case first**, then fix.

## Consequences

- A new hook costs twice as much. That is intended — a guard you cannot verify is better not built.
- The three-kind requirement forces boundary cases. A verifier with only block cases proves nothing about false positives, and false positives are what actually kill guards.
- CI runs everything in two environments (ubuntu bash 5, macOS bash 3.2), so merges take longer.
- Scale at the time of the decision: 6 hook verifiers / 192 cases, 90 harnessctl assertions, 9 frontmatter. [`agent-layer.md` §4](../agent-layer.md) is the source of truth for current numbers — the figures here are a record of that moment.

## Alternatives considered

- **A documented manual verification procedure** — it runs the first few times, and then it does not.
- **Smoke tests for hooks only** — catches a broken hook, misses false positives. False positives are the more common cause of death.
- **Exempt the installer** (the reference harness deleted its installer verifier as "disproportionate") — that judgement was about a 143-line copy-only installer. This installer merges JSON and removes symmetrically, so what is lost on failure is different.

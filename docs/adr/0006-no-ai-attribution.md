# ADR-0006: No AI attribution in commits or PRs

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

By default Claude Code appends a `Co-Authored-By: Claude <noreply@anthropic.com>` trailer to commits and puts a `🤖 Generated with [Claude Code]` footer in PR bodies. The two have different switches — the first is `includeCoAuthoredBy` in `settings.json`, the second is a judgement the model makes while writing the body.

The two reference harnesses took opposite positions. One kept `includeCoAuthoredBy: true` and *required* the trailer in its workflow convention; the other turned it off and blocked it at the command layer with a PreToolUse hook. The user of this repository is the second one.

Since this is a point where policies diverge, leaving it unwritten means the next look at a reference harness could revert it on the grounds that "theirs is true".

## Decision

**No AI appears as author or co-author in a commit message, a PR, or an issue.**

Three layers hold it.

1. `includeCoAuthoredBy: false` in `plugins/harness-core/declarative/settings-fragment.json` — turns off the built-in attachment. If a consumer already has this key, the installer warns instead of changing the value (it does not overturn somebody's explicit setting).
2. The `ai-attribution-guard` hook — blocks trailers, footers and robot emoji in Bash commands that write a commit, PR or issue. Because it catches at the command layer, `--no-verify` does not get around it.
3. `rules/harness/workflow.md` R2 — states it as a convention. On paths with no guard (this repository itself, for one), it is the only thing left.

Legitimate references are not attribution and stay: the filename `CLAUDE.md`, the `.claude/` directory, the `anthropic` API backend, a model name in prose. A human co-author trailer passes too, of course.

## Consequences

- This is the exact opposite of one reference harness. When that repository comes up again and the divergence is noticed, this ADR is the reason to hold.
- This repository cannot install onto itself (ADR-0001), so it gets no protection from the hook here. `CLAUDE.md` §6 discipline is all there is.
- A consumer who already set `includeCoAuthoredBy: true` still has `true` after install. The installer warns and does not change it — that value may be a deliberate choice.
- There is one place the hook can produce a false positive: quoting the policy inside a commit message ("drop the Co-Authored-By: Claude trailer"). If it ever fires, rephrase — there is rarely a reason to put policy text in a commit subject.

## Alternatives considered

- **`includeCoAuthoredBy: false` alone** — stops the built-in trailer, not the footer the model writes itself. The second is the path that actually leaks.
- **A commit-msg stripper** — bypassed by `--no-verify`, and git-hook installation is asymmetric across environments. Useful as a backstop, not as the primary defence.
- **Convention only, no guard** — the default behaviour runs the other way, so convention alone leaks repeatedly.

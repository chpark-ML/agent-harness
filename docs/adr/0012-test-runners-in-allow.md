# ADR-0012: Five test runners move into `allow`

- **Status**: Accepted
- **Date**: 2026-08-08
- **Related**: [ADR-0007](0007-install-levels.md) (permission tiers) · [`CLAUDE.md`](../../plugins/harness-core/declarative/CLAUDE.md) §4 and §6 · [`agent-layer.md` §4b](../agent-layer.md)

## Context

`CLAUDE.md` §4 requires *"run it, look at what came out"*. The new §6 requires evidence in a report. Both principles stand on the assumption that **the agent can actually run the verification command**.

That assumption was false. Of 42 `allow` entries, **the only runner was `Bash(make:*)`** — no `pytest`, no `python3`, no `npm`, no `sh`, no `./script`. In a repository without a Makefile, the verification the harness demands **raises an approval prompt every time, and is refused outright in a non-interactive run.**

**It surfaced during a measurement.** The first pilot of the R6 loop-rule benchmark came back 0/3 on both arms; opening the stream showed the agent had **asked to run `sh check.sh` and been refused**. The 0/3 was evidence about permissions, not about the rule. In the same run **the agent under test reported the defect itself**, and was then refused when it tried to write to the ledger — because writing to `.claude/` needs approval too.

The ledger counts this as occurrence 2. Occurrence 1 was *the `ask` tier makes the PR flow unreachable in headless runs*. **Same family: the permission design makes a step the harness itself mandates unreachable.**

## Decision

Add five runners to `permissions.allow`, right beside `Bash(make:*)` — because they are the same kind of thing.

```
Bash(pytest:*)
Bash(python3 -m pytest:*)
Bash(npm test:*)
Bash(cargo test:*)
Bash(go test:*)
```

**Bare `python3`, `python`, `sh`, `bash` and `node` are not added.** That is not allowing a runner, it is opening a shell. `npm run <script>` is not added either — the script name is arbitrary, so it is not as narrow as `npm test`.

A project whose runner is not on the list adds its own to its own `settings.json`. Try to anticipate every ecosystem's runner and the list becomes a shell.

## What we are accepting, stated plainly

**A test runner executes arbitrary code from the repository.** `conftest.py`, the test files, `package.json`'s `pretest`. All of it runs with no approval prompt.

**That line was already crossed.** `Bash(make:*)` is in `allow`, and a Makefile runs anything. The state before this change was not *"runners are dangerous"* but *"only repositories that use a Makefile can be verified"* — which is not a security judgement, it is an accident.

What actually widens is the range **from "repositories with a Makefile" to "repositories with tests"**. In threat-model terms, by this point the user has already decided to run an agent in that repository, and the agent already reads and writes files.

**The `ask` tier was considered and dropped.** `ask` is always refused headless, so the state where §4 cannot be honoured would simply remain. And by the tier's own definition `ask` is for *things that are expensive to undo*, while running tests is usually local and idempotent.

## Consequences

- `allow` goes 42 → **47**. Irrelevant to `context-budget` (permissions are not always-on context).
- A fixture in `verify-install.sh` had to change. That verifier tested *does an `allow` entry the consumer already had survive uninstall* using `Bash(npm test:*)` — and **once we ship that same string, the test passes for the wrong reason**: not because it was preserved but because we put it back. The fixture is now `Bash(echo consumer-owned:*)`. Only a string we will never ship actually tests the ownership property.
- This change **makes the R6 family of rules measurable again.** R6 itself is withdrawn on separate grounds (3/3 on both arms, no discriminating power).
- A consumer who wants `pytest` behind an approval prompt overrides it with `deny` in their own `settings.json`. `deny` beats `allow`.

## Alternatives considered

- **Do nothing.** §4 and §6 keep standing on an assumption that cannot be met. And that fact already ruined one benchmark quietly.
- **Allow only a project-designated single entry point, like `Bash(./check.sh)`.** Clean, but few repositories have such an entry point, and it lands back in the same problem as having only `make`.
- **Move them to `ask`.** Dropped for the two reasons above.

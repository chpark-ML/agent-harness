# check-uncommitted

At the end of a turn, reports when work is piling up on the default branch.

## Behaviour

Registered on `Stop`, matcher `""` (every Stop) ([`hooks.json`](../../plugins/harness-core/hooks/hooks.json)).

**Informational — always exits 0 and never blocks a turn.** It prints one line of notice to stdout.

Four gates must all pass before it says anything.

1. `git rev-parse --show-toplevel` succeeds — outside a repository, exit 0.
2. `git -C "$root" branch --show-current` is non-empty — on a detached HEAD, exit 0.
3. **the current branch is the default branch** — otherwise exit 0.
4. `git status --porcelain | wc -l` is greater than zero — clean, exit 0.

The default branch is taken from what the remote reports via `git symbolic-ref refs/remotes/origin/HEAD`. With no remote HEAD, the current branch is treated as the default only when it is named `main` or `master`; otherwise it exits 0. With neither a remote nor a conventional name, it declines to judge.

It does not use `jq`. It never parses stdin and only calls `git`, so it has no jq self-disable branch.

**Speaking only on the default branch is the whole design.** An unconditional "you have uncommitted changes" fires on every turn of every session and is ignored within a day, at which point it is not a guard rail but noise shaped like one.

## What passes

The verifier checks silence more than it checks blocking. All of the following are deliberately quiet.

- **Uncommitted changes on a feature branch** — that is where changes belong. Nothing to report.
- **The default branch with a clean tree.**
- **Detached HEAD** — with no branch name there is no branch convention to discuss.
- **Outside a git repository.**
- **No remote HEAD and a branch named neither `main` nor `master`** — it does not guess a default.
- **A branch named `main` in a repository whose default is `trunk`** — the name fallback would have spoken, but the remote lookup wins. `main` is a feature branch here, so silence is correct.

## Bypass

There is nothing to bypass; it does not block. The message itself names the cases where it can be ignored — a one-off typo or exploration, leave it. When the notice is right, the prescribed response is moving to a `{feat,fix,chore}-<slug>` branch (automated by the [`pr-create`](../../plugins/harness-core/skills/pr-create/SKILL.md) skill, shipped in the same plugin).

## Limits

- **`wc -l` counts files, not the size of the change.** `1` may be a one-character edit or a whole-file rewrite.
- **Untracked files count too.** They appear in `--porcelain` output by default, so unignored build artefacts inflate the number and make the notice repeat.
- **It fires every turn.** There is no suppression while the condition holds, so the same line repeats. The single default-branch gate is what keeps that from being noise.
- **It assumes the remote is named `origin`.** With a differently named remote the `refs/remotes/origin/HEAD` lookup fails and it falls back to `main`/`master`.
- **It does not judge whether the work is a review unit.** That judgement is left to rule R1 and to the human or model; the hook reports facts.

## Verification

[`plugins/harness-core/scripts/verify-check-uncommitted.sh`](../../plugins/harness-core/scripts/verify-check-uncommitted.sh) — 16 cases (5 silent, 4 speaking on `main`, 2 on `master`, **2 on a remote-declared default**, 1 count tracking). Silent cases use a dedicated `quiet_case` helper that checks exit 0 **and empty stdout** together. As the verifier's header says, the load-bearing property is not what it blocks but what it keeps quiet about.

Two fixtures set `origin/HEAD` directly with `symbolic-ref`, no network required, so the lookup path that always runs in a real clone is verified for the first time — before them every fixture was a remoteless `git init` and only the `main`/`master` fallback ever ran. The one that earns its keep is the repository whose default is `trunk` with a branch named `main`: the only arrangement where the name fallback and the remote lookup point in opposite directions, and the remote has to win.

```
bash plugins/harness-core/scripts/verify-check-uncommitted.sh
```

## Related

- Hook script: [`plugins/harness-core/hooks/check-uncommitted.sh`](../../plugins/harness-core/hooks/check-uncommitted.sh) (not installed into the consumer tree — loaded from the plugin cache)
- Registration: [`plugins/harness-core/hooks/hooks.json`](../../plugins/harness-core/hooks/hooks.json)
- Rule R1, which this hook helps enforce ("never push directly to `main`", and the definition of a unit of work): [`declarative/rules/core/workflow.md`](../../plugins/harness-core/declarative/rules/core/workflow.md) — unlike hooks, rules cannot travel in a plugin, so `harnessctl init` installs them into the project's `.claude/rules/`.
- The symmetric informational hook: [session-brief](session-brief.md) — reports the same `git status --porcelain` count at session start, regardless of branch.

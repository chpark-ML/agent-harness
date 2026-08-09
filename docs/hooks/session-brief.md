# session-brief

Injects a compressed briefing on repository state into context at session start.

## Behaviour

Registered on `SessionStart`, matcher `startup|resume|clear|compact` ([`hooks.json`](../../plugins/harness-core/hooks/hooks.json)).

**Informational — always exits 0 and never blocks a session.** This hook's stdout becomes session context.

Output order:

1. the `[session-brief] repo state` header
2. `- branch:` — `git branch --show-current`, replaced by `(detached: <short sha>)` when empty
3. `- upstream(<ref>): ahead N / behind M` — only when an upstream is configured **and** ahead and behind are not both zero
4. `- uncommitted: N files` — `git status --porcelain | wc -l`, **only when non-zero**
5. `- harness: project rules not installed (harnessctl init --scope project)` — **only when `.claude/harness-manifest.json` is absent**
6. `- recent commits:` followed by `git log -5 --pretty='  %h %s'`

It resolves the repository root once with `git rev-parse --show-toplevel` and sends every later call through `git -C "$root"` — the session may start in a subdirectory, and this matches its sibling Stop hook, [check-uncommitted](check-uncommitted.md). Outside a repository it prints nothing and exits 0.

It does not use `jq`. It never parses stdin and only calls `git`, so unlike the pre-tool-use hooks it has no jq self-disable branch.

**It reports the missing install; it does not perform it.** A SessionStart hook fires in whatever directory you happened to open, including a repository cloned for five minutes, and writing rules, settings and a `.gitignore` line into someone else's tree is not something a guard does uninvited. It would not even help: settings and plugins load at session start, so anything written from here applies from the *next* session — which is exactly when being told would have worked too. The line goes into context, so the agent reading it can offer to run the command.

**The output budget is eleven lines, and ten in the steady state.** This hook runs on every start, resume, clear and compact, so verbosity here is a tax levied on every session for the life of the project. It therefore carries only facts the model would otherwise spend a tool call to learn.

## What passes

The conditions under which it stays silent are the core property of this hook. Conditional lines do not appear at all in the default case.

- **Complete silence outside a git repository** — zero bytes, exit 0.
- **No upstream, no upstream line.** Even with one, it is omitted when ahead and behind are both zero. "In sync" is not information.
- **A clean working tree produces no uncommitted line.**
- **Detached HEAD still reports normally** — it is not treated as a failure, just labelled `(detached: <sha>)`.

## Bypass

There is nothing to bypass; it does not block. Registration lives in the plugin's `hooks.json` rather than `settings.json`, so it cannot be turned off by editing settings — disabling the plugin (`harness-core` in `/plugin`) is the only route, and that takes the other five hooks with it. If the content is the problem, change the script in the harness repository.

## Limits

- **The ten-line budget has no slack.** The worst case — upstream divergence plus uncommitted changes plus five commits — is **exactly ten lines**. Adding something means removing something. This is no longer advice in a document: the verifier renders that worst case and asserts it, so adding a field breaks the test.
- **`- recent commits:` is left empty in a repository with no commits.** The `git log` failure is swallowed by `2>/dev/null`, but the header line has already been printed.
- **`wc -l` counts files, not changed lines.** A large rewrite of one file and a one-character typo both read as `1 files`.
- **Submodules and worktrees are not distinguished.** It reports values for the current tree only.

## Verification

[`plugins/harness-core/scripts/verify-session-brief.sh`](../../plugins/harness-core/scripts/verify-session-brief.sh) — 24 cases (2 outside a repository, 5 clean repo, 1 output budget, 3 dirty repo, 2 detached HEAD, **4 upstream and worst-case budget**, 5 the not-installed notice and its absence). The `expect_absent` helper, which checks for lines that must *not* appear, lives in [`_verify-lib.sh`](../../plugins/harness-core/scripts/_verify-lib.sh) — used in two places here and one in protected-paths.

The last four run against a fixture that attaches a bare repository as a remote and builds a dirty tree one commit ahead. It is the only fixture that reaches the upstream block — before it, that code path never executed at all — and it is the budget worst case, where every optional line renders at once.

```
bash plugins/harness-core/scripts/verify-session-brief.sh
```

## Related

- Hook script: [`plugins/harness-core/hooks/session-brief.sh`](../../plugins/harness-core/hooks/session-brief.sh) (not installed into the consumer tree — loaded from the plugin cache)
- Registration: [`plugins/harness-core/hooks/hooks.json`](../../plugins/harness-core/hooks/hooks.json)
- The symmetric informational hook: [check-uncommitted](check-uncommitted.md) — reads the same `git status --porcelain` count at the end of a turn, but only speaks on the default branch. Both resolve the toplevel and call git through `git -C "$root"`.

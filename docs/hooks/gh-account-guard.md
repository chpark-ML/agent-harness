# gh-account-guard

Blocks a push or a pull request made as the **wrong GitHub account**.

## Behaviour

Registered on `PreToolUse`, matcher `Bash` ([`hooks.json`](../../plugins/harness-core/hooks/hooks.json) — the second `PreToolUse` block, alongside the other three Bash guards).

`gh` installs itself as git's credential helper, so `git push` authenticates as whatever account is currently **active**. Move between two accounts with `gh auth switch` and two things follow: a pull request opens under the wrong identity while nothing at all fails, or a push is refused with a 403 that does not say why.

The checks run in this order, and **the order is the design** — the expensive step is last, so the common case never pays for it.

1. `jq` absent → one line to stderr, exit 0.
2. `tool_name` is not `Bash`, the command is empty, or the command is not one of the caught shapes → exit 0. **Almost every call ends here, at no cost.**
3. Read any declared expectation (env, project file, user file). It may be empty — that is not the end.
4. `gh` absent → one line to stderr, exit 0.
5. Ask `gh` which account is active and which accounts exist.
6. Nothing was declared → try to infer the expectation from the owner of `origin`. Still nothing → exit 0.
7. Active is the expectation → exit 0. Mismatch → block message, exit 2.

Step 5 costs about **0.5 seconds**, because `gh auth status` validates the token against the API. That is far too slow to pay on every Bash call, which is why step 2 stands in front of it. **A repository that declares nothing now pays it too** — that is the one cost inference adds, and it is charged only on push and PR commands, a handful of times per session.

```bash
gh auth status --hostname github.com --json hosts \
  | jq -r '.hosts["github.com"] | map(select(.active)) | .[0].login'
```

`--active` is deliberately *not* passed: one call has to answer both "who is active" and "who else am I", and the second is what inference needs. That makes selecting on the `active` flag load-bearing — with two accounts authenticated, `.[0]` is simply the first, which is the whole situation this hook exists for.

Reading the JSON rather than the prose matters twice. Under `--json`, `gh` **exits 0 regardless of any authentication issue** (its own help says so), so the hook reads the payload and never the exit code. And the payload carries `tokenSource`, which is how the block message can say a token came from the environment.

**`~/.config/gh/hosts.yml` would have been free and offline, and was rejected.** Its host-level `user:` key names the active account at no cost — but when `GH_TOKEN` or `GITHUB_TOKEN` is set, `gh` uses that token and `gh auth switch` has no effect, while `hosts.yml` still names the old account. A guard about mistaken identity must not be confidently wrong in exactly the case where identity is in doubt.

An empty answer from `gh` is not a mismatch, so it exits 0 and lets git report the real problem. `state` is not consulted either: a broken token fails loudly on its own, and this hook only ever answers *which account*.

Without `jq` — or without `gh` — it prints one line to stderr and self-disables with exit 0. A missing hook must not block work.

## What is caught

`git push`, `gh pr create`, `gh pr merge`. Those are the commands behind the two accidents this hook exists for. `gh issue create` and `gh release create` also publish under an identity, and are deliberately **not** included — neither has actually gone wrong, and this harness adds guards for problems that happened, not for problems that could.

**The gate is anchored, and that is where it differs from [`ai-attribution-guard`](ai-attribution-guard.md).** That hook matches the same family of subcommands with a deliberately *unanchored* regex, and its document explains why that is safe there: "a wide gate is harmless — a command with no attribution passes it and exits 0 anyway." The reasoning does not transfer. Here the gate **is** the block, so a wide gate produces false positives — and a check that cries wolf gets switched off, which is the same as no check at all.

So the command is split on `;`, `&&`, `||`, `|` and newline, and a match must start at the **beginning** of a segment. Global options between `git` and its subcommand are skipped, the trick `ai-attribution-guard` learned after `git -C <repo> commit` slipped past a simpler pattern. This hook does not fold the command to lowercase, so its option pattern accepts `-C` as well as `-c`; without that, `git -C /elsewhere push` walks straight through.

## Configuration

**Usually none.** Four sources, resolved in order — **first match wins** — and the last one needs no configuration at all:

| Order | Source | Scope |
| --- | --- | --- |
| 1 | `HARNESS_GH_ACCOUNT` | one shell, one time |
| 2 | `${CLAUDE_PROJECT_DIR:-.}/.claude/gh-account.txt` | this repository |
| 3 | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/gh-account.txt` | this machine |
| 4 | **the owner of `origin`**, when that owner is itself one of your authenticated accounts | inferred |

Source 4 is why a personal repository needs nothing written anywhere. `github.com/chpark-ML/thing` with accounts `chpark-ML` and `work-acct` authenticated: the owner is one of them, so it *is* the expectation, and pushing while `work-acct` is active blocks. An organisation owner matches no account, so inference stays quiet and an org repository has to declare if it wants the guard. That degradation is deliberate: offline, there is no way to tell an org from a stranger's namespace, and a guard that invents an expectation blocks the wrong thing.

For sources 2 and 3 the value is one account login on its own line. `#` comments and blank lines are ignored, and **only the first real line is read** — so `echo login >> gh-account.txt` a second time changes nothing, and the file is edited rather than appended to.

**This deliberately differs from [`protected-paths`](protected-paths.md), which unions its sources.** There, more protection is safer, so a union is the right direction. Here a union would mean "either account is fine", which weakens the guard on purpose. A machine-wide default with per-repository exceptions is also the shape the problem actually has: one account is normal, and specific repositories are the exception.

**A personal repository is guarded out of the box; everything else stays off until declared.** Inference only ever fires when the answer is unambiguous — the owner is literally an account you hold. Where it cannot tell, the absent file is the off switch, the same stance `protected-paths` takes.

`gh-account.txt` is a **template** installed by `harnessctl init` rather than carried by the plugin — the original lives in [`plugins/harness-core/declarative/templates/`](../../plugins/harness-core/declarative/templates/) and belongs to the consumer once copied. What ships is comments only. With inference in place the file is now the *exception* path — reach for it when the owner of `origin` is an organisation, or when it is your namespace but the expectation is a different account.

## What passes

- **`echo "git push"`** — the segment begins with `echo`, not `git`.
- **`git commit -m "remember to git push after review"`** — the segment begins with `git`, but the subcommand is `commit`.
- **`git pushx --dry-run`** — `pushx` is not `push`.
- **`gh pr view 12`**, `git status`, and every other read-only command — outside the caught set.
- **`git push` in a repository that declared nothing, whose `origin` owner is an organisation** — inference has nothing to say, so the guard stays off.
- **`git push` with no `origin`, or an `origin` that is not on github.com** — nothing to infer from.
- **A config file containing only comments** — zero declarations is the same as inactive.
- **A remote on a host that merely resembles github.com** — `git@notgithub.com:you/repo` and `https://github.com.evil.io/you/repo` are other hosts. The hostname is parsed and compared exactly, not searched for.

## Bypass

Two, and the block message lists both.

- switch to the account the repository expects → `gh auth switch --user <login>`
- proceed as the active account, once → `HARNESS_GH_ACCOUNT=<login> <command>`

There is no third. Editing `.claude/gh-account.txt` is not a bypass but a change of what the repository expects.

## Limits

- **The commit author is not checked.** `git config user.email` is a separate knob from the token: the active account and the author email can disagree without this hook noticing. A commit can therefore still land with the wrong author while the push itself goes out as the right account. Adding it would double the configuration format, and it was not one of the accidents this hook was built for.
- **A push inside a command substitution is missed.** `echo $(git push)` is not caught, because the segment begins with `echo`. The gap runs in the permissive direction on purpose — this guards against a mistake, not against someone working around it.
- **Only `github.com`.** The hostname is fixed, so a GitHub Enterprise host is not examined.
- **One expected account, not a list.** A repository legitimately pushed from either of two accounts has to use the env bypass each time.
- **Inference can be wrong about intent.** A repository you own but deliberately push to as another account — a bot, a second account added as a collaborator — is blocked with no configuration having asked for it. It fails loudly and the message names both ways out, but this is a false-positive class that declaring-only did not have.
- **Only `origin`.** `git push upstream` is judged against `origin`, and a repository whose `origin` is a fork of somewhere else is judged by the fork's owner — usually right, and not checked. Where `origin` has a separate push URL, that is the one read, since it is what `git push` targets.
- **The literal `tokenSource` value for an env-supplied token is unverified.** The hook prints whatever `gh` reports rather than matching a guessed word, so the message stays correct either way.

## Verification

[`plugins/harness-core/scripts/verify-gh-account-guard.sh`](../../plugins/harness-core/scripts/verify-gh-account-guard.sh) — 45 assertions across 30 cases.

**The suite does not call the real `gh`.** It cannot: `gh auth status` makes a network call, and its answer depends on whoever is logged in on the machine running the suite — either one would have the verifier reporting on something other than the hook. A stub `gh` prints JSON frozen from the actual `--active --json hosts` output of **gh 2.89.0**, with `login` and `tokenSource` driven by environment variables.

The `gh`-absent case needs `jq` present and `gh` absent at the same time, so `PATH=/nonexistent` cannot serve it — that removes `jq` too and the wrong branch fires. It gets a directory holding explicit absolute links to only the five external tools the hook uses (`cat`, `jq`, `grep`, `tr`, `git`). **The absolute-path check there is load-bearing:** a relative link makes a dangling self-referential symlink, `grep` then fails inside the gate, `caught` stays empty, and the hook exits 0 — so the case reports PASS while never reaching the branch it exists to test. It was observed doing exactly that.

The two self-disabling branches each assert **which** tool they reported missing. Both messages begin `gh-account-guard:`, so matching that prefix alone would let the `gh` case pass while `jq` was the thing actually missing.

The three boundary cases that earn their keep are `echo "git push"`, the commit message mentioning a push, and `git pushx` — the false positives that would get this hook switched off. `git push` as the *expected* account is asserted too: without it the hook could be blocking everything and the suite would still be green.

```
bash plugins/harness-core/scripts/verify-gh-account-guard.sh
```

## Related

- Hook script: [`plugins/harness-core/hooks/gh-account-guard.sh`](../../plugins/harness-core/hooks/gh-account-guard.sh) (not installed into the consumer tree — loaded from the plugin cache)
- Registration: [`plugins/harness-core/hooks/hooks.json`](../../plugins/harness-core/hooks/hooks.json)
- Configuration template: [`declarative/templates/gh-account.txt`](../../plugins/harness-core/declarative/templates/gh-account.txt)
- The anchoring contrast: [`ai-attribution-guard`](ai-attribution-guard.md) — same subcommand family, deliberately wide gate, and the reason that is safe there
- The default-off precedent: [`protected-paths`](protected-paths.md) — same absent-file-is-the-off-switch stance, opposite source-resolution rule
- What a repository that declared nothing gets instead: the identity line in Step 5 of the [`pr-create`](../../plugins/harness-core/skills/pr-create/SKILL.md) skill
- The ownership model (managed vs template, and what a reinstall overwrites): the header comment in [`harnessctl`](../../plugins/harness-core/bin/harnessctl)

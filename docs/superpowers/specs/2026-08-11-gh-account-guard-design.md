# gh-account-guard — design

Status: approved, not yet implemented. Date: 2026-08-11.

A blocking hook that refuses `git push`, `gh pr create` and `gh pr merge` when the
active GitHub account is not the one this repository expects.

## 1. The problem

A developer with two `gh` accounts moves between them with `gh auth switch`. Two
accidents follow, and both were named as real by the person who asked for this.

- **A PR or commit lands under the wrong identity.** The active account happens to
  have write access to the repository, so the push succeeds and the PR opens — as
  the wrong person. Nothing fails, and it is found afterwards.
- **A push or PR is refused for lack of access.** The active account has no rights
  here. The command fails with a 403 that does not say *why*, and an agent that
  misreads the cause starts inventing detours.

The mechanism that makes the first one silent is worth stating, because it is not
obvious. `gh` installs itself as git's credential helper
(`credential.https://github.com.helper = !gh auth git-credential`), so `git push`
authenticates as whatever account is **active**. Meanwhile `git config user.email`
is a separate value, usually global. The token and the author are two independent
knobs, and nothing in the harness looks at either.

Today the harness has no notion of account identity at all: nothing in
`declarative/rules/`, no hook, no line in `session-brief`, no row in the
`docs/agent-layer.md` §7 backlog. `settings-fragment.json:50-53` puts
`Bash(gh pr:*)` in `allow`, so the agent opens pull requests without ever
establishing who it is speaking as.

## 2. Why not the free version

The cheap implementation reads `~/.config/gh/hosts.yml`, whose host-level `user:`
key is the active account. It costs nothing and needs no network.

It is rejected for two reasons.

- **It is wrong in the case that matters.** When `GH_TOKEN` or `GITHUB_TOKEN` is
  set, `gh` uses that token and `gh auth switch` has no effect — but `hosts.yml`
  still names the old account. A guard about mistaken identity that reports a
  confident wrong answer exactly when identity is confused is worse than no guard.
- **jq cannot read YAML.** The remaining option is grep-parsing a YAML file, which
  is the class of part the hook contract exists to keep out ([ADR-0002](../../adr/0002-hook-contract.md)).

`gh auth status` is authoritative, and it does not have to be read as prose:
`--active --json hosts` returns exactly the fields needed, including a
`tokenSource` that makes the env-token case **explicitly detectable** rather than
merely honestly described.

```json
{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com",
  "login":"chpark-ML","tokenSource":"keyring","scopes":"...","gitProtocol":"https"}]}}
```

Two measured properties matter. It takes **~0.5 s**, because it validates the
token against the API — too slow for every Bash call, fine once the command has
already been identified as a push or a PR. And **under `--json` it exits 0
regardless of any authentication issue** (its own help says so), so the hook reads
the payload and never the exit code.

## 3. Decision

`gh auth status` behind a narrow command gate. The ordering of the checks is the
design: the expensive step is last, and the common case exits before it.

```
1. jq absent                        → one line to stderr, exit 0
2. not Bash / empty / not caught    → exit 0        # almost always ends here, free
3. no expected account declared     → exit 0        # off by default
4. gh absent                        → one line to stderr, exit 0
5. active account == expected       → exit 0
6. mismatch                         → exit 2
```

Steps 1 and 4 follow the contract's self-disabling rule: a hook whose dependency
is missing announces itself once and gets out of the way. A missing hook must not
block work.

Step 5 reads the active login with one command and one jq expression:

```bash
active="$(gh auth status --active --hostname github.com --json hosts 2>/dev/null \
  | jq -r '.hosts["github.com"][0].login // empty')"
```

An empty `active` means gh answered but named nobody. That is not an identity
mismatch, so it exits 0 and lets git report the real problem. `state` is likewise
not consulted: a broken token fails loudly on its own, and this hook is only ever
answering *which account*.

## 4. Configuration

Three sources, resolved in order — **first match wins, no union**:

```
1. HARNESS_GH_ACCOUNT                      # one-shot, scoped to a single shell
2. <project>/.claude/gh-account.txt
3. <user config>/gh-account.txt            # $CLAUDE_CONFIG_DIR, else ~/.claude
```

One value: the account login, one line, `#` comments and blank lines ignored.

**This deliberately differs from `protected-paths`, which unions its sources.**
There, more protection is safer, so union is the right direction. Here a union
would mean "either account is fine", which weakens the guard on purpose. A
user-level default with a per-repository override is also the shape the problem
actually has: one account is normal, and specific repositories are the exception.

There is no separate off switch. **The absent file is the off switch** — the same
default-off stance `protected-paths` takes, for the same reason: a generic harness
cannot guess which account a given repository wants, and a guard with an invented
default blocks the wrong thing and teaches people to ignore it. When a push under
the other account is genuinely intended, source 1 is the way through, and the
block message says so.

## 5. The catch gate

The catch list is `git push`, `gh pr create`, `gh pr merge` — the commands behind
the two accidents in §1. `gh issue create` and `gh release create` also publish
under an identity, but neither has happened, so neither is included
([`CLAUDE.md`](../../../CLAUDE.md) §7).

**The gate must be anchored, and this is where it departs from an existing hook.**
`ai-attribution-guard` matches its subcommands with a deliberately unanchored
regex, and [its document](../../hooks/ai-attribution-guard.md) explains why that
is safe: "a wide gate is harmless — a command with no attribution passes it and
exits 0 anyway." That reasoning does not transfer. This hook blocks on the gate
itself, so a wide gate produces false positives, and a check that cries wolf gets
switched off — which is the same as no check at all
([ADR-0003](../../adr/0003-verification-mandate.md)).

So: split the command on `;`, `&&`, `||`, `|` and newline, and within each
segment require the match to start at the **beginning** of the segment.

- `echo "git push"` — the segment begins with `echo`. Passes.
- `git commit -m "... git push ..."` — the segment begins with `git`, but the
  subcommand is `commit`. Passes.
- `git -C /elsewhere push` — caught. Global options between `git` and the
  subcommand must be skipped, exactly as `ai-attribution-guard` learned to do
  after `git -C <repo> commit` slipped past a simpler pattern.
- `git pushx` — not `push`. Passes.

One gap is accepted, and it runs in the permissive direction: a push hidden inside
a command substitution — `echo $(git push)` — is not caught, because the segment
begins with `echo`. This is a guard against a mistake, not against someone working
around it, and `protected-paths` documents the same kind of gap for the same
reason.

## 6. Block message

The consumer cannot open the hook file — it lives in the plugin cache — so the
message is the whole interface. It carries what was caught and how to get past it.

```
gh-account-guard: active GitHub account is "work-acct", but this repo expects "chpark-ML".

  caught:   gh pr create --title ...
  active:   work-acct   (gh auth status)
  expected: chpark-ML   (.claude/gh-account.txt)

Switch, then retry:     gh auth switch --user chpark-ML
Or proceed as active:   HARNESS_GH_ACCOUNT=work-acct <command>

docs/hooks/gh-account-guard.md
```

The `expected:` line names **which** of the three sources supplied the value, so a
surprising expectation can be traced without guessing.

When `tokenSource` is not the keyring, the `active:` line says so — `(from
GITHUB_TOKEN)`. That is the case where `gh auth switch` appears to do nothing, and
being told beats discovering it.

## 7. Verification

`scripts/verify-gh-account-guard.sh`, using `run_case` / `expect` / `expect_match`
from `_verify-lib.sh`. Twelve cases across the three required kinds.

**no-op** — input the hook must not touch:

1. `git status` with an account declared → pass, gate does not match
2. `gh pr view 12` → pass, read-only subcommand
3. `git push` with **nothing declared** → pass, default-off

**block** — exit 2 with the account named:

4. `git push` under a mismatched declaration
5. `gh pr create --title x` under a mismatch
6. `gh pr merge 3` under a mismatch

**boundary** — resembles what is blocked, and must pass:

7. `echo "git push"` — segment begins with `echo`
8. `git commit -m "remember to git push"` — subcommand is `commit`
9. `git pushx` — word boundary
10. `git push` with the declaration **matching** the active account — the happy
    path, and the one an author forgets to assert
11. `gh` absent from PATH, **with an account declared** — passes with one stderr
    line, does not block. The declaration is what makes this case reach step 4 at
    all; without it step 3 exits first and nothing is printed
12. `HARNESS_GH_ACCOUNT` set to the active account, overriding a mismatched file

Case 7 and 8 are the ones that earn their keep. They are the false positives that
would get this hook switched off.

The suite must pass under the bash 3.2 floor: `make verify BASH=/bin/bash`.

## 8. Artifacts

`CLAUDE.md` §2 names six. Three more come from how the installer and the published
check count actually work.

| # | File | Note |
|---|---|---|
| 1 | `plugins/harness-core/hooks/gh-account-guard.sh` | `catches` / `scope` / `bypass` in the header comment |
| 2 | `plugins/harness-core/scripts/verify-gh-account-guard.sh` | the 12 cases of §7 |
| 3 | `docs/hooks/gh-account-guard.md` | |
| 4 | `plugins/harness-core/hooks/hooks.json` | fourth entry under the existing `Bash` matcher |
| 5 | `plugins/harness-core/declarative/templates/gh-account.txt` | comments only, so an install leaves the guard off |
| 6 | `plugins/harness-core/bin/harnessctl` | `addt` at user and project scope (near lines 229–234) and an inactive hint (near 193–195), both following `protected-paths.txt` |
| 7 | `docs/agent-layer.md` | hooks 6 → 7, blocking 4 → 5 |
| 8 | `plugins/harness-core/.claude-plugin/plugin.json` | 1.11.0 → 1.12.0 |
| 9 | `README.md` and `README.ko.md` | `badge/checks-NNN`, settled by `make verify-all` |
| 10 | `plugins/harness-core/declarative/settings-fragment.json` | line 53 allows the **exact string** `Bash(gh auth status)`; `--active --json hosts` does not match it and would prompt. Widen to `Bash(gh auth status:*)` |

Item 6 touches the installer, which makes `scripts/verify-install.sh` the gate —
in particular the property that **`settings.json` after uninstall is canonically
identical to the original**. A new template must be registered in the manifest's
`template` tier so that uninstall keeps it by default and `--purge-templates`
removes it.

The two READMEs must move together; they are a mirror pair
([`CLAUDE.md`](../../../CLAUDE.md) §8).

## 9. Companion changes

- **`pr-create` Step 5** gains one identity line before the push, so that a
  repository which declared nothing still gets the fact surfaced. The skill's
  `description` is untouched, so its trigger eval does not need re-measuring.
- **`.claude/harness-gaps.md`** gets two entries, written in the same turn as the
  work: the `user.email` / active-account mismatch as occurrence 1, and the
  deliberate decision to pass §7's occurrence gate for this hook.

## 10. Out of scope

- **`git config user.email`.** "A commit under the wrong identity" is strictly the
  author email, not the token, and the two are independent — on the machine that
  prompted this, the active account is `chpark-ML` while `user.email` is a
  personal address. It is still left out: it was not one of the accidents named,
  and folding it in doubles the configuration format and the case count. It goes
  in the ledger as occurrence 1 instead.
- **Reacting to a mid-session `gh auth switch`.** A PreToolUse hook reads the live
  state on every matched command, so it is correct without needing to be told.
  Extending `session-brief` would only cover session start, which is the one
  moment the guard does not need help.
- **Deriving the expected account from the git remote.** The owner of an org
  repository never equals a user login, and resolving membership needs a network
  call inside a hook.
- **This repository installing the guard on itself.** It cannot install onto
  itself, and is not protected by its own hooks ([`CLAUDE.md`](../../../CLAUDE.md)
  §6). Verification here happens through case 1–12, not through a live config.

## 11. The §7 note

[`CLAUDE.md`](../../../CLAUDE.md) §7 admits a new hook only for a problem that has
happened twice, with candidates held in the `docs/agent-layer.md` backlog. This
hook is built without that count being established; the requester chose to pass
the gate knowingly. The PR body records the choice under `## Notes`, and the
ledger records it too — so that the next person reads a decision rather than
inferring a precedent.

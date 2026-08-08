# ai-attribution-guard

Keeps AI authorship marks out of git history and GitHub.

## Behaviour

Registered on `PreToolUse`, matcher `Bash` ([`hooks.json`](../../plugins/harness-core/hooks/hooks.json)).

1. If `tool_name` is not `Bash`, or the command is empty, exit 0.
2. Fold the command to lowercase (`$lc`) and first ask **whether this command writes a message**. If not, exit 0. The gate:

   ```
   git( +(-c +[^ ]+|--[a-z][^ ]*|-[a-z]+))* +(commit|tag)|gh +(pr|issue) +(create|edit|comment)|gh +release +(create|edit)
   ```

   The part that allows global options between `git` and the subcommand is the point. The earlier, simpler `git +commit` match let `git -C <repo> commit ...` through untouched. Because `$lc` is lowercased, `-C` arrives as `-c`, so the single `-c +[^ ]+` covers both `-C <path>` and `-c <name>=<value>`. `git tag` is in scope because annotated tags carry messages; `comment` and `release` are there because, like `create`, they publish prose to GitHub. A wide gate is harmless — a command with no attribution passes it and exits 0 anyway.
3. Check three shapes in order. On a match, name what was caught on stderr and exit 2.

`includeCoAuthoredBy: false` in `settings.json` disables Claude Code's built-in trailer. This hook covers the remaining path: a message the model wrote by hand. It reacts to **the command itself**, so it still applies when `--no-verify` skips commit-msg hooks.

Without `jq` it prints one line to stderr and self-disables with exit 0.

## Patterns

| Shape | Checked against | Regex / string |
| --- | --- | --- |
| Co-author trailer | lowercased copy | `co-authored-by:.*(claude\|noreply@anthropic)` |
| Generated-with footer | lowercased copy | `generated with .{0,20}claude` |
| Robot emoji | **the original** | `🤖` |

The first two read the lowercased copy and are therefore case-insensitive (`CO-AUTHORED-BY: CLAUDE` is blocked too). Only the third reads the raw `$cmd`, because an emoji has no case to fold.

The trailer rule looking for `noreply@anthropic` rather than `anthropic` alone is the load-bearing detail. A human colleague with an `@anthropic.com` address is a genuine co-author and that trailer has to survive. Only the bot address is targeted.

## What passes

A legitimate mention is not attribution. All of these pass deliberately.

- **The filename `CLAUDE.md`** — `git commit -m "Update CLAUDE.md language policy"`.
- **The `.claude/` directory path** — `git commit -m "Move rules under .claude/rules/harness"`.
- **References to the `anthropic` SDK or API backend** — `git commit -m "Pin anthropic to 0.40 for the tool_use fix"`.
- **A human co-author trailer** — `Co-Authored-By: Jane Doe <jane@example.com>`. What is blocked is AI attribution, not co-authorship.
- **A human colleague at Anthropic** — `Co-Authored-By: Jane <jane@anthropic.com>` passes. The bot address `noreply@anthropic.com` is what is blocked.
- **Commands that write no message** — `grep -rn "Co-Authored-By: Claude" .` never reaches the gate, and `git tag -l` reaches it with no prose to check and exits 0. The first is a required property: *searching for* trailers this hook blocks must not itself be blocked.
- **An ordinary commit** — `git commit -m "Add retry to the upload path"`.

## Bypass

**None.** This is a policy, not a threshold, and an environment-variable escape hatch becomes standard procedure the moment it exists. On a false positive (see Limits), rephrase and retry; if the pattern itself is wrong, fix it in the harness repository.

**There is no copy in the consumer tree to fix.** Hooks ship in the plugin and load from the plugin cache — true for all six documented here. So a block message cannot be traced to a file in your own repository. To read the script, look at `plugins/harness-core/hooks/` in [agent-harness](https://github.com/chpark-ML/agent-harness), or inspect the installed plugin via `/plugin`. That is also where the fix goes.

## Limits

The two false positives below are deliberate, and the script header says so.

- **An unrelated 🤖 is blocked.** `git commit -m "fix the 🤖 emoji rendering bug"` exits 2 even though the emoji is the subject. There is no context judgement. It stays because this rule is **the only one that catches a generated-with footer written without the word "Claude"** — remove it and that shape escapes entirely.
- **`generated with … claude` in prose is a false positive.** `git commit -m "note that fixtures were generated with the claude api"` is not attribution and is blocked.

Remaining gaps:

- **A person named Claude is still blocked.** `Co-Authored-By: Claude Dupont <claude.dupont@example.com>` exits 2. The address-based false positive was fixed; the name-based one cannot be — searching a trailer value for `claude` cannot separate a real name from a model name. It is pinned in the verifier as a **known-limitation case that asserts the block**, so if the behaviour changes the test says so.
- **Commands outside the gate.** `git merge -m`, `git notes add -m` and `git revert` carry messages and are not checked. Coverage is `git commit`, `git tag`, `gh pr|issue create|edit|comment`, and `gh release create|edit`.
- **Messages arriving via stdin or a file are invisible in principle.** `git commit -F msg.txt` has no message text in the command string, so this hook cannot see it. The same is true of `git commit` with no `-m`, which opens an editor.

## Verification

[`plugins/harness-core/scripts/verify-ai-attribution-guard.sh`](../../plugins/harness-core/scripts/verify-ai-attribution-guard.sh) — 33 cases. The four "gate evasion" cases (`git -C`, `git -c`, `git --no-pager`, an uppercase trailer) are the real incidents that gave the gate regex its current shape.

The trailer boundary is pinned in three directions — an `@anthropic.com` human colleague passes, the bot address `noreply@anthropic` is blocked even without the word "Claude", and a person named Claude is **asserted to be blocked**. The last pins a false positive that cannot be fixed, so the Limits section above cannot drift away from the code.

```
bash plugins/harness-core/scripts/verify-ai-attribution-guard.sh
```

## Related

- Hook script: [`plugins/harness-core/hooks/ai-attribution-guard.sh`](../../plugins/harness-core/hooks/ai-attribution-guard.sh) (not installed into the consumer tree — loaded from the plugin cache)
- Registration: [`plugins/harness-core/hooks/hooks.json`](../../plugins/harness-core/hooks/hooks.json)
- The paired scalar `includeCoAuthoredBy: false`: [`declarative/settings-fragment.json`](../../plugins/harness-core/declarative/settings-fragment.json) — unlike the hook, merged into `settings.json` by `harnessctl init` rather than carried by the plugin. They are two routes for one policy: the scalar disables the built-in attachment, the hook stops the hand-written one.
- The policy itself, R2: [`declarative/rules/core/workflow.md`](../../plugins/harness-core/declarative/rules/core/workflow.md)
- Sibling hooks sharing the `Bash` matcher: [secret-scrubber](secret-scrubber.md), [large-file-veto](large-file-veto.md)

# secret-scrubber

Blocks Bash commands carrying a literal secret.

## Behaviour

Registered on `PreToolUse`, matcher `Bash` ([`hooks.json`](../../plugins/harness-core/hooks/hooks.json) — the second `PreToolUse` block, which runs secret-scrubber → large-file-veto → ai-attribution-guard in that order).

1. If `tool_name` is not `Bash`, or `tool_input.command` is empty, exit 0 immediately.
2. Run `grep -qE` over the `PATTERNS` array in declaration order. **The first match decides** — array order is priority, and the label carried in the block message is the first match's.
3. On a match, exit 2; otherwise exit 0. The stderr from exit 2 is returned to the model as feedback, so the message names both the kind detected and the fix.

**It does not scan file contents.** Only Bash commands. Fixtures, documentation and tests legitimately contain key-shaped strings, and a guard that produces false positives eventually gets switched off (script header).

Without `jq` it prints one line to stderr and self-disables with exit 0.

## Patterns

| Kind | Regex |
| --- | --- |
| Anthropic API key | `sk-ant-api03-[A-Za-z0-9_-]{40,}` |
| OpenAI scoped key (proj/svcacct/admin) | `sk-(proj\|svcacct\|admin)-[A-Za-z0-9_-]{40,}` |
| OpenAI legacy API key | `sk-[A-Za-z0-9]{40,}` |
| GitHub personal access token | `ghp_[A-Za-z0-9]{36,}` |
| GitHub token (oauth/user/server/refresh) | `gh[ousr]_[A-Za-z0-9]{36,}` |
| GitHub fine-grained token | `github_pat_[A-Za-z0-9_]{40,}` |
| Slack token | `xox[abprs]-[A-Za-z0-9-]{20,}` |
| AWS access key ID | `AKIA[0-9A-Z]{16}` |
| AWS temporary access key | `ASIA[0-9A-Z]{16}` |
| Google API key | `AIza[0-9A-Za-z_-]{35}` |
| PEM private key block | `-----BEGIN[A-Z ]*PRIVATE KEY-----` |

Plus one vendor-agnostic env-assignment rule:

```
(API_KEY|APIKEY|SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE_KEY|ACCESS_KEY)=["']?[A-Za-z0-9+/=._-]{12,}
```

The name part is not anchored, so it matches as a substring — `MYSQL_PASSWORD=`, `DEPLOY_PRIVATE_KEY=` and `APP_SECRET=` all hit. The value must be a literal of twelve characters or more.

**The two OpenAI entries having different character classes is not a mistake.** The scoped family (`sk-proj-`, `sk-svcacct-`, `sk-admin-`) really does contain `_` and `-`, while legacy `sk-` is pure base62. Different formats, different classes — What passes, below, records what happened when they were "unified".

## What passes

- **`API_KEY=$REAL_KEY <command>`** and **`TOKEN=$(cat ~/.token) ...`** — a literal `$` is outside the value character class, so they do not match. This is by design: the fix the block message recommends has to pass on its own. "Fixing" this would block the recommended fix.
- **Values under twelve characters** (`DEBUG_TOKEN=ab12`) and **long values whose name is not in the list** (`OUTPUT_PATH=/very/long/path/to/output.json`).
- **Prose that merely mentions `sk-`** — nothing matches unless it is key-shaped.
- **A long kebab-case identifier beginning with `sk-`** — `git switch -c sk-refactor-the-whole-data-loading-layer-for-real` passes, because the legacy `sk-` class contains no `-`. At one point the legacy class was widened to `[A-Za-z0-9_-]` on the theory that differing from the scoped one looked like a typo, and branch names like that were all mistaken for keys and blocked. Widening bought nothing — no legacy key format contains an underscore. Two cases are pinned as allow, so do not "tidy" this again.
- **Tools other than Bash** — `Read` and `Write` are not in the matcher at all.

## Bypass

**None.** There is deliberately no environment-variable escape hatch. Once a literal has reached the shell, the value is already in history, the process table and logs; the only real remediation afterwards is rotation, and a switch to turn this off becomes standard usage the moment it exists. There is one procedure: rotate the value, then reissue the command through a shell variable or a secret manager.

## Limits

- **Space-separated secrets are not caught.** The rule only sees `name=value`. `aws configure set aws_secret_access_key <value>` is the canonical way to plant long-lived credentials and the one form that never goes through an environment variable — and it passes. Flag forms (`--api-key <value>`) are the same. Judging the value without a name would mean treating any long base62 string as a secret, which catches every hash, UUID and path.
- **Obvious placeholders are blocked too.** `TOKEN=REPLACE_ME_BEFORE_RUN`, `API_KEY=your-key-here`, and AWS's own documentation example `AKIAIOSFODNN7EXAMPLE`. The last is particularly irritating: the header declines to scan file contents *because fixtures legitimately hold key-shaped strings*, and then blocks creating that fixture from the shell. A placeholder deny-list would fix it and would itself become maintenance, so it stays a known friction.
- **The env-style value class includes `/` and `.`,** so any long literal whose name matches is blocked even when it is not a secret (`TOKEN=/very/long/path/to/output.json` → block). A deliberately accepted false positive — narrowing the class lets base64 and dot-separated tokens through (script header).
- Exfiltration through a file write or an MCP tool rather than a command is out of scope — the price of the no-file-scanning decision above.
- **Fixtures have to be fake in a way that is still *detectable*.** Pushing this repository public was refused by GitHub push protection, which judged our Slack token fixture to be a real secret (`evals/incidents.sh`, `verify-secret-scrubber.sh`). Our regex only looks for `xox[abprs]-` plus twenty characters while GitHub inspects real token structure, so the value has to split the two judgements — `xoxb-EXAMPLE-NOT-A-REAL-TOKEN-000000` trips ours and not the scanner's. A fixture that tests a secret detector looks like a secret by construction, so every new pattern has to be checked against this conflict.

## Verification

[`plugins/harness-core/scripts/verify-secret-scrubber.sh`](../../plugins/harness-core/scripts/verify-secret-scrubber.sh) — 37 cases.

The `sk-` family is now pinned in both directions: the three scoped formats (`proj`, `svcacct`, `admin`) and legacy base62 block, while two long kebab-case identifiers starting with `sk-` pass. With only block cases in the widening direction, that regression was invisible — adding the opposite direction is what makes it hold.

```
bash plugins/harness-core/scripts/verify-secret-scrubber.sh
```

## Related

- Hook script: [`plugins/harness-core/hooks/secret-scrubber.sh`](../../plugins/harness-core/hooks/secret-scrubber.sh) (not installed into the consumer tree — loaded from the plugin cache)
- Registration: [`plugins/harness-core/hooks/hooks.json`](../../plugins/harness-core/hooks/hooks.json)
- Sibling hooks sharing the `Bash` matcher: [large-file-veto](large-file-veto.md), [ai-attribution-guard](ai-attribution-guard.md)
- The complementary permission `deny`: `Read(./.env*)`, `Read(./secrets/**)` and `Read(./**/.credentials*)` in [`declarative/settings-fragment.json`](../../plugins/harness-core/declarative/settings-fragment.json) — those block the paths that *read* a secret, this hook blocks the path that *types* one. The fragment is merged by `harnessctl init`.
- `harnessctl doctor` feeds this hook a sample `AKIA…` key directly to confirm it blocks — the fastest way to see whether the plugin actually loaded.

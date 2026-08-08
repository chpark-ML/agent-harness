# large-file-veto

Blocks a `git add` that would stage a file over the threshold.

## Behaviour

Registered on `PreToolUse`, matcher `Bash` ([`hooks.json`](../../plugins/harness-core/hooks/hooks.json)).

1. If `tool_name` is not `Bash`, or the command contains no `git add`, exit 0.
2. Split the command at statement separators (`;`, `&`, `|`, newline) with `awk`, then extract **every `git add` in every segment** and tokenise with `read -r -a`. Tokens fall into three groups — `-A`/`--all`/`.` enumerate everything, `-u`/`--update` enumerate modified files, and any remaining non-flag token is an explicit path (one layer of surrounding quotes stripped).
3. Collect candidate files. Full enumeration uses `git ls-files --others --modified --exclude-standard`, modified enumeration uses `git ls-files --modified`, and an explicit path that is a directory expands via `find <dir> -type f -not -path '*/.git/*'`. The base directory is `CLAUDE_PROJECT_DIR`, or `pwd` when unset.
4. Deduplicate, `stat` each candidate, and if any exceeds the threshold print the list to stderr and exit 2. Otherwise exit 0.

Removing a large blob after it has been staged requires a history rewrite. That is why this blocks at staging time.

**Multiple `git add` calls in one command are order-independent.** Every one is checked, so a large file is caught wherever it sits. Matching uses `(^|[[:space:]])git[[:space:]]+add` for word boundaries, so a string like `legit add` is not mistaken for `git add`.

Without `jq` it prints one line to stderr and self-disables with exit 0.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `HARNESS_LARGE_FILE_BYTES` | `10485760` (10 MiB) | size in bytes above which to block |
| `CLAUDE_PROJECT_DIR` | `$(pwd)` | base for resolving relative paths and running `git ls-files` |

There is no config file. The threshold works in both directions — raise it and things pass, set `HARNESS_LARGE_FILE_BYTES=1` and small files are blocked (the verifier checks both).

## What passes

- **`git add` with no arguments** — the candidate list is empty.
- **Paths that do not exist** — skipped silently when `[ -f "$abs" ]` fails.
- **Symlinks** — filtered by `[ ! -L ]` before the size check. Links are not followed.
- **`git add -A` where the large file is gitignored** — `--exclude-standard` keeps it out of the candidates, which matches what `git add` itself would stage.
- **Commands without `git add`** — `git status && git commit` is not examined.

## Bypass

In order of preference: (1) track the file with Git LFS, (2) add the path to `.gitignore`, (3) raise the threshold for one command — `HARNESS_LARGE_FILE_BYTES=<bytes> <command>`.

(3) is a deliberate escape hatch in this hook. Unlike secret-scrubber, "a large file" has legitimate site-specific exceptions, and the problem is repository bloat rather than an irreversible disclosure.

## Limits

A parser that fully understands the shell would be larger than the hook. Everything below is accepted as the price of that.

- **`-A` ignores any pathspec beside it.** `git add -A small.txt` stages only `small.txt`, but the hook enumerates the whole worktree and blocks on an unrelated large file, because seeing `-A` turns on `enumerate_all` and explicit paths are then not consulted.
- **`git -C <dir> add` is not detected.** Its sibling [ai-attribution-guard](ai-attribution-guard.md) does handle `git -C ... commit`, and the difference is principled rather than an omission: that hook inspects **command text**, which means the same thing wherever it runs, while this one **resolves** every argument against a directory on disk. Honouring `-C` here would mean moving the size lookups to the same base, and honouring it halfway would measure the size of the wrong files.
- **A quoted path containing spaces is split at the spaces** — `read -r -a` cuts on IFS.
- **An already-tracked file of the same size is blocked too** — only size is considered, not whether the file is new.
- **`git add --dry-run <big>` is blocked.** `--dry-run` is in the ignored-flags list, so only the path survives, and a command that stages nothing still exits 2.
- **Explicit paths do not consult `.gitignore`.** `git add big.bin` is blocked even when `big.bin` is gitignored, so fix (2) from the block message does not release the hook in that form.

## Verification

[`plugins/harness-core/scripts/verify-large-file-veto.sh`](../../plugins/harness-core/scripts/verify-large-file-veto.sh) — 40 cases (6 no-op, 2 under threshold, 6 blocked, **5 ordering regressions**, 2 threshold in both directions, 4 block message). Fixtures use a real `git init` repository and an 11 MiB file built with `dd`, because this code path actually calls `git ls-files`.

The five ordering cases pin "caught wherever it sits": large file in the **first** of two `git add` calls, in the **second**, split by `;`, both small, and the `legit add` non-match. The first four are regression tests for a version that checked only the last `git add` and let `git add big.bin && git add ok.txt` through.

```
bash plugins/harness-core/scripts/verify-large-file-veto.sh
```

## Related

- Hook script: [`plugins/harness-core/hooks/large-file-veto.sh`](../../plugins/harness-core/hooks/large-file-veto.sh) (not installed into the consumer tree — loaded from the plugin cache)
- Registration: [`plugins/harness-core/hooks/hooks.json`](../../plugins/harness-core/hooks/hooks.json)
- [`declarative/settings-fragment.json`](../../plugins/harness-core/declarative/settings-fragment.json) has `Bash(git add:*)` in the permission `allow` tier, which makes this hook the only brake on `git add`.
- Sibling hooks sharing the `Bash` matcher: [secret-scrubber](secret-scrubber.md), [ai-attribution-guard](ai-attribution-guard.md)

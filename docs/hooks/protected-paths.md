# protected-paths

Blocks tool calls that touch an **absolute path** under a protected prefix, unless an explicit carve-out allows it.

## Behaviour

Registered on `PreToolUse`, matcher `Read|Write|Edit|NotebookEdit|Glob|Grep|Bash` ([`hooks.json`](../../plugins/harness-core/hooks/hooks.json) — the first `PreToolUse` block, which holds this hook alone).

1. Read the list of protected prefixes. With none configured, **exit 0 silently** — it is off by default.
2. Extract the paths to check, per tool: `Read`/`Write`/`Edit` use `tool_input.file_path` (falling back to `.path`), `NotebookEdit` uses `notebook_path`, `Glob`/`Grep` use `path`, and `Bash` splits the command on spaces, `"`, `'` and `=` and takes every token starting with `/`. Any other tool exits 0.
3. Skip paths that do not start with `/`. If any path is under a protected prefix and not under an allowed one, print it and exit 2. Otherwise exit 0.

It fills the gap that permission globs in `settings.json` cannot reach. Those globs are project-relative, so shared mounts, another team's export, and production data directories — anything addressed absolutely — are out of range.

**Shipping no defaults is the design.** A general-purpose harness cannot know which absolute paths matter, and a guard with invented defaults either blocks the wrong thing or teaches the habit of ignoring it.

Without `jq` it prints one line to stderr and self-disables with exit 0.

## Configuration

Configuration is read from **two locations** and combined — the project's `${CLAUDE_PROJECT_DIR:-.}/.claude/` and the user config directory `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/`. The hook behaves the same wherever it is installed, and machine-wide protection cannot vanish because some project has a list of its own — that would make the guard weakest in projects nobody configured.

| Target | Source | Format | How it combines |
| --- | --- | --- | --- |
| protected | `HARNESS_PROTECTED_PATHS` | **colon-separated** (like `PATH`) | **replaces** the files |
| protected | `<user>/protected-paths.txt` ∪ `<project>/.claude/protected-paths.txt` | one per line, `#` comments | **union** of the two; both ignored when the env var is set |
| allowed | `HARNESS_ALLOWED_PATHS` | **colon-separated** | **union** with the files |
| allowed | `<user>/allowed-paths.txt` ∪ `<project>/.claude/allowed-paths.txt` | one per line, `#` comments | union with each other and with the env var |

Protection replaces; permission unions. A one-off shell exception must not silently wipe a project's allow list, and conversely, if protection were a union there would be no way to *reduce* protection from the environment.

Both env variables are colon-separated, so **a prefix may contain spaces** — `HARNESS_PROTECTED_PATHS='/my data:/mnt/shared'` reads correctly as two prefixes.

> **Warning — the old space-separated syntax.** `HARNESS_PROTECTED_PATHS` used to be space-separated. The old form `'/a /b'` is now read as **one** prefix, `/a /b`, so neither `/a` nor `/b` is protected. A guard silently ceasing to guard because of config syntax is not an acceptable direction of failure, so the hook **warns on stderr when a value contains spaces and no colon** — `HARNESS_PROTECTED_PATHS is colon-separated, so '/a /b' is being read as ONE prefix. If you meant several, write '/a:/b'.` A correctly colon-separated value does not warn, even when its parts contain real spaces.

The two `.txt` files are **templates** installed by `harnessctl init` rather than carried by the plugin — the originals live in [`plugins/harness-core/declarative/templates/`](../../plugins/harness-core/declarative/templates/) and belong to the consumer once copied. `harnessctl` records them in the manifest as templates, so reinstalling does not overwrite them and `harnessctl uninstall` leaves them unless `--purge-templates` is given. Install location follows scope: `--scope project` puts them under `.claude/`, `--scope user` directly in the user config directory. What ships is comments only, so the hook is inactive immediately after install.

**The project directory is not implicitly allowed.** If the project sits under a protected prefix, say so in `.claude/allowed-paths.txt`. An implicit exception turns the guard off exactly where it was asked for.

## What passes

- **`/database`** — passes even with `/data` protected, because matching compares literally against `"$pre"` or `"$pre"/*` rather than testing a string prefix (the same holds for `/mnt/shared-old`). "Fixing" this would block every unrelated directory with a similar name.
- **Relative paths** (`data/local.csv`) and **Bash commands with no absolute path** (`npm test && git status`) — only absolute paths are inspected.
- **A config file containing only comments and blank lines** — zero declarations is the same as inactive.
- **Tools not in the list** (`Task` and others) — outside the matcher, and the script exits 0 at `*)`.
- **Paths under a carve-out** — with `/data` protected and `/data/project-x` allowed, `/data/project-x/out.json` passes while its sibling `/data/project-y` is blocked.

## Bypass

Three, and the block message lists them.

- this project needs standing access → add the path to `.claude/allowed-paths.txt`
- one shell, one time → `HARNESS_ALLOWED_PATHS=/p1:/p2 <command>`
- it should not have been protected → edit `.claude/protected-paths.txt`

## Limits

This is a guard against accidents, not against adversarial evasion.

- **There is no path normalisation, and the gap opens in the permissive direction.** `/tmp/../data/secret.csv` really does reach `/data` but **passes**, because the string does not start with the protected prefix. The same applies to doubled slashes, `//data/x`. The reverse case, `/data/../etc/passwd`, escapes `/data` yet matches the prefix and is blocked — that is a safe failure. Both directions are pinned as verifier cases so neither changes silently.
- **Relative paths are never inspected.** `../data/secret` after a `cd` does not look absolute and passes. The real backstop for paths that must be protected is a `deny` rule in `settings.json`; this hook sits on top of that as accident prevention.
- **Prefix matching only.** No globs, no regular expressions, no symlink resolution. A symlink pointing into a protected directory is not caught.
- **The Bash tokeniser is coarse.** It splits only on spaces, quotes and `=`, so a comma-joined path like `cp a,/data/x .` is missed. Conversely `cd /data` and `OUT=/mnt/shared/x.log` are caught.
- **Reads are blocked too.** `Read`, `Glob` and `Grep` are in the matcher, so even inspection is stopped. There is no mode that permits reading and blocks writing.

## Verification

[`plugins/harness-core/scripts/verify-protected-paths.sh`](../../plugins/harness-core/scripts/verify-protected-paths.sh) — 53 cases. Four fixture projects differing only in configuration (`none`, `commented`, `basic`, `carve`) make each case's configuration visible in its name.

User-level configuration is covered by five cases: blocking from the user list alone with no project config, a user carve-out applying, both lists in effect simultaneously (each direction), and an env protection override replacing **both files**.

The separator warning is pinned in both directions by four cases — a space-only value produces the warning regardless of whether it blocks, and a colon-separated value containing spaces is asserted **not** to warn via `expect_absent`.

Two of the seven boundary cases **assert that the missing normalisation passes**: `/tmp/../data/secret.csv` passes, `/data/../tmp/x` is blocked. Pinning the gap as a test keeps the behaviour from changing quietly and keeps the Limits section from drifting away from the code.

```
bash plugins/harness-core/scripts/verify-protected-paths.sh
```

## Related

- Hook script: [`plugins/harness-core/hooks/protected-paths.sh`](../../plugins/harness-core/hooks/protected-paths.sh) (not installed into the consumer tree — loaded from the plugin cache)
- Registration: [`plugins/harness-core/hooks/hooks.json`](../../plugins/harness-core/hooks/hooks.json)
- The complementary permission `deny`: entries like `Read(./.env*)` in [`declarative/settings-fragment.json`](../../plugins/harness-core/declarative/settings-fragment.json) are project-relative globs. This hook covers the absolute paths those globs cannot reach. The fragment is merged into `settings.json` by `harnessctl init`, not carried by the plugin.
- Configuration templates: [`declarative/templates/protected-paths.txt`](../../plugins/harness-core/declarative/templates/protected-paths.txt), [`declarative/templates/allowed-paths.txt`](../../plugins/harness-core/declarative/templates/allowed-paths.txt)
- The ownership model (managed vs template, and what a reinstall overwrites): the header comment in [`harnessctl`](../../plugins/harness-core/bin/harnessctl)

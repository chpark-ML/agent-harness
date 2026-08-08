# `harness-log` — the session history as one page

Renders every session this project has had into a single self-contained HTML
file: **what you asked for, and what came back.** Nothing else.

```bash
harness-log                  # session-log.html at the repo root
harness-log --limit 20       # only the most recent 20 sessions
harness-log --out ~/x.html   # somewhere else
harness-log --no-exclude     # leave .git/info/exclude alone
harness-log --project DIR    # a project other than the current one
```

It ships in `harness-core/bin/`. Claude Code puts that directory on the **Bash
tool's** `PATH`, so a session can run it directly. Your own terminal is a
separate `PATH`, so `install.sh` also writes a shim into `~/.local/bin` for
every executable in the plugin's `bin/` — resolving the newest installed
version at run time, because the plugin cache is versioned and `claude plugin
update` moves it.

## What it keeps, and what it drops

| Kept | Dropped |
|---|---|
| Your typed prompts | Every tool call and tool result |
| The last assistant message of each turn | Subagent (sidechain) transcripts |
| Timestamp, git branch, session id | Skill injections and system reminders |
| | Slash-command plumbing (`<command-name>…`) |
| | The body of a compaction hand-off |

**The exclusions are the design, not an economy.** `claude-mem` was kept out of
this harness for storing all tool I/O in a repository that runs
`secret-scrubber` ([agent-layer §3b](agent-layer.md)) — a log that swallows tool
output swallows whatever a command printed, which is precisely what the scrubber
exists to keep off the command line in the first place. The same objection would
apply to this page if it kept them, so it does not.

A compaction hand-off is a special case worth naming: it *arrives* as a user
message, but nobody typed it, and its body is a machine-written summary of the
tool work the page is built to leave out. The page keeps the marker — `context
compacted` — and discards the body, so the seam is visible without the contents
coming back in through the side door.

**The last assistant message is the answer.** Text emitted between tool calls is
the model narrating; the block after the last tool call is the result. Keeping
only that is what makes a 241-session history readable at 272 KB.

## How it finds the transcripts

Claude Code stores them under `~/.claude/projects/<slug>/*.jsonl`, where the
slug is the project's absolute path with every `/` and `.` replaced by `-`.
`CLAUDE_CONFIG_DIR` overrides the root.

The path used is the **logical** one — symlinks left alone. On macOS `pwd -P`
rewrites `/var` to `/private/var` and `/tmp` to `/private/tmp`, so resolving
first produces a slug that matches nothing. The tool tries the logical path,
falls back to the physical one, and if neither directory exists it says which
path it looked under rather than writing an empty page.

Sessions are ordered by their **first event**, not by filename (UUIDs sort
arbitrarily) and not by mtime (resuming an old session touches it).

## Regeneration, not accumulation

The page is rebuilt from the transcripts on every run and never appended to.
Two consequences worth knowing:

- A truncated or corrupted page is one re-run away from correct.
- Editing it by hand accomplishes nothing. Annotate somewhere durable instead —
  for research work that is `FINDINGS.md`, which is what the
  [`research-notes`](../plugins/harness-research/skills/research-notes/SKILL.md)
  skill maintains.

## git

By default the output filename is appended to `.git/info/exclude`, **not** to
`.gitignore`. The page is one developer's local artifact; adding it to a tracked
`.gitignore` commits a preference to everyone who clones the repository. If a
project decides the log should be shared, that is their edit to make.

`--no-exclude` skips this entirely.

## Requirements and failure modes

`jq` only — the same floor as the hooks ([ADR-0002](adr/0002-hook-contract.md)),
and bash 3.2 compatible. It exits non-zero and explains itself when there are no
transcripts, when `--limit` is not a number, and on an unknown flag. It is not a
hook: it blocks nothing and runs only when invoked.

## Verification

`plugins/harness-core/scripts/verify-harness-log.sh` — 44 checks, run by
`make verify`. They come in three kinds, and the third is the one that earns its
keep:

- **must appear** — the prompt, the final answer, the branch, fenced code as code
- **must not appear** — a secret in a tool result, a skill injection, a subagent
  transcript, a system reminder, a hand-off body, interim narration
- **boundary** — a human *talking about* `tool_result` and `system-reminder` is
  kept verbatim. A filter that censored the words as well as the blocks would
  pass every exclusion case above and still be wrong.

Plus a regression case for the assembly bug that only appeared once a session
held more than one turn, and a check that HTML in a prompt is escaped rather
than emitted.

Two of them exist because a branch that runs on one platform only is a branch
CI never runs: the symlink case forces the physical-path fallback by storing
the fixture under the resolved slug and asking for the logical one, and the
repeat-run case covers the *already ignored* path. Both were confirmed by
deleting the code they cover and watching only those cases fail.

# Output styles

An output style changes how Claude talks to you. It is not a rule file and not a
skill: Claude Code puts it in the **system prompt**, so it applies to every
response and cannot be forgotten halfway through a session.

This document covers the styles this harness ships and how to write another.
**Only one output style is active at a time**, which is why there is exactly one
here — a second would compete with the first rather than add to it, so the bar
for adding one is that it replaces `Report` for some consumer, not that it is
also useful.

## `Report`

`harness-core` ships `output-styles/report.md`, and `harnessctl` selects it by
writing `outputStyle` into your `settings.json`.

### Why it exists

`CLAUDE.md` §6 already says what a report must not do — a number with no
referent, a name used as if the reader knows it, a pointer to an earlier turn.
Those are rules about *content*, and they load as project context.

This style covers what §6 does not: **length and shape**, and **provenance**. The
two do not overlap, deliberately — the same rule written into two layers with
different precedence is a rule you can no longer reason about.

Three things it asks for:

- **The result opens the report.** Method, background, and the list of steps taken
  come after it, and only when they change what you do next.
- **A number arrives with its run** — the command, commit, config or file it came
  from, in the same sentence. This is the `ARTIFACTS.md` invariant applied to
  speech instead of to documents.
- **Measured and inferred are said apart**, and something unmeasured is named as
  unmeasured rather than quietly rounded up into a finding.

It also carries its own brevity clause, because Claude Code holds **exactly one
output style active at a time**: selecting this one turns the built-in `Concise`
off, so the brevity has to come from somewhere.

And it carries a stop: *brevity stops where correctness starts*. Failing output,
security warnings and confirmations for destructive actions keep their full
content. A style that shortens an error message is worse than no style.

### How it is selected

`plugins/harness-core/declarative/settings-fragment.json` carries the scalar:

```json
{ "scalars": { "outputStyle": "harness-core:Report" } }
```

**The name is namespaced.** A plugin's output style is registered as
`<plugin>:<style name>`, not by the bare name in its frontmatter.

Both halves were checked on Claude Code 2.1.246, with the plugin loaded straight
from the tree so nothing had to be installed first:

```bash
claude --plugin-dir plugins/harness-core \
  -p 'Quote verbatim the line in your system prompt that begins "# Output Style:".'
```

With `"outputStyle": "harness-core:Report"` that prints `# Output Style:
harness-core:Report`. With a bare `"outputStyle": "Report"` **no style loads and
nothing says so** — the session simply runs on the default. A wrong name here
does not fail, it evaporates, which is why the value has a case in
`scripts/verify-install.sh` rather than being left to review.

`harnessctl` writes a scalar **only when you do not already have that key**, and
`harness-manifest.json` records what it wrote so uninstall removes exactly that
and nothing else. So:

- You had no `outputStyle` → you get this one, and uninstall takes it back out.
- You had chosen a style → **yours is kept**, the installer says so on the way
  past, and uninstall never touches it.

That is the reason the style is not marked `force-for-plugin: true` in its
frontmatter. That field applies a style whenever the plugin is enabled and
overrides whatever you chose. `harness-core` is installed in every profile, so
using it would take every consumer's voice with no way out short of disabling
the plugin.

### Turning it off

Set `outputStyle` to something else, or delete the key:

```bash
# pick another style, including a built-in one
/config          # → Output style

# or edit the file harnessctl wrote — jq prints, so write the result back
tmp=$(mktemp) && jq 'del(.outputStyle)' ~/.claude/settings.json > "$tmp" \
  && mv "$tmp" ~/.claude/settings.json
```

Or run `harnessctl uninstall`, which removes the key along with everything else
the manifest records — it never removes a value you set yourself.

**The change applies on the next session.** Output style is part of the system
prompt, which Claude Code reads once at startup; editing the setting mid-session
does nothing until `/clear` or a restart. That is not a limitation of this
harness — it is how output styles work, and the same is true of `CLAUDE.md`.

## Writing another one

Add `plugins/<plugin>/output-styles/<name>.md`. Two rules the verifiers enforce:

- **Quote the `description` value.** An unquoted YAML scalar containing a
  colon-space fails to parse, and the description loads blank in the `/config`
  picker.
- **State `keep-coding-instructions` explicitly.** It defaults to `false`, and
  that default strips Claude Code's built-in software-engineering instructions —
  how to scope a change, when to comment, how to verify work. `Report` sets it
  `true`. A style that genuinely replaces those instructions may set it `false`;
  what is not allowed is arriving at either by omission.

## Limits

- **Subagents do not get it.** A subagent runs its own system prompt, so the
  style reaches the main conversation only. A fork is the exception — it inherits
  the parent's system prompt whole.
- **One at a time.** There is no layering. Anything a consumer needs alongside
  this belongs in `CLAUDE.md`, which is always read regardless of style.
- **Not measured.** Whether this style actually changes report quality, and
  whether it collides with `CLAUDE.md` §6 in practice, has not been measured. See
  `docs/agent-layer.md` §4b.

## Verification

| What | Where |
|---|---|
| Frontmatter parses, `description` quoted, `keep-coding-instructions` present | `scripts/verify-frontmatter.sh` |
| The style's token cost is counted, not silently zero | `scripts/context-budget.sh` |
| The scalar is written, and a consumer's own choice survives install and uninstall | `scripts/verify-install.sh` |

`claude plugin details` does **not** list output styles and its `Always-on`
figure does not include them, which is why `context-budget.sh` measures the file
directly rather than trusting that number.

## Related

- [`docs/agent-layer.md`](agent-layer.md) — §2 for the accident this answers, §3
  for where output styles sit in the ladder
- `plugins/harness-core/output-styles/report.md` — the style itself
- `plugins/harness-core/declarative/settings-fragment.json` — the scalar

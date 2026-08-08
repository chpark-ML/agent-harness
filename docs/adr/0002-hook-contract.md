# ADR-0002: Hooks are written in bash 3.2 and jq only, and the installer requires jq

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

Hooks run on every tool call. The more runtime dependencies they carry, the more easily the harness lands in the "installed but not running" state — and that state is silent. A guard that does not run looks exactly like nothing happening.

The floor is macOS's `/bin/bash` 3.2 (a 2007 release Apple does not update, for licence reasons). The reference harness's verifiers used `mapfile` and declared "requires bash 4+"; another harness's formatting hook was quietly running at half strength on macOS hosts.

Meanwhile one reference hook used `python3` to parse stdin, putting it in violation of its own repository's bash-and-jq convention.

## Decision

Hooks are written in **bash 3.2 and jq only**. No Python, Node or perl. No bash 4 syntax such as `mapfile`, associative arrays or `${x^^}`. Under `set -u`, an empty array expands as `"${arr[@]+"${arr[@]}"}"`.

A hook **disables itself with one stderr line and `exit 0`** when `jq` is absent. A missing guard must not become a stopped piece of work.

**The installer does the opposite: it requires jq, and stops without writing anything if it is missing.** *(After ADR-0008 that preflight lives in `harnessctl`. `install.sh` installs the plugins first and then stops at harnessctl, so "without writing anything" applies to the declarative half only.)* Since hooks require jq, an install without it delivers nothing but self-disabled guards. Better a failed install than that, done quietly.

`make syntax` parses every shipped script with `bash -n`, and CI runs it under macOS's `/bin/bash` as well — to catch bash 4 syntax on error paths no test reaches.

## Consequences

- Hook logic gets verbose. Array and string handling has to be written in the 3.2 vocabulary, and things like `large-file-veto`'s `git add` argument parsing go through a line of awk.
- An environment without jq cannot install at all. That is a heavy ask for someone who only wants the conventions and skills, but jq installs in one line even then.
- When a hook disables itself, the only sign is one line on stderr. A user can miss it — which is why the installer's preflight blocks it earlier.
- There will come a moment when a new hook wants a scripting language. At that point, open a PR marking this ADR superseded first.

## Alternatives considered

- **Allow Python hooks** — parsing gets easier, but the hook now depends on interpreter version and virtualenv state, and that failure is silent.
- **Fall back to python3 when jq is missing** (the reference installer's approach) — two copies of the same merge logic to maintain, and when they diverge what gets damaged is the user's `settings.json`. Given that hooks already require jq, the only scenario this fallback rescues is "a harness with no guards".
- **Require bash 4 and point at Homebrew bash** — forces an environment change on the user, and breaks quietly wherever that force does not reach (CI images, a colleague's laptop).

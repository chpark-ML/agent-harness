<h1 align="center">agent-harness</h1>

<p align="center">
  <strong>A general-purpose Claude Code harness for research and development</strong><br>
  Guards, conventions and a reversible installer — assembled from what already exists, and measured against running without it.
</p>

<p align="center">
  <a href="https://github.com/chpark-ML/agent-harness/actions/workflows/verify.yml"><img alt="verify" src="https://github.com/chpark-ML/agent-harness/actions/workflows/verify.yml/badge.svg"></a>
  <img alt="checks" src="https://img.shields.io/badge/checks-692-blue">
  <img alt="incidents stopped" src="https://img.shields.io/badge/incidents%20stopped-33%2F35-success">
  <img alt="always-on context" src="https://img.shields.io/badge/always--on%20context-8.3k%2F9k-informational">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-lightgrey">
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#what-you-get">What you get</a> ·
  <a href="#what-it-is-measured-to-do">Measurements</a> ·
  <a href="#how-it-is-built">How it is built</a> ·
  <a href="#contributing">Contributing</a> ·
  <a href="README.ko.md">한국어</a>
</p>

---

## The short version

Most agent harnesses are a pile of rules nobody checked. This one keeps a rule only while it can show the rule changes what the agent does — and **deletes the ones that measure zero.** Two are already gone: a commit-subject length limit and a draft loop rule, both of which scored identically with and without the harness.

> **Agent = Model + Harness.** The harness is everything around the model — tool dispatch, permissions, context, verification. In a production agent it is [most of the system](https://en.wikipedia.org/wiki/Agent_harness). This repository is the guards-and-conventions part of it for Claude Code, plus a way to install and remove that part cleanly.

---

## Quick start

One command. It installs everything.

```bash
curl -fsSL https://raw.githubusercontent.com/chpark-ML/agent-harness/main/install.sh | bash
```

That is **user scope**: the guard hooks, skills and commands apply in every repository you open on this machine, and nothing is written into any project.

**Path-scoped rules do not come with it, and cannot.** There is no documented `~/.claude/rules`, so installing them machine-wide would place inert files where they look active. Rules load from a project only. To put them — and `CLAUDE.md` — into a repository your team clones, add a second command:

Go to the repository first. This is the only line you edit:

```bash
cd your-repo
```

Then paste the rest unchanged:

```bash
curl -fsSL https://raw.githubusercontent.com/chpark-ML/agent-harness/main/install.sh | bash
harnessctl init --scope project --with dev,research
```

**`--with` is not optional here, and its absence is silent.** `harnessctl` takes the module list from `--with` or from the target's own manifest, and a repository being set up for the first time has neither — so plain `harnessctl init --scope project` installs the catch-all workflow rule and nothing else. Name the same role profiles you installed: the default above is `dev,research`, and `--profile dev,python` would be `--with dev` (`python` is a language profile and carries no rules).

The split follows what each asset is *for*. Guards and skills are yours: they belong machine-wide, or the one repository you forgot to install in becomes the hole. Rules and project settings are the team's: they belong in the commit, so they arrive with a clone.

Run `harnessctl init` on its own in any repository later — `install.sh` is not repeated.

The first command puts `harnessctl` in `~/.local/bin`. If that directory is not already on your `PATH`, the installer says so and names the file to add it to, but it cannot change the shell you are sitting in — apply that line and reopen the shell, or call the shim by its full path: `~/.local/bin/harnessctl init --scope project --with dev,research`.

An existing project loses nothing. A `CLAUDE.md` you already have is kept as it is, your own rules outside `.claude/rules/harness/` are untouched, and `settings.json` is parsed and re-serialised rather than replaced, so existing keys and permissions survive and duplicates are not created. If a file the harness does not own already sits at one of its managed paths, the install **stops before writing anything** and names it. Add `--dry-run` to the `harnessctl` command to see its plan first; `install.sh` has no such flag.

<details>
<summary><b>If piping a remote script into a shell makes you uneasy</b></summary>

Reasonable. Any of these work instead.

```bash
# 1) Read it first. It does three things:
#    register the marketplace, install the plugins, run harnessctl init.
curl -fsSL https://raw.githubusercontent.com/chpark-ML/agent-harness/main/install.sh -o install.sh
less install.sh && bash install.sh --profile dev,python

# 2) Pin to a revision so a moving main cannot change what you get
bash install.sh --profile dev --ref v0.1.0

# 3) Clone, as before
git clone https://github.com/chpark-ML/agent-harness && bash agent-harness/install.sh --profile dev
```

`--ref` takes a tag, a branch or a commit SHA. Release tags version the whole snapshot — the installer, the declarative payload, and the plugin versions at that revision — and are independent of the six plugins' own versions ([ADR-0013](docs/adr/0013-release-tags.md)).

The clone was never required: the installer reads nothing from the checkout. It looks for `harnessctl` in the plugin cache, then the marketplace clone, then the checkout — and the first two are what the script itself just created.

</details>

### Taking less than everything

**You do not have to choose a profile.** Everything is ~8,000 tokens of always-on
context against a ceiling of 9,000, so the default is all of it. `--profile`
exists for taking *less* — the whole content set costs about 2,100 tokens per
session more than development alone, which is worth declining only if you know
you want it back.

| You want | Flags | Difference from the default |
|---|---|---|
| **Everything** | *(none)* | 7 guards, three permission tiers, the six-principle `CLAUDE.md`, [Superpowers](https://github.com/obra/superpowers) 14 skills, our 5, and the rules for both roles |
| Development only | `--profile dev` | Drops the five-document note discipline and `results-deck`. Saves ~2,100 tok per session |
| Research only | `--profile research` | Drops `pr-review` and the Superpowers 14 |
| A language server too | `--profile dev,python --with-tools` | Adds the LSP. `--with-tools` runs `npm install -g`, which is why it is opt-in |
| Guards and nothing else | `--profile core` | The permission tiers, the guards, `CLAUDE.md`, `pr-create` |

**The one thing to know about `--scope`.** It defaults to `user`, which covers the whole machine — but the **rule files install at project scope only**, because `~/.claude/rules` is not a location Claude Code reads. So a new project needs one more run inside it:

```bash
bash install.sh --scope project
```

You do not have to remember that. From the next session in an uninstalled project, the brief says so on its first line, and the agent can run it for you:

```
- harness: project rules not installed (harnessctl init --scope project)
```

Restart Claude Code when the installer finishes. Plugins load at session start.

### Verify and undo

```bash
harnessctl doctor                    # what is installed, what is missing
harnessctl uninstall --scope user    # settings, rules, CLAUDE.md
```

**Removal has three parts, and `harnessctl` owns only the first.** It writes no plugins and no shims, so it removes neither. Both commands above now end by listing what is actually installed and the exact command for each, so there is nothing to remember:

```
  to remove the plugin half:
    claude plugin uninstall harness-core@agent-harness --prune
    claude plugin uninstall harness-dev@agent-harness --prune
    ...

  shell shims (written by install.sh):
    remove with:  rm ~/.local/bin/harnessctl ~/.local/bin/harness-log
```

Templates you may have edited — `CLAUDE.md`, `*-paths.txt`, `gh-account.txt` — are kept by default; add `--purge-templates` to remove those too.

**A verified property:** after uninstall, `settings.json` is **canonically identical** to what it was before (`jq -S`). The installer reverts only the receipt it wrote (`harness-manifest.json`) and touches nothing else. 132 assertions hold that line.

### Requirements

bash 3.2 or newer (stock macOS `/bin/bash` is the floor) · jq · git · a Claude Code that supports plugins. One more assumption: **a git repository.** Two guards call git directly and most of the conventions assume a forge.

---

## What you get

`core` is in every combination; the rest stack on top. **A blank cell means that profile does not add anything there.**

Profiles fall on three different axes — what you *do*, what you *produce*, and what you *write it in* — so they are not mutually exclusive.

| | `core`<br><sub>always</sub> | `+dev`<br><sub>role</sub> | `+research`<br><sub>role</sub> | `+slides`<br><sub>output</sub> | `+python`·`+typescript`<br><sub>language</sub> |
|---|---|---|---|---|---|
| **Guard hooks** | **7** — 5 blocking, 2 informational | | | | |
| **Permission tiers** | allow 47 / ask 3 / deny 8 | | | | |
| **`CLAUDE.md`** | six behavioural principles | | | | |
| **Our skills** | `pr-create` | `pr-review` | `research-notes`<br>`repro-checklist` | `results-deck` | |
| **External skills** | | [Superpowers](https://github.com/obra/superpowers) 14 | | | |
| **Rule files** | `workflow.md` | `review.md` | `notes.md` | | |
| **Executables** | `harnessctl` (install/verify/undo)<br>`harness-log` ([session history → HTML](docs/harness-log.md)) | | | | |
| **External tools** | | | | [`slides-grab`](https://www.npmjs.com/package/slides-grab) (npm) | language server (LSP) |
| **Always-on context** | ~3,761 tok | **+2,060** | **+1,759** | **+446** | **0** |

**Hooks and LSP cost nothing in context.** The figures above are project scope and include `CLAUDE.md` (~1,736) and `rules/` — **most of the cost is rule prose, not skills.** User scope has no `rules/`, so it totals ~3,919; project scope with everything is **~7,085 tok per session** — measured in CI (ubuntu, Claude Code 2.1.227). The estimator varies by environment: the same checkout measures ~7,934 on a macOS workstation under the identical version, because the Korean trigger clauses in our skill descriptions are counted differently. **The 9,000 ceiling is the gate**, and CI enforces it on a complete install.

`make context-budget` counts this from source and `make verify` fails past the ceiling of 9,000. **Do not edit those numbers by hand** — an earlier table counted skills only and was wrong by 3.6×.

### The guards

| Hook | What it catches | Blocks |
|---|---|---|
| `secret-scrubber` | literal secrets on a command line (API keys, tokens, AWS keys) | ✅ |
| `large-file-veto` | `git add` over 10 MiB | ✅ |
| `protected-paths` | declared absolute path prefixes (off until configured) | ✅ |
| `ai-attribution-guard` | AI authorship marks in commits and PRs | ✅ |
| `gh-account-guard` | a push or PR as the wrong GitHub account (off until configured) | ✅ |
| `session-brief` | ten lines of repo state at session start | ❌ informational |
| `check-uncommitted` | work piling up on the default branch | ❌ informational |

**Only blocking hooks exit non-zero.** An informational hook that halts a turn is a bug. A block message says both *what was caught* and *how to resolve it*, because a consumer cannot open the hook file — it lives in the plugin cache, so the message is the only interface.

---

## What it is measured to do

Every layer is compared against stock Claude Code. **This table is the point of the repository** — [methods and caveats](docs/agent-layer.md).

| Layer | Question | Result |
|---|---|---|
| **Guards** | does it stop incidents? | **33 / 35** stopped — at the cost of **2 / 30** false positives on ordinary work |
| **Conventions** | does written prose change behaviour? | branch naming 0/12 → **10 / 12** (*p* ≈ 0.00007) |
| **Skill routing** | does work reach the skill we said it would? | **59 / 60** |
| **LSP** | does it reduce tokens or errors? | **inconclusive** — this sample can only resolve effects above 61% |
| **Installer** | does uninstall restore the original? | **canonically identical**, 132 assertions |

**Read the first row as two numbers.** A guard that blocks everything scores 100% and gets switched off the same day, after which it stops zero. 8% is the price of the 93%.

### Things it is measured *not* to do

- **A commit-subject length limit earned nothing** — 6/6 with the harness, 6/6 without. The model writes short subjects anyway. **Removed from the rules.**
- **A draft loop rule earned nothing** — given a task whose first attempt necessarily fails, both arms ran the verification command 3/3 unprompted. Running the check is what the model already does. **Not merged.**
- **The LSP result is "not visible with this ruler", not "no effect"** — the off arm's coefficient of variation is 26%, so detecting the observed 6.3% would need 137 runs per arm.

### The measurement is where most of the learning was

Nine times an instrument produced a confident zero that turned out to be its own fault — a read-only task that could not trigger the mechanism, a timeout indistinguishable from a non-trigger, a rule that was never installed into the fixture, a verification command the permission tier refused, a grader that marked a correct answer wrong. All nine looked identical on screen.

**The rule that came out of it: when you get a negative result, confirm the mechanism could have fired before concluding anything.** All nine are tabulated in [`docs/agent-layer.md` §4b](docs/agent-layer.md).

---

## How it is built

### Two halves, because the platform draws the line there

| | Plugin | `harnessctl` |
|---|---|---|
| **What** | guard hooks, skills, commands, verifiers | permission tiers, `CLAUDE.md`, `.claude/rules` |
| **Why here** | Claude Code loads, updates and scopes it | a plugin's `settings.json` supports only `agent` and `subagentStatusLine`; a plugin-root `CLAUDE.md` is not read as context; `rules` is not a plugin component |
| **Installed by** | `claude plugin install` | `harnessctl init` |

See [ADR-0008](docs/adr/0008-plugin-declarative-split.md). `harnessctl` ships in the plugin's `bin/`, which reaches the Bash tool's PATH but not your terminal, so the installer also writes a shim to `~/.local/bin` that resolves the newest version at run time.

### What `harnessctl` touches — all of it

| | What | Rule |
|---|---|---|
| 1 | `.claude/rules/harness/**` | **managed** — overwritten on reinstall. Fix these upstream. Not installed at user scope |
| 2 | `CLAUDE.md`, `*-paths.txt`, `gh-account.txt` | **templates** — copied only when absent, yours afterwards |
| 3 | `settings.json` | parsed and **re-serialised**, never replaced. Only missing permission strings and `includeCoAuthoredBy: false` |
| 4 | `settings.json.bak-<ts>` | a snapshot, only when settings actually change |
| 5 | `.gitignore` | two lines, project scope only |
| 6 | `harness-manifest.json` | the receipt for all of the above. Uninstall reverts only this |

**Never touched:** the `hooks` block in `settings.json` (the plugin registers hooks; a verifier asserts `.hooks` is byte-identical before and after install) · anything outside the chosen scope · `settings.local.json` · anything under `.claude/` not in the manifest · git itself.

---

## Verification

```bash
make verify-all              # everything, plus a check that the published total matches
make verify BASH=/bin/bash   # under macOS bash 3.2, the floor — required before merge
make context-budget          # always-on token cost per scope and profile
```

| Target | Cases |
|---|---|
| 7 hook verifiers | **248** |
| session-log renderer | **44** |
| installer round trip | **132** assertions |
| context-budget gate | **14** |
| inventory figures | **39** + selftest **7** |
| slide claim checker | **36** |
| document references | **61** files + **19** own cases |
| documented commands exist | **45** + selftest **12** |
| frontmatter | **11** |
| plugin and marketplace manifests | **7** |
| benchmark health | **14** |
| context-budget ceiling | **1** |
| **Total** | **692** |

Cases come in three kinds — **no-op** (input the hook must ignore), **block**, and **boundary** (something that resembles what is blocked and must pass). The third is what earns its keep: a verifier with only block cases proves it stops what it should and says nothing about what it lets through, and the second is how guards actually die.

`make bench*` is different. Those burn model sessions, cost real money, and are run by hand — never in CI.

---

## What is deliberately absent

- **No general-purpose work skills.** Brainstorming, TDD, systematic debugging, worktrees — [Superpowers](https://github.com/obra/superpowers) covers those and this repository takes it as a dependency instead of rebuilding it ([ADR-0009](docs/adr/0009-external-dependencies.md)).
- **No domain verticals.** [`harness-100`](https://github.com/revfactory/harness-100) ships a hundred of them under Apache-2.0 and coexists cleanly — measured: our skills held all six of their own prompts, 3/3 each. Absorbing them would cost about 35k tokens per session, so they stay a dependency ([ADR-0011](docs/adr/0011-ecosystem-survey.md)).
- **No consumer sub-agents, no MCP servers.** Both are levers we have never needed twice.

**New assets are added for problems that occurred at least twice.** The count is kept in a ledger rather than in memory, because "twice" cannot be counted across sessions any other way.

---

## Contributing

[`CONTRIBUTING.md`](CONTRIBUTING.md) has the full workflow. Four points carry most of it:

- **A new guard is a bundle** — script, verifier, doc, `hooks.json` registration, SOT update. All four names must match.
- **A new skill is a bundle too** — a trigger eval (`evals/trigger/<name>.json`, 6 positive and 6 negative) or it is unfinished. Unmeasured negative routing is a claim, not a behaviour.
- **A guard merged without verification is decoration.**
- **Always-on context is a trade, not an addition.** Past the ceiling, say what comes out.

[`docs/agent-layer.md`](docs/agent-layer.md) is the single source of truth for scope, inventory and backlog. [`docs/engineering-axes.md`](docs/engineering-axes.md) separates the layers this work sits in — context, loop, graph — and is honest about which of them we have measured.

## Credits

Safe `settings.json` merging, collision-proof backups, symmetric removal and the "what does it touch" audit come from [`claude-statusline`](https://github.com/chpark-ML/claude-statusline). The two-tier install, per-hook verification mandate, ADR discipline, principle-based `CLAUDE.md`, harness-gap loop, PR conventions and the five-document research note pattern come from two internal harnesses that are not public, with the project-specific parts removed.

Two external works are used directly, with their licences:

- **`CLAUDE.md` §1–§4** — adapted almost verbatim from the MIT-licensed [`karpathy-guidelines`](https://github.com/multica-ai/andrej-karpathy-skills), itself derived from Andrej Karpathy's observations on LLM coding pitfalls. §5 and §6 are ours.
- **The ledger mechanism in §5** — from the CC BY 4.0 [`task-observer`](https://github.com/rebelytics/one-skill-to-rule-them-all), whose argument is that writing the observation down *is* the enforcement.

Dependencies are [`superpowers`](https://github.com/obra/superpowers) and the official LSP plugins, under their own licences.

## License

MIT. See [`LICENSE`](LICENSE).

# Agent Layer — what the harness is, where it stands, how it is verified

The **single source of truth** for this repository. What the harness covers, what gets built next, and how its behaviour is verified is written here and nowhere else ([ADR-0004](adr/0004-single-source-of-truth.md)).

## 1. Definition

| Artifact | Location | Role |
|---|---|---|
| Plugins | `plugins/harness-{core,dev,research,python,typescript}/` | Hooks, skills, commands, verifiers, and `bin/` executables (`harnessctl`, [`harness-log`](harness-log.md)). Claude Code loads them directly and puts `bin/` on the Bash tool's PATH |
| Declarative installer | `plugins/harness-core/bin/harnessctl` | Writes what a plugin cannot carry — permissions, `CLAUDE.md`, `rules` — to the target, and removes it symmetrically |
| Bootstrap | `install.sh` | The whole install in one command: register the marketplace → plugins → `harnessctl init` → language servers → `doctor`. It holds no harness logic; it calls the two halves in order |
| Verification runners | `plugins/harness-core/scripts/verify-*.sh`, `scripts/verify-{install,frontmatter}.sh` | Hook behaviour, the harnessctl round trip, frontmatter |

**Non-goal** — application code, build systems, per-language or per-framework scaffolding, tracking and deployment backends. Those belong to the consumer project.

**A second non-goal, and the more important one** — we do not build *general-purpose working skills*. Brainstorming, TDD, systematic debugging, planning, code-review procedure and worktrees are already done well by Superpowers. This repository's own share is three things — **preventing accidents (guards), fixing conventions, and safe install and removal** — and the ability to do work is composed through a profile's `dependencies`.

That distinction explains why the two profiles differ in thickness. The 14 Superpowers skills cover development workflow broadly but include **nothing research-specific** — so `harness-dev` being thin on our side (1 convention + 1 skill) while `harness-research` is thick (1 convention + 2 skills + 5 templates) is not an imbalance, it is upstream coverage reflected accurately. When the urge to thicken `dev` arrives, check whether Superpowers already has it.

**The profiles sit on one line but they lie on three axes.** `--profile` takes a comma list, which invites picking different kinds of thing with the same syntax. In fact they divide like this.

| Axis | Profiles | What it adds |
|---|---|---|
| **Role** — what kind of work you do | `dev`, `research` | Conventions (rules) plus skills. Most of the always-on cost |
| **Output** — what you produce | `slides` | One skill plus a checker. No rules |
| **Language** — what stack you are on | `python`, `typescript` | One manifest. Zero files, zero cost, and the LSP only attaches when those files exist |

Different axes, so they are not exclusive — `dev,python` and `research,slides` are both ordinary combinations. When adding a profile, **decide its axis first**: the role axis is expensive (rules cost more than skills, §4) and the language axis is effectively free.

**One prerequisite** — a git repository. `large-file-veto` and `check-uncommitted` call git directly, and the part of `rules/harness/workflow.md` that mentions PRs 15 times across its 98 lines assumes a forge. In a repository with no PR flow half of that is meaningless, while R3 (harness gap) and R5 (plan verification) still hold. Work that does not use git is not what this harness is for.

**One scope test**: would this still make sense installed as-is on a project in another domain, on another stack? If not, it does not belong here.

**One delivery test**: can a plugin carry it? Hooks, skills, commands, agents and executables can; permissions, `CLAUDE.md` and `rules` cannot — a boundary the platform drew, not one we chose ([ADR-0008](adr/0008-plugin-declarative-split.md)).

**One level test**: is this asset's audience *me* or *the team*? Guards, skills and principles are me — they have to sit machine-wide or a repository you forgot to install in becomes the hole. Path-scoped rules and project-specific settings are the team — they have to be committed to arrive with a clone. Scope itself is now handled by the plugin system and `harnessctl --scope` ([ADR-0007](adr/0007-install-levels.md)).

## 2. Why — the things every project runs into again

Problems no project should have to solve from scratch. Each row is owned by **one category** in §3.

| Accident / friction | Frequency | Owner |
|---|---|---|
| A secret goes onto the command line as a literal and lands in history, logs and the process list | Common | `secret-scrubber` |
| A large artifact is swept up by `git add -A` and enters history permanently | Common | `large-file-veto` |
| A shared mount or another team's directory is touched by absolute path, by mistake | Site-dependent | `protected-paths` |
| AI attribution lands in a commit or PR | It is the default | `ai-attribution-guard` + `includeCoAuthoredBy: false` |
| A push or PR goes out as the wrong GitHub account, because two are authenticated and `gh auth switch` moved the active one | Site-dependent | `gh-account-guard` |
| Irreversible commands (`rm -rf`, force push, `reset --hard`) | Rare but fatal | Permissions `deny` |
| PR and commit conventions drift per project | Every time | `rules/harness/workflow.md` |
| Work piles up on the default branch and the review unit tangles | Common | `check-uncommitted` |
| Repo state is re-discovered with tool calls at the start of every session | Every session | `session-brief` |
| Review criteria get explained out loud again each time | Every time | The `dev` module |
| Experiment results cannot be reproduced later | It is the default | The `research` module |
| Records scatter and a new session cannot pick them up | Common | The `research` module |

When adding an item to the §7 backlog, **say which row of this table it answers**. If there is no such row, add the row first — and then ask yourself whether it has actually happened twice.

## 3. Categories and the adoption ladder

Eight categories. **The adoption order is the axis of progress** — guardrails → guides → automation → delegation → external connections. Go in reverse and automation amplifies the accidents.

| Phase | Category | Location | Now |
|---|---|---|---|
| **0** | Conventions | `CLAUDE.md`, `.claude/rules/harness/**` | ✅ core 1 + dev 1 + research 1 |
| **0** | Permissions | `settings.json` (merged from a fragment) | ✅ allow 47 / ask 3 / deny 8 ([ADR-0012](adr/0012-test-runners-in-allow.md)) |
| **1** | Hooks | `plugins/harness-core/hooks/` — registered by `hooks.json` | ✅ 7 (5 blocking, 2 informational) |
| **1** | Skills | `plugins/*/skills/<name>/SKILL.md` | ✅ core 1 + dev 1 + research 2 + slides 1, with Superpowers 14 on top |
| **2** | Sub-agents | `.claude/agents/*.md` | ⏳ 1 for the harness itself (`harness-reviewer`) — none for consumers |
| **3** | Slash commands | `.claude/commands/*.md` | ✅ 1 (`/verify`) |
| **3** | Executables | `plugins/*/bin/` | ✅ 2 — `harnessctl` (install, check, remove) and [`harness-log`](harness-log.md) (session history → HTML) |
| **4** | MCP servers | `.mcp.json` | ⏳ none |
| **—** | External plugins | A profile's `dependencies` | ✅ Superpowers, 2 LSPs ([ADR-0009](adr/0009-external-dependencies.md)) |
| **—** | External instruments | Installed by the developer (not shipped) | ✅ `skill-creator` — skill ablation and trigger measurement ([ADR-0011](adr/0011-ecosystem-survey.md)) |
| **—** | External npm tools | `harnessctl doctor` checks PATH | ✅ `slides-grab` (slides, [ADR-0010](adr/0010-slides-profile.md)) |

> Phase 0 is guardrails, Phase 1 is the guides and automation on top of them, Phase 2 is the division of labour on top of that. **Each phase is the safety net for the next.**

Having no consumer-facing sub-agent yet is a judgement, not an omission. We could invent one; there has not yet been a delegation that was actually needed twice.

## 3b. Ecosystem verdicts — what came in, and what got measured

The detail behind §3's last three rows (external plugins, external instruments, external npm tools). **The reasoning and the measurements live in one table** — scattered, the same candidate gets reviewed twice. The narrative is [ADR-0011](adr/0011-ecosystem-survey.md), the consumer-facing summary is in the README, and both point here.

**The measurement column is the point of this table.** Most of it is empty, and that means not yet measured — not no effect.

| Subject | What | Verdict | Basis | Measured | Always-on cost |
|---|---|---|---|---|---|
| [`superpowers`](https://github.com/obra/superpowers) | 14 development-workflow skills | **Depend** | Covers development workflow broadly. No reason for us to build it | Our routing **59/60**. One delegation was not accepted, though — three merge requests all went to `Bash` | ~688 |
| `pyright-lsp`, `typescript-lsp` | Language server connection | **Depend** | A dependency of the language profiles | **Inconclusive** — tokens −6.3%, and this design's MDE is 61% | **0** |
| [`harness-100`](https://github.com/revfactory/harness-100) | 100 domain verticals (Apache-2.0) | **Depend, do not absorb** | An individual harness cannot pass ADR-0001's admission test by construction. Absorbing six domains ≈ 35k tok | Coexistence: **zero conflicts** — our skills held 6/6 negatives unanimously across three runs each | ~560 each, **only what you install** |
| `skill-creator` (official) | An evaluation harness — 3 subagents + 7 scripts | **Developer only, not shipped** | The name says authoring helper; the body is an instrument | — | 112 always-on / **10.9k per call** |
| `karpathy-guidelines` (MIT) | Four principles on LLM coding pitfalls | **Do not install, absorb the text** | Our `CLAUDE.md` §1–4 already is this | 20 of 23 normative sentences matched **verbatim** | 0 (absorbed) |
| `task-observer` (CC BY 4.0) | Session observation → an improvement ledger | **Do not install, absorb the mechanism** | Half of its 446 lines overlap our §5 | — | 0 (absorbed) |
| [`slides-grab`](https://www.npmjs.com/package/slides-grab) | Slide rendering | **External tool** | Rendering is a solved problem. `doctor` checks PATH | — | 0 |
| `graphify` (an ehr-research project skill), `CodeGraph`, `GitNexus` | Codebase knowledge graphs — precompute the structure and serve it over MCP | **Unjudged** | We have no corresponding asset. An LSP is the symbol layer and answers a different question ([axes](engineering-axes.md)) | **Not measured.** Others report tokens −47% and tool calls −58% (`CodeGraph`, 7 repositories) | Index maintenance |
| [`ponytail`](https://github.com/dietrichgebert/ponytail) (MIT) | A "lazy senior dev" ruleset — always-on `AGENTS.md` + 6 skills + hooks | **Held, but its eval design absorbed** | It argues what our `CLAUDE.md` §2 argues. The difference is that **they measured and we did not** | **LOC −54%, tokens −22%, cost −20%, time −27%** (same agent ±skill, n=4, Haiku 4.5, 12 tickets on the fastapi template, scored on the git diff) | Always-on `AGENTS.md` + 6 skills |
| [`codebase-memory-mcp`](https://github.com/DeusData/codebase-memory-mcp) (MIT) | Codebase → knowledge-graph MCP. A static binary plus SQLite, with a file watcher | **Top candidate** | The concrete candidate for the graph row above. Being MCP, it adds no plugin surface | 31 repositories, 12 question categories, Opus 4.6: **quality 0.83 vs 0.92**, **10×** fewer tokens, 2.1× fewer tool calls, latency `<<1ms` vs 10–30s. Weakest on macro-heavy C (0.58 vs 1.00) and exhaustive grep | The index (`~/.cache`) |
| [`headroom`](https://extraheadroom.com/) | Input-side compression — logs, JSON, build output | **Rejected** | Not a plugin but a **local proxy**. Every prompt passes through it, so the same verdict as `omniroute`: a security decision, not a harness one, and the app is paid (\$5–60/month) | Their claim: ~50% on noisy input, 15–25% in real sessions | — |
| `caveman` | 65% fewer output tokens | **Rejected** | Head-on conflict with [ADR-0002](adr/0002-hook-contract.md)'s hook contract (*a block message carries what was caught and how to get past it*) | — | — |
| `ui-ux-pro-max` | UI/UX reference | **Held** | Domain-profile material. Zero occurrences in this repository → a `harness-frontend` candidate | — | — |
| `claude-mem` | Session capture via 5 lifecycle hooks → SQLite | **Held** | Stores **all tool I/O**. Not possible in a repository running `secret-scrubber` without checking first | — | — |
| `omniroute` | A local gateway for 290+ providers | **Rejected** | Not a plugin but a proxy. A security decision, not a harness one | — | — |
| `handoff` | Context hand-off between sessions | **Held** | The five-document set covers the research side. Zero occurrences on the development side | — | — |

**Verdicts come from the body, not the name.** All four verdicts made from names alone were wrong (ADR-0011). `skill-creator` was an instrument, not an authoring helper; `harness-100` was a collection of project templates, not of skills; `slide-deck` (ehr-research) looked orphaned but sat under another pipeline's front door. **The fourth was not even a name** — `headroom` and `ponytail` were written down as *"an inactive install under another project's scope"*, which is not a verdict but a description of this machine. Reading the bodies, one had measured our own §2 more rigorously than we had, and the other was a proxy.

**What those three rows say together.** Half our always-on context is norms telling the model to *write less* and *change narrowly* (`CLAUDE.md` §2 and §3, `workflow.md`), and we have never measured whether those norms change behaviour. `ponytail` measured the same claim with **the same agent ±skill, a real repository, and grading on the git diff** — the design `bench-convention` was reaching for, so the next measurement is one to copy rather than invent. Conversely `codebase-memory-mcp`'s 0.83 vs 0.92 means **a 10× token saving costs 10% of the quality**, a measured instance of what §4b already suspected: *accuracy can peak at intermediate cost*. Both push the question from "how cheap" to **"what does the cheapness cost"**.

## 4. The verification mandate

**A guard merged without verification is not a guard, it is decoration** ([ADR-0003](adr/0003-verification-mandate.md)).

| Category | Verification |
|---|---|
| Hooks | `plugins/harness-core/scripts/verify-<name>.sh` — one per hook, 8 cases or more, carrying all three kinds: no-op, block, boundary |
| Installer | `scripts/verify-install.sh` — harnessctl's init → reinstall → module swap → uninstall round trip, **and `install.sh` itself** (is there an executable line in the header; do `--help` and the argument rejections run without the Claude CLI). User scope is checked against a scratch directory via `CLAUDE_CONFIG_DIR`, so the real `~/.claude` is never touched |
| Frontmatter | `scripts/verify-frontmatter.sh` — YAML parsing of every skill, agent, rule and command, plus a skill description's negative routing and the second-language triggers `TRIGGER_LANGS` declares (this repository declares `한국어\|Korean`; the English triggers cannot be checked by machine and stay a human review item). Needs only python3 |
| Output tools | `plugins/harness-core/scripts/verify-harness-log.sh` — 44 cases. The same three kinds as a hook, but centred on **must-not-appear**: if tool output, a subagent transcript, a skill injection or a compaction summary leaked onto the page, then in a repository running `secret-scrubber` whatever a command printed would survive in a file ([harness-log](harness-log.md)) |
| Document references | `scripts/verify-doc-refs.sh` — does the file a link points at exist, does `#anchor` resolve to a heading, and does the first segment of a path an instruction file calls exist. Runs its own 19 cases first (false positives being this checker's only failure mode) |
| Check total | `scripts/verify-check-total.sh` — do the three published totals (the README badge, the README table, §4 of this document) agree with each other **and with what the run actually produced**. `make verify-all` runs verify and then reads its output |
| Context budget | `scripts/context-budget.sh` — sums the **entire always-on footprint** (declarative plus plugins) per scope × profile and fails past `CONTEXT_CEILING`. The file list is a glob, so a new rule cannot become quietly free |
| Manifests | `claude plugin validate --strict` — its own CI job. Everything else runs without the CLI |
| Syntax | `make syntax` — parses every shipped script with `bash -n` |
| Conventions and skills | Human review plus [`harness-reviewer`](../.claude/agents/harness-reviewer.md)'s structural audit |

**Now**: 7 hook verifiers / 248 cases, session-log renderer 44, claim checker 36, harnessctl round trip + install.sh 112 assertions, context-budget gate 14, inventory figures 23, frontmatter 11, plugin manifests 7, benchmark health 12, document references 61 files + 19 own cases, context-budget ceiling 1 — a total of 588. That number is itself checked by `make verify-all` (`verify-check-total.sh`) — the total has to wrap `verify` and read its output, so it does not count itself. `make verify` runs everything, and CI executes it as three jobs: ubuntu (bash 5), macOS (`/bin/bash` 3.2), and manifests.

**The document-reference checker earned its place on its first run.** The bodies of `pr-review` and `research-notes` gave the checklist's location as `rules/harness/…` — while `pr-create` writes the same location as `.claude/rules/harness/…`. A path that does not resolve from the project root, inside a skill body where nobody was looking. The second ledger occurrence that caused this checker to exist was exactly that kind.

**And it produced three false positives first.** The frozen corpus (`evals/prose-corpus.md`) is a copy of past documents, so its links are relative to the original location, and the relative links in the `declarative/` payload are correct relative to their *post-install* location. All three were removed by fixing the checker — going the other way would have made correct things wrong. The last one especially: the ledger was *quoting a broken link as evidence*, and because inline code was not stripped, the quotation was counted as a real link. **The discipline of adding the opposite-direction case when widening a guard applies here too.**

**Context cost is counted by `make context-budget`.** Below is the 2026-08-08 output, and **do not edit the table by hand** — re-run the script.

| What | Always loaded | When |
|---|---|---|
| `CLAUDE.md` | **~1,736 tok** | both user and project |
| `rules/core/workflow.md` | **~1,696** | project only |
| `rules/dev/review.md` | **~1,132** | project only, `--with dev` |
| `rules/research/notes.md` | **~1,279** | project only, `--with research` |
| `harness-core` | ~329 | always |
| `harness-dev` + `superpowers` | ~240 + ~688 | `dev` |
| `harness-research` | ~480 | `research` |
| `harness-slides` | ~446 | `slides` |
| **worst case** (project, every profile) | **~7,085 tok / session** (CI; ~7,934 on macOS — the estimator varies) | ceiling 9,000, enforced in CI |
| Every profile at user scope | ~3,919 | no rules there |
| `skill-creator` (developer, not shipped) | ~112 | ~10.9k when called |

**This table has been wrong twice, and both times for the same reason — it was maintained by hand.**

- **The declarative half was missing entirely.** The first version counted skills only and put it at `~2.2k`. The `CLAUDE.md` and `rules/` that `harnessctl` installs load every session and appeared in no table. The real figure is **3.6× higher**, and `workflow.md` alone approaches the cost of all our skills combined. **We were judging "we can fit a bit more" on top of a fake baseline** — which is how bringing in 62 external harnesses (~560 tok each) briefly sounded survivable.
- **The plugin numbers were stale too.** The table said core 390 / dev 351 / slides 300; measurement says 329 / 240 / 446.

So instead of pinning numbers into a document, they moved into **a script that reads the source**, and `make verify` fails past the ceiling. The file list is a glob — a hardcoded list is the path by which a new rule file becomes quietly free.

**Hooks and LSPs are still zero** (`plugin details` classifies them as "harness-only — no model context cost"). What changed is that the conclusion *only skills cost anything* was wrong — **rules cost more than skills.** Our per-skill unit cost is high (Superpowers: 688 across 14, so ~49 each, against our ~240) because ours carry English and Korean triggers plus negative routing together, and whether that convention earns its cost is measured in §4b. We observed external skills attaching to Korean prompts **on an English description alone**, so this stays an open question.

**Adding is not addition, it is a trade.** There is ~1k of headroom under the ceiling, and it is there for the next one thing, not to be filled. To go past it, either say what comes out in the same change, or raise `CONTEXT_CEILING` in the Makefile with a reason.

**We also learned there is a second axis.** `skill-creator` is 112 always-on and 10.9k when called — a short description over a huge body. We have built the opposite way. Which is right is decided by call frequency: a frequently triggered skill needs a cheap body, and a rarely used tool needs a cheap description. Design on always-on cost alone and this axis is invisible.

**Repo-only verifiers owe no cases by default; how they fail decides.** Hooks are required to carry 8 cases or more, but there was no rule for `scripts/verify-*.sh`, so three of them were judged on the spot — `verify-frontmatter` (0 cases), `verify-doc-refs` (19), `context-budget` (0). Lined up, the criterion was one thing: **if it fails by false positive, add cases** (a check that cries wolf gets switched off, and a switched-off check is zero); **if it fails by omission, prevent it in the design** — glob rather than hardcode, so a new file does not become quietly free. When true or false is self-evident, neither is needed. The rule is written into `CLAUDE.md` §4.

**And a line that runs in only one of the environments is an unverified line.** `verify-check-total` was written on a machine with the Claude CLI, and the branch that runs only without it executed for the first time in CI and broke in two ways — `grep -c`'s exit 1, and treating an unmeasurable total as a failure. The same disease as the fixture item below, except this time it was the *environment* that was singular.

Boundary cases earn the most of the three kinds. A verifier with only block cases proves *it stops what it should* and says nothing about *it lets through what it should* — and the second is what actually kills guards.

**A code path with no fixture is an unverified code path.** The first verifiers all used a bare `git init` repository, so `check-uncommitted`'s `origin/HEAD` lookup and `session-brief`'s upstream block — paths that run *always* in a real cloned repository — never executed once. Coverage comes from the variety of fixtures, not the number of cases.

**A gap left on purpose gets pinned by a case that asserts it passes.** `protected-paths`'s path traversal and `ai-attribution-guard`'s "a person named Claude" false positive are the examples. Assert the fact that something is not caught, or is caught wrongly, and the behaviour cannot change quietly, and the limits section of the document cannot drift from the code.

**When widening a guard, add the opposite-direction case with it.** The order it actually happened: an audit flagged "only the `sk-` pattern has a narrow character class, looks like a typo", it was widened, and every long kebab-case branch name starting with `sk-` was then mistaken for a key and blocked. The class differed not by mistake but because *the formats differ* (legacy is base62; only the scoped variants include `_-`). With block cases only in the widened direction, the regression was invisible. **A change that widens a guard has to arrive with "things that must still pass" cases.**

**Look for failures that come out empty.** Three skills carried `한국어 트리거: '...'` in an unquoted YAML scalar — a scalar cannot hold a colon-space, so frontmatter parsing failed wholesale and those skills **loaded with an empty description**. No triggers, no negative routing, and nothing looking broken. `claude plugin validate` caught it, and `scripts/verify-frontmatter.sh` now does the same check with nothing but python3. The lesson is not "be careful with YAML" but that **some failures arrive as an empty value rather than an error**.

**When changing a configuration syntax, check whether it fails open first.** Switching `HARNESS_PROTECTED_PATHS` from space-separated to colon-separated made the old syntax `'/a /b'` read as *one* prefix, quietly creating a state that protected nothing. A guard stopping because of configuration syntax is not an acceptable direction to fail in. It now prints one stderr warning for a value with spaces and no colons.

## 4b. What to expect — what is measured and what is not

"What changes if I use the harness" cannot be answered by counting verifier passes. Verifiers measure *whether it runs as we intended*; this question asks *what differs from raw*. Each layer was measured separately.

| Layer | The question | Result | Confidence |
|---|---|---|---|
| **Guards** (hooks) | Do they stop incidents? | raw 0/29 → harness **27/29**, false positives on ordinary work **2/24** | Deterministic. A count, so no error bars |
| **Conventions** (CLAUDE.md, rules) | Does written prose change behaviour? | branch naming raw 0/12 → harness **10/12** | **Significant** (*p* ≈ 0.00007) |
| **Skill routing** | Does work reach the skill we said it would? | **59/60** | Descriptive. The 6/6 negatives confirmed across three runs each |
| **Deck number traceability** | Does the filter have holes? | 41 flagged of 143 tokens in the frozen corpus, **0 new unclassified shapes** | Deterministic |
| **LSP** | Does it improve tokens or accuracy? | accuracy 3/3 against 3/3, tokens −6.3% | **Inconclusive** — this design can only resolve effects above 61% |
| **Installer** | Does uninstall restore the original? | 112 assertions | An invariant, not an A/B subject |

**Every agent-session measurement came from `model=opus` and `effort=high`** (change them with `BENCH_MODEL` and `BENCH_EFFORT`). The first version did not pass these through and inherited the caller's `settings.json`, and which configuration produced a number was recorded nowhere — no comparison with another machine's figures was possible, and a reader had no way to know. The benches now print it at the start.

**That effort can move the result is left open.** More reasoning may mean more convention-following without the harness, which raises the raw arm and shrinks the effect below what is reported here. It has not been measured at `effort=xhigh`.

Below is the basis for each row. **If you take one line: guards and conventions earn their place, the LSP is not yet known, and some of the conventions earn nothing at all.**

### Guards (`make bench`)

`evals/incidents.sh` is a 53-case corpus written **independently of the verifiers** (drawn from the §2 accident table and from things that actually happen, without looking at the regexes). By category: attribution 5/5, protected 6/6, secret 10/11, bigfile 6/7. **The 2 misses and the 2 false positives are exactly the four `docs/hooks/*.md` already records as limits** — an independent corpus rediscovering the documentation, which is also evidence that the limits are described accurately.

The raw arm being 0/0 is self-evident (no hooks, so nothing blocked and nothing blocking). The meaning is not in that contrast but in **the 8% price tag** — a guard that blocks 100% is switched off within a day, and its block rate is zero from then on.

### Conventions (`make bench-convention`)

Guards were measured, skill routing was measured, and **whether a written convention changes model behaviour went unmeasured for a long time.** The branch-name convention `{feat,fix,chore}-<slug>` was chosen because it is decided by a regex (no judgement in the grading), it is **not in Claude Code's default prompt** (the default only goes as far as "if you are on the default branch, branch first"), and no hook enforces it — so it measures the guide layer rather than the guard layer.

| Convention | raw | harness | Verdict |
|---|---|---|---|
| Branch naming | **0 / 12** | **10 / 12** | two-sided *p* ≈ 0.00007 |
| Commit subject ≤ 70 chars | 6 / 6 | 6 / 6 | **No discriminating power** |
| Commit body present | 5 / 6 | 6 / 6 | Not significant |
| Verification loop — was the check command run | **3 / 3** | **3 / 3** | **No discriminating power** |

**The raw arm's failure shape is exactly what the rule anticipated.** Our rule forbids `/` in a slug and says why (it is used verbatim as a worktree and directory name), and every branch the raw arm cut was precisely `feat/retry-backoff`.

**The verification loop came back zero as well (2026-08-08).** A rule extending `CLAUDE.md` §4 into a loop contract (draft R6) was written and measured on a task whose first attempt necessarily fails — a naive exponential backoff falls over on the clamp and on a negative-value ValueError. **Both arms ran `make check` themselves 3/3, and both were correct 3/3.** Running the verification is what the model does anyway, not something the rule buys. So **R6 was not merged** — there is no case for adding 525 tok. Note that this bench measured *one* of R6's three claims (the stopping conditions and the session and experiment scales were not measured). Until a task design exists for the other two, it does not go in as a rule.

**But the other two earn nothing.** The 70-character subject limit is 6/6 on both arms — the model writes short subjects anyway. Written as a rule, it looks like a rule being followed, but **the difference that rule made is zero.** This is exactly the **non-discriminating assertion** `skill-creator`'s analyzer looks for. **It was removed from the rules on 2026-08-07** — measuring and getting zero is a conclusion, not a candidate. A comment in the rule file records the condition for putting it back: measure first, and only add it if there is a difference.

> *Correction*: the branch result was first measured at 6 runs per arm and recorded as **6/6 against 0/6**. At 12 runs it is **10/12**. The conclusion holds and *p* actually got smaller, but **six runs per arm makes 100% look like 100%.**

**The two PR-stage conventions (title format, four-section description) could not be measured locally, and both reasons are findings.** First, the harness puts `git push` in the `ask` tier and a non-interactive `-p` session cannot answer a prompt (`acceptEdits`, `dontAsk` and `bypassPermissions` were all refused) — **a headless run cannot reach the PR stage at all.** Second, give the agent a non-forge remote and it notices and stops, and a fixture elaborate enough to fool it would be measuring the disguise rather than the convention.

### Skill routing (`make bench-trigger`)

A description's English and Korean triggers and its negative routing were both claims about behaviour, and neither had ever been measured. All 5 shipped skills were measured on 12 prompts each (6 positive, 6 negative): `pr-create` 12/12, `pr-review` 12/12, `research-notes` 12/12, `repro-checklist` 12/12, `results-deck` 11/12 = **59/60**.

**Where the negatives went is the real result.** This benchmark asks "did the work go where we wrote that it would", not "did our skill stay quiet". Pre-merge commit-range review went to `superpowers:requesting-code-review`, responding to a received review to `receiving-code-review`, PR creation to `pr-create`, note-taking to `research-notes`, seeds and environment to `repro-checklist`, and presenting to `results-deck`. **The lifecycle-stage separation [ADR-0009](adr/0009-external-dependencies.md) had only declared is now confirmed by measurement.**

Only `results-deck` started at 4/6, and both misses were *development-side reporting* — the Korean triggers leaned research-side. After strengthening them, the pairwise comparison went 12/18 → 14/18, **2 improved, 0 worsened**. Sign test *p* = 0.25, not significant, so what is claimed is the absence of a regression, not an effect size.

**We also saw someone else's skill decline.** "Merge this PR and clean up the branch" is `superpowers:finishing-a-development-branch`'s seat, and all three runs went to `Bash`. Our routing is clean but the delegate does not always accept, which is the concrete instance of ADR-0009's "our routing discipline now depends on somebody else's repository".

### Do the Korean triggers earn their cost? (pilot, 2026-08-08)

The Korean triggers in a skill description take **20%** of our ~240 tok per skill (565 characters across the five), and their value had never been measured. A pilot ran on `results-deck` — **the single variable is the 133-character `한국어 트리거: '...'` clause**, with the English description, the negative-routing clause and the body byte-identical. `harness-slides` was disabled and both arms were project skills (§4b trap 3 — an installed skill cannot be measured through a stand-in).

| | With triggers | Without | Difference |
|---|---|---|---|
| pass@3 (fired at least once) | 0.83 | 0.67 | +0.16 |
| pass@1 (per trial) | 0.83 | 0.61 | +0.22 |
| **pass^3 (all three runs)** | **0.83** | **0.50** | **+0.33** |
| spread | **0.00** | 0.17 | |
| Negatives fully silent | 1.00 | 1.00 | 0 |

**Not significant** — by two-sided Fisher exact, 5/6 against 3/6 by case is *p* = 0.545, and 15/18 against 11/18 by trial is *p* = 0.264. Catching this effect at 80% power needs roughly **30 positive cases per arm**; the current set has six.

**So it stays.** The only measurement points toward keeping it, and removing it on a non-significant null would be using *absence of evidence* as *evidence of absence*. But **it is not established as earning its cost either** — this is "measured, inconclusive", not "measured, it works".

**Two side results were worth more.**

- **The negatives are 1.00 on both arms.** The Korean triggers have no effect on negative routing. The only thing the cost buys is *positive reliability*, which narrows exactly where to look.
- **The old metric could not see this question at all.** Counted by majority it is 11/12 against 10/12 — a one-case difference that reads as noise. By pass^3 it is 0.83 against 0.50, with spread 0.00 against 0.17. **Same data, different question.** Adding the reliability metrics is what made this pilot discussable.

### Deck number traceability (`make bench-claims`)

`check-claims.sh` has 33 verifier cases, but **those are not independent evidence** — the regexes and the cases were written in the same sitting, so every "not-a-claim shape" in there is one I had already thought of. So the same approach as the guards was used: **this repository's own documents from a commit before the checker existed** as the corpus.

| Corpus | Tokens checked | Flagged | New unclassified shapes |
|---|---|---|---|
| History reference (first version, no longer usable) | 262 | 113 | 21 |
| History reference (after strengthening the filters) | 193 | 60 | 6 |
| **Frozen (`evals/prose-corpus.md`)** | 143 | 41 | **0** |

**Depending on history for the corpus was a design defect.** When the repository history was rewritten the reference commit disappeared, the bench ended quietly with zero corpus and no result, and all the while the README was quoting the last number in the present tense — *the checker built to stop untraceable numbers had its own number become untraceable.* The corpus is now a file, and that file says on its own face not to regenerate it.

**The frozen corpus found one real hole**: HTML comments spanning multiple lines. Only same-line comments were handled. Fixed, with three regression cases pinned (33 → 36).

**We decided not to report a percentage.** Two attempts, both wrong in opposite directions — grouping by line context counted a real number as a false positive because an ADR number sat beside it, and grouping by `word + number` counted "frontmatter 9" as a version. Those two cannot be told apart by shape. The limit the checker already documents (`bash 5` and `hooks 6` are indistinguishable) applies to the grader too. So the output is **a list**.

Of the 41 flags, 5 are that indistinguishable kind (`bash 3.2`) and the other 36 are real numbers that legitimately have no row because the evidence table was deliberately kept small. **Zero new shapes needing a filter.**

### LSP (`make bench-lsp`)

*First run (discarded).* Measured on a read-only comprehension task: −0.5%, and turn count exactly 8.0 on both sides. At the time this was read as "the fixture is too small" — **that reading was wrong.** The real reason was the task: the mechanism the documentation describes is "diagnostics the moment you edit", and a task that forbids editing cannot fire it.

*Second run.* Switched to an editing task. The fixture is type-clean and the natural implementation of the function the task asks for is not — write it as it comes to mind and exactly one type error appears.

| Arm | type-clean | Mean tokens | Std dev | Turns |
|---|---|---|---|---|
| LSP off | **3 / 3** | 315,857 | 81,407 (CV 26%) | 11.3 |
| LSP on | **3 / 3** | 295,831 | 15,143 (CV 5%) | 11.0 |

**There was no accuracy difference to grab, and tokens −6.3% is not merely non-significant but below what this design can see.** The off arm's coefficient of variation is 26%, so catching 6.3% out of that noise at 80% power needs **137 runs per arm**. The minimum effect n=3 can actually detect is **61%**.

Two rules from this become measurement discipline.

1. **An A/B whose samples are agent sessions does not claim an effect below 20%.** At realistic n, anything under that is indistinguishable from noise.
2. **Where possible, push the measurement down to a deterministic layer.** The guard benchmark is definitive at n=1 because hooks live outside the model. `check-claims.sh` is a script rather than a skill instruction for the same reason — **tell the model to be careful and you can only confirm it with an A/B; tell a machine and you confirm it by counting.**

### The instruments were wrong nine times — all the same mistake

This may have been worth more than the measurements. All nine **looked identical on screen — "0.0 / failed"** — and most made the harness look unfairly bad.

| # | Where | What killed the instrument |
|---|---|---|
| 1 | LSP, first run | A read-only task, so the mechanism could not fire |
| 2 | Triggers | A timeout was indistinguishable from a non-trigger (`--timeout 30 --num-workers 10`) |
| 3 | Triggers | **An installed skill cannot be measured through a stand-in** — the model calls the real one |
| 4 | Triggers | Only the first tool call is examined, so starting with `Bash` is recorded as a non-trigger |
| 5 | Conventions | `harnessctl init` was never run in the scratch repository, so the rules were simply not there |
| 6 | Conventions | The task was a one-line edit — a size our R1-3 **explicitly exempts** |
| 7 | Conventions (R6) | `harnessctl` was found in the **installed cache**, so it installed the released payload rather than the rule just written. The new rule is not in that payload, so the effect is structurally zero |
| 8 | Conventions (R6) | The fixture's verification command was `./check.sh`, and **the allow tier's only runner was `make`, so it was refused.** 0/3 on both arms was the shadow of permissions, not of the rule |
| 9 | Tiers | **The grader counted a correct answer wrong.** `scripts/verify-doc-refs.sh` is the same answer as `verify-doc-refs.sh` but the directory prefix made it a MISS, and `tr` died with `Illegal byte sequence` on a Korean response, skipping normalisation entirely. Three tiers appearing side by side at 90% was **each tier hitting the grader once** |

**7 and 8 stab the same spot from two directions**: is the rule you are measuring *in the payload*, and is the behaviour the rule mandates *permitted*. Both appear on screen as "the rule earned nothing". So `bench-convention` now looks for the working tree's `harnessctl` first and **prints which copy it used**, and 8 went into the ledger as a permissions gap — changing the fixture to `make check` fitted the instrument to an allowed runner; it did not fix the gap.

**Rule: when you get a negative result, check whether the conditions for the mechanism to fire were met before concluding anything.** Run a positive control alongside any trigger measurement — an uninstalled skill that must certainly fire. Traps 2, 3 and 4 would all have been caught by that one control. And **one run per query is not a measurement**: measured once, `results-deck` is 4/6 both before and after the fix, with different members.

### Not yet measured

- **The two PR-stage conventions.** Impossible locally for the two reasons above. A throwaway repository on a real forge would do it.
- **The rest of `CLAUDE.md`'s principles.** The branch convention was measured, but whether "Simplicity First" actually makes code simpler is hard to write a grading criterion for. `skill-creator`'s grader subagent is the candidate for that seat — and `ponytail` (§3b) has already run this exact measurement, so the design is there to copy.
- **The installer is not an A/B subject in principle.** "Uninstall restores the original" is an invariant, not a claim with a comparison group, and `scripts/verify-install.sh`'s 112 assertions pin it (particularly that `settings.json` is canonically identical after uninstall).

## 5. Guide vs Guard

- **Guard** — fail it and the tool call does not happen at all. Permissions and blocking hooks. The line of defence against accidents is always here.
- **Guide** — followed by the agent's judgement. Conventions, skills, informational hooks. Violate one and the tool still runs.

A guard cannot be replaced by a guide (the agent can ignore a guide), and a guide cannot be enforced as a guard (not every case can be encoded in advance). **Both layers are necessary.**

One rule follows: **only blocking hooks use exit 2.** An informational hook that stops a turn gets switched off by the user, and the information goes with it.

## 6. The ownership model

A consumer's configuration is a space where our things and theirs mix. There are now two bases for deciding what is ours — the most complicated one disappeared when hooks moved into the plugin.

- **The plugin cache is component ownership.** Hooks, skills, commands and verifiers live only inside the plugin directory and are never copied into the consumer tree. The `hooks` block of `settings.json` is **something we do not touch** — a verifier asserts `.hooks` is byte-identical before and after install. The old path marker and strip-then-append are retired.
- **`harness-manifest.json` is the receipt for everything else.** The permission strings actually added, the scalar keys set, the JSON containers we created, the line appended to `.gitignore`. Uninstall reverses this receipt and nothing more — a value the consumer already had is not deleted even when it is the same string.

The two tiers are unchanged: **managed** (overwritten on reinstall — currently just `rules/`) and **template** (copied once, the consumer's thereafter — `CLAUDE.md` and the two path config files).

`harnessctl` ships in `bin/`, which puts it on the Bash tool's PATH automatically, and it finds its own payload at `<its own location>/../declarative`. The plugin cache is a faithful copy, so that one relative path works from the cache and from a source checkout alike — not even `${CLAUDE_PLUGIN_ROOT}` is needed.

**No index file is installed.** We observed a hand-maintained inventory in a reference harness actually drift. The inventory lives in this one document, and the file list is derived from the tree.

## 7. Backlog

**Held, waiting for the second occurrence** (there is a corresponding row in §2, and it has happened once or not at all):

- ✅ ~~Worktree helper~~ — decided against building one. Superpowers' `using-git-worktrees` solves it upstream. The most direct gain from adopting an external dependency, and code we did not write is the gain itself.
- ⏳ Release / changelog skill — a `dev` module candidate. Release conventions differ too much per project for a common core to be visible yet.
- ⏳ A post-hoc output scrubber — blocking a command with PreToolUse and catching sensitive strings in *output* with PostToolUse are different accidents. The mirror-pair pattern itself is proven (the reference harness's PHI pair), but a general-purpose harness has no payload to use. If site-specific patterns are needed, it goes in a consumer-owned config file like `protected-paths`.
- ⏳ **Model and effort orchestration.** The harness currently ships no sub-agents to consumers, so this lever does not exist. Plugin agent frontmatter supports `model` and `effort` (`hooks`, `mcpServers` and `permissionMode` are refused for security), so keeping the main loop on Opus high while pushing mechanical delegation down to a cheaper tier is possible. This session is the evidence — 12 subagents were launched and all inherited the session model, and half of them (path substitution, counting, updating documents) did not need Opus. But *which work goes to which tier* takes judgement, and getting it wrong costs more when the expensive model redoes what the cheap one missed. Candidate axis: exploration, counting and mechanical edits low; design, adversarial review and root cause high.
- ⏳ Anchoring the `hooks.json` matcher. Today `Read|Write|...|Bash` has no anchors. If Claude Code treats a matcher as a regex, `Bash` also matches `BashOutput` and four guards spin uselessly on every call (each reading stdin, calling jq, exiting 0). Wrapping in `^(...)$` would remove that for free, but **we could not confirm how matching works** — if it is string comparison rather than regex, the anchors break matching instead. Both reference harnesses run without anchors, so we followed the convention. When it is confirmed, change it.
- ⏳ `harnessctl --scope local` (targeting `settings.local.json`) — the place for permissions you will not commit. No real demand yet.
- ⏳ More language profiles (`go`, `rust`, `java`, …) — one manifest each, added when actually used.
- ⏳ A `harness-frontend` profile — `ui-ux-pro-max` carries a large body of style, palette and stack references, so the candidate is clear. Zero occurrences in this repository, though ([ADR-0011](adr/0011-ecosystem-survey.md)).
- ⏳ Session hand-off on the development side — the `handoff` family exists and the research side is already covered by the five-document set. When real demand appears twice on the development side.
- ✅ Session records — answered by [`harness-log`](harness-log.md), which inverts the reason `claude-mem` was held (storing all tool I/O) by making **not storing** the design. It keeps prompts and final answers and drops tool output, subagent transcripts and compaction summaries. Ten of its 44 verification cases watch for *what must not appear*. `claude-mem` itself is still held ([ADR-0011](adr/0011-ecosystem-survey.md)).
- ⏳ MCP server registration — the merge surface grows to include `.mcp.json`. The installer's ownership model would have to apply to that file too, so: after real demand.
- ⏳ `dev`: a review item for "documents and configuration examples this change made false". A draft was written and pulled — it is language-agnostic and plausible, but has zero occurrences, and it looks exactly like adding something because it seems nice to have. If a real review misses a stale README, that is occurrence 1.
- ⏳ `research`: a negative-results section in the `FINDINGS.md` template. The reasoning (stop people walking a dead path twice) is the same reasoning that justifies the ledger. A template should be a skeleton, so it was left out for now.

**Recorded risks** (no solution yet, and they will show up in a consumer first):

- **The five-document set assumes the project has runs.** In research that is mostly reading and synthesis (a literature survey, a design review) the ledger is thin and there is nothing to put in `ARTIFACTS.md`. The discipline does not break, but two of the five sit empty, and **an empty mandatory document teaches people to ignore the whole set.** The answer in that case is not to weaken the invariant but to keep a lighter variant separately — when a real case appears.
- **`ARTIFACTS.md`'s "every claim traces to a run" is strong.** It is exactly right for a project whose numbers outlive the session, and pure overhead for a one-off analysis nobody will quote. It is kept as an invariant anyway, because weakening it to "record the important numbers" makes it unenforceable.
- **Observed tool friction**: a subagent's Write was blocked on `templates/FINDINGS.md` by filename pattern matching (a report-file writing guard). The `research` module ships three templates with those names, so anyone editing or installing them through a subagent hits the same wall. Not something the harness can fix, but something to know.

**Deliberately not doing**:

- An installed index file (§6).
- A jq-free path in `install.sh`. Hooks require jq, so an install without it delivers nothing but self-disabled guards, and an honest failure is better ([ADR-0002](adr/0002-hook-contract.md)).
- Per-module partial uninstall. Dropping a module with `--with` deletes its files, so no separate command is needed.

## 8. Directory layout

```
.
├── .claude-plugin/marketplace.json     # catalogue of the six plugins
├── plugins/
│   ├── harness-core/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── hooks/hooks.json            # event and matcher registration
│   │   ├── hooks/*.sh                  # 5 blocking + 2 informational
│   │   ├── skills/pr-create/SKILL.md
│   │   ├── commands/verify.md
│   │   ├── scripts/{_verify-lib,verify-*}.sh
│   │   ├── bin/harnessctl              # init, doctor, uninstall
│   │   ├── bin/harness-log             # session history → self-contained HTML
│   │   └── declarative/                # what a plugin cannot carry
│   │       ├── settings-fragment.json  # permissions + scalars (no hooks)
│   │       ├── CLAUDE.md               # template
│   │       ├── templates/{protected,allowed}-paths.txt, gh-account.txt
│   │       └── rules/{core,dev,research}/*.md
│   ├── harness-dev/            # skills/pr-review + deps: core, superpowers
│   ├── harness-research/       # skills/{research-notes,repro-checklist} + deps: core
│   ├── harness-slides/         # deps: core — the results-deck skill + check-claims.sh
│   ├── harness-python/         # deps: core, pyright-lsp
│   └── harness-typescript/     # deps: core, typescript-lsp
├── install.sh                          # thin bootstrap
├── scripts/verify-{install,frontmatter}.sh
├── Makefile · CLAUDE.md · .claude/     # developing this repository itself
├── AGENTS.md                           # the same conventions, summarised for other agents
├── .github/workflows/verify.yml        # ubuntu · macOS bash 3.2 · plugin manifests
└── docs/ (agent-layer.md · harness-log.md · adr/0001..0013 · hooks/*.md)
```

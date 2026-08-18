# Agent Layer — what the harness is, where it stands, how it is verified

The **single source of truth** for this repository. What the harness covers, what gets built next, and how its behaviour is verified is written here and nowhere else ([ADR-0004](adr/0004-single-source-of-truth.md)).

## 1. Definition

| Artifact | Location | Role |
|---|---|---|
| Plugins | `plugins/harness-{core,dev,research,slides,frontend}/` and the language profiles `plugins/harness-{python,typescript,csharp,cpp,lua,swift,kotlin}/` | Hooks, skills, commands, verifiers, and `bin/` executables (`harnessctl`, [`harness-log`](harness-log.md)). Claude Code loads them directly and puts `bin/` on the Bash tool's PATH |
| Declarative installer | `plugins/harness-core/bin/harnessctl` | Writes what a plugin cannot carry — permissions, `CLAUDE.md`, `rules` — to the target, and removes it symmetrically |
| Bootstrap | `install.sh` | The whole install in one command: ensure jq → register the marketplace → plugins → `harnessctl init` → language servers → `doctor`. It holds no harness logic; it calls the two halves in order |
| Removal | `uninstall.sh` | The same four things taken back, in the only order that works — `harnessctl uninstall` → plugins → marketplace → shims. harnessctl ships *inside* the plugin cache, so removing the plugins first strands the declarative half. A bootstrapped jq, `npm -g` language servers and any plugin this harness did not install are reported, never removed |
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
| A result has to become a talk, and the figures in the talk drift from the runs that produced them | Site-dependent | The `slides` module |
| An established result has no path to a manuscript, so its numbers are retyped and their provenance is lost | Site-dependent | ⏳ nothing — §7 |
| Game and app code gets no symbol layer, because the language profiles stop at Python and TypeScript | Site-dependent | The language profiles (⏳ for C#, Swift, Kotlin, Lua, C++); `frontend` covers the UI side only |

When adding an item to the §7 backlog, **say which row of this table it answers**. If there is no such row, add the row first — and then ask yourself whether it has actually happened twice.

> **The last three rows were added on 2026-08-18, after the fact.** This harness was built for five kinds of work — research, development, presentation, paper writing, and game or app development — and only the first two had ever been written down here. That is a failure of this table rather than of the modules: `harness-slides` shipped without the row that its own rule says must exist first, and the two unserved kinds could not be missed from a backlog they were never entered into. The consequence was visible in §7, whose language-profile row named `go`, `rust` and `java` — backend languages nobody had asked for — while the game and app languages behind a stated goal went unlisted.
>
> **`Site-dependent` is the honest frequency for all three**, and it is the same basis §3b accepted for `claude-video` and `ui-ux-pro-max`: the owner states the need, and whether it recurs depends on the installation rather than on the tool. It is not a claim that these happened twice here.

## 3. Categories and the adoption ladder

Eight categories. **The adoption order is the axis of progress** — guardrails → guides → automation → delegation → external connections. Go in reverse and automation amplifies the accidents.

| Phase | Category | Location | Now |
|---|---|---|---|
| **0** | Conventions | `CLAUDE.md`, `.claude/rules/harness/**` | ✅ core 1 + dev 1 + research 1 |
| **0** | Permissions | `settings.json` (merged from a fragment) | ✅ allow 47 / ask 3 / deny 8 ([ADR-0012](adr/0012-test-runners-in-allow.md)) |
| **1** | Hooks | `plugins/harness-core/hooks/` — registered by `hooks.json` | ✅ 7 (5 blocking, 2 informational) |
| **1** | Skills | `plugins/*/skills/<name>/SKILL.md` | ✅ core 1 + dev 2 + research 2 + slides 2, with Superpowers 14 on top — and `ui-ux-pro-max` 7 more when `frontend` is installed |
| **2** | Sub-agents | `.claude/agents/*.md` | ⏳ 1 for the harness itself (`harness-reviewer`) — none for consumers |
| **3** | Slash commands | `plugins/harness-core/commands/*.md` (what consumers get; `.claude/commands/` is this repository's own copy) | ✅ 1 (`/verify`) |
| **3** | Executables | `plugins/*/bin/` | ✅ 2 — `harnessctl` (install, check, remove) and [`harness-log`](harness-log.md) (session history → HTML) |
| **4** | MCP servers | `.mcp.json` | ⏳ none |
| **—** | External plugins | A profile's `dependencies` | ✅ Superpowers, 2 LSPs, `ui-ux-pro-max` ([ADR-0009](adr/0009-external-dependencies.md)) — the last one is the first dependency taken from a marketplace Anthropic does not curate |
| **—** | External instruments | Installed by the developer (not shipped) | ⏳ none — `skill-creator` was adopted ([ADR-0011](adr/0011-ecosystem-survey.md)), found orphaned and never used on 2026-08-13, and demoted; re-adopt when `claude plugin eval` leaves early access (its `--ablation with-without` is the native form of the paired runs that justified adoption) |
| **—** | External npm tools | `harnessctl doctor` checks PATH | ✅ `slides-grab` (slides, [ADR-0010](adr/0010-slides-profile.md)) |

> Phase 0 is guardrails, Phase 1 is the guides and automation on top of them, Phase 2 is the division of labour on top of that. **Each phase is the safety net for the next.**

Having no consumer-facing sub-agent yet is a judgement, not an omission. We could invent one; there has not yet been a delegation that was actually needed twice.

## 3b. Ecosystem verdicts — what came in, and what got measured

The detail behind §3's last three rows (external plugins, external instruments, external npm tools). **The reasoning and the measurements live in one table** — scattered, the same candidate gets reviewed twice. The narrative is [ADR-0011](adr/0011-ecosystem-survey.md), the consumer-facing summary is in the README, and both point here.

**The measurement column is the point of this table.** Most of it is empty, and that means not yet measured — not no effect.

| Subject | What | Verdict | Basis | Measured | Always-on cost |
|---|---|---|---|---|---|
| [`superpowers`](https://github.com/obra/superpowers) | 14 development-workflow skills | **Depend** | Covers development workflow broadly. No reason for us to build it | Our routing **59/60**. One delegation was not accepted, though — three merge requests all went to `Bash` | ~688 |
| [`mattpocock/skills`](https://github.com/mattpocock/skills) (MIT) | 25 workflow skills on the official marketplace — tdd, code-review, diagnosing-bugs, research, handoff, domain-modeling, grilling | **Do not install alongside Superpowers** | Not a complement but a competitor: the overlap sits at the **same lifecycle stage**, so [ADR-0009](adr/0009-external-dependencies.md)'s dividing line has nothing to divide. The concrete cost is the row above — our **59/60** was measured against Superpowers, and 25 more descriptions in the trigger space makes that number stale the moment they load. Its own per-repository installer (`setup-matt-pocock-skills`) would be a second installer in the consumer tree (§6). Genuinely new: `to-spec` / `to-tickets` / `wayfinder` | **None published. Ours is partial and stopped on purpose: 2 of 5 sets, 2026-08-13.** Installed at user scope, `bench-trigger.py` at 3 runs — `pr-create` **11/12**, `pr-review` **11/12** against a documented 12/12 each. **Both misses opened with `Bash`, not with a mattpocock skill**, and all 12 negatives held, including the two Superpowers seats (`requesting-code-review`, `receiving-code-review`) at 3/3. A one-case move is the size §4b already calls noise, so this claims **no observed seat-stealing** and nothing more. Stopped at 2/5 because the framing was wrong: as "should we adopt mattpocock" the decision was already made on other grounds, so the remaining ~110 sessions bought nothing. The version worth running is a **load test** — our routing against a deliberately crowded trigger space, sized in steps — and mattpocock is a poor instrument for it. Uninstalled afterwards | **~1,609 tok always-on measured 2026-08-13** (25 skills, 0 agents) |
| [`get-shit-done`](https://github.com/open-gsd/gsd-core) (MIT) | Spec-driven meta-prompting — a discuss → plan → execute → verify loop with its own agents, `/gsd:*` commands and npx installer, on 14+ runtimes. ~59k stars | **Do not install alongside Superpowers — the row above's verdict at larger scale** | The overlap sits at the same lifecycle stage as `writing-plans` / `executing-plans` / `subagent-driven-development`, so [ADR-0009](adr/0009-external-dependencies.md)'s line has nothing to divide — and its installer writes its own command and agent tree into the consumer config, a second installer with its own ownership model (§6). **Two absorb pointers survive the verdict**: its model profiles (quality / balanced / budget) are a shipped instance of §7's *model and effort orchestration* row, and its "context rot" discipline — fresh context per task, plan artifacts, atomic commits — is the argument our R1 makes, arrived at independently at 59k stars | **None published** — 59k stars is popularity, not measurement, the `harness-100` shape again. Ours not run: it is not a Claude plugin, so `claude plugin details` cannot price it, and measuring means running its installer against a redirected HOME | Own command + agent tree |
| `pyright-lsp`, `typescript-lsp` | Language server connection | **Depend** | A dependency of the language profiles | **Inconclusive** — tokens −6.3%, and this design's MDE is 61% | **0** |
| [`harness-100`](https://github.com/revfactory/harness-100) | 100 domain verticals (Apache-2.0) | **Depend, do not absorb** | An individual harness cannot pass ADR-0001's admission test by construction. Absorbing six domains ≈ 35k tok | Coexistence: **zero conflicts** — our skills held 6/6 negatives unanimously across three runs each | ~560 each, **only what you install** |
| `skill-creator` (official) | An evaluation harness — 3 subagents + 7 scripts | **Adopted, then demoted 2026-08-13** | The name says authoring helper; the body is an instrument. Installed 08-07, orphaned 08-09, **never used once** — the verdict outlived the installation and only a re-review noticed. Re-adopt when `claude plugin eval` leaves early access: its `--help` already advertises `--ablation with-without`, the native form of the paired with/without runs that were the reason to adopt, but at runtime it still refuses (*"currently in early access"*, confirmed 2026-08-13) | — | 112 always-on / **10.9k per call** (when installed) |
| [`skilltester`](https://github.com/skilltester-ai/skilltester) | Skill evaluation — paired `baseline` / `with_skill` runs plus a security probe suite, normalised into a utility score, a security score and a three-level security label | **Named instrument, not adopted — 2026-08-14** | The row above's seat, filled from outside: paired with/without runs are exactly what `skill-creator` was adopted for and what `claude plugin eval --ablation with-without` still refuses. Two things stop it being the stand-in. It evaluates **one skill in isolation**, so it cannot answer the question that prompted the search (§7's trigger-space load test), and its own scoring is self-described as *still evolving* — adopting a moving instrument with no use waiting is the row above's mistake exactly. Read again the day a skill needs a utility number | — | 0 until installed |
| [`skillsbench`](https://github.com/benchflow-ai/skillsbench) | 87 tasks across 8 domains, containerised, with deterministic verifiers. **Paired evaluation** — matched no-Skills and curated-Skills runs over 18 model-harness configurations; the CLI's `--skill-mode` also carries a self-generated-Skills arm | **Absorb the finding, not the harness — 2026-08-14** | The closest thing found to a composite measurement, and still not one: a task is handed **a set curated for that task** and the agent selects within it, so what is measured is selection inside a purpose-built set, not interference from a room assembled for other reasons. §7's trigger-space load test seat stays empty. What transfers is the result, which is our own *adding is a trade* in someone else's data | **Theirs, not ours** — [arXiv:2602.12670v4](https://arxiv.org/abs/2602.12670v4), current since 2026-06-14: curated Skills raise the average pass rate **33.9% → 50.5%** (**+16.6pp**, 25.5% normalised gain), configuration-level gains **+4.1 to +25.7pp**. **Cite the version, because v4 replaced the experiment.** v1–v3 (to 2026-03-13) ran 86 tasks over 11 domains and 7 configurations, and the figures that circulate from it — +16.2pp, +4.5pp (Software Engineering) to +51.9pp (Healthcare), 16 of 84 tasks with a negative delta — describe a benchmark that no longer exists. One v1 result has no v4 counterpart and is the one worth keeping: **self-generated Skills gave no benefit on average — a model could not reliably author the procedural knowledge it benefits from consuming** | 0 (absorbed) |
| [`stanford-iris-lab/meta-harness`](https://github.com/stanford-iris-lab/meta-harness) | An outer-loop optimiser that **searches over harness code** on a fixed base model. Reference experiments: memory-system search for text classification, scaffold evolution for Terminal-Bench 2.0 | **Unjudged — read the body before any verdict** | The only candidate found that operates on a whole harness rather than a component, which is the shape the search was for. But what it searches is *harness code* — what to store, retrieve and show — and ours is prose, permissions and hooks, with the composite's context and routing being the thing we would want searched. Whether that maps is not decidable from the README, and [ADR-0011](adr/0011-ecosystem-survey.md)'s rule is that the verdict comes from the body | **Not measured.** Paper reports gains on online text classification, retrieval-augmented math reasoning and agentic coding (TerminalBench-2) | — |
| `karpathy-guidelines` (MIT) | Four principles on LLM coding pitfalls | **Do not install, absorb the text** | Our `CLAUDE.md` §1–4 already is this | 20 of 23 normative sentences matched **verbatim** | 0 (absorbed) |
| `task-observer` (CC BY 4.0) | Session observation → an improvement ledger | **Do not install, absorb the mechanism** | Half of its 446 lines overlap our §5 | — | 0 (absorbed) |
| [`slides-grab`](https://www.npmjs.com/package/slides-grab) | Slide rendering | **External tool** | Rendering is a solved problem. `doctor` checks PATH | — | 0 |
| `graphify` (an ehr-research project skill), `CodeGraph`, `GitNexus` | Codebase knowledge graphs — precompute the structure and serve it over MCP | **Unjudged** | We have no corresponding asset. An LSP is the symbol layer and answers a different question ([axes](engineering-axes.md)) | **Not measured.** Others report tokens −47% and tool calls −58% (`CodeGraph`, 7 repositories) | Index maintenance |
| [`Understand-Anything`](https://github.com/Lum1104/Understand-Anything) (MIT) | Codebase → knowledge graph. 8 commands + 7 agents, index committed to the repository as `.ua/` | **Loses to the row below** | The second concrete candidate for the graph row, and it loses on both axes. **Delivery** — a plugin carrying 8 commands and 7 agents, against an MCP server with no plugin surface at all, and it asks the consumer to commit a generated index, which is what `large-file-veto` exists for. **Evidence** — none, against 31 repositories. Note also that the README's marketplace command reads `Egonex-AI/…` while the repository is `Lum1104/…`; which is canonical is unconfirmed | **None published** | 8 commands + 7 agents, plus the `.ua/` index |
| [`ponytail`](https://github.com/dietrichgebert/ponytail) (MIT) | A "lazy senior dev" ruleset — always-on `AGENTS.md` + 6 skills + hooks | **Held, but its eval design absorbed** | It argues what our `CLAUDE.md` §2 argues. The difference is that **they measured and we did not** | Their claim: **LOC −54%, tokens −22%, cost −20%, time −27%** (same agent ±skill, n=4, Haiku 4.5, 12 tickets on the fastapi template, scored on the git diff) | Always-on `AGENTS.md` + 6 skills |
| [`codebase-memory-mcp`](https://github.com/DeusData/codebase-memory-mcp) (MIT) | Codebase → knowledge-graph MCP. A static binary plus SQLite, with a file watcher | **Top candidate** | The concrete candidate for the graph row above. Being MCP, it adds no plugin surface | Their claim: 31 repositories, 12 question categories, Opus 4.6: **quality 0.83 vs 0.92**, **10×** fewer tokens, 2.1× fewer tool calls, latency `<<1ms` vs 10–30s. Weakest on macro-heavy C (0.58 vs 1.00) and exhaustive grep | The index (`~/.cache`) |
| [`headroom`](https://extraheadroom.com/) | Input-side compression — logs, JSON, build output | **Rejected** | Not a plugin but a **local proxy**. Every prompt passes through it, so the same verdict as `omniroute`: a security decision, not a harness one, and the app is paid (\$5–60/month) | Their claim: ~50% on noisy input, 15–25% in real sessions | — |
| [`caveman`](https://github.com/JuliusBrussee/caveman) | 65% fewer output tokens. An MIT skill over a BSL-1.1 proxy and engine | **Rejected** | **Basis corrected 2026-08-13.** It was recorded as a head-on conflict with [ADR-0002](adr/0002-hook-contract.md)'s block-message contract. Reading the body, the skill claims to preserve code, commands and error messages verbatim — and a block message is *hook stderr*, which `caveman` never sees. What it compresses is the model's **relay** of it, so the conflict is real but softer than recorded, and unmeasured in either direction. What actually decides the verdict is that the value sits in the **proxy and engine** layer: BSL-1.1, and a proxy, so the same verdict as `headroom` and `omniroute`. The MIT skill on its own is the weak half | Their claim: output −65%, and −33.2% provider-reported input tokens through the proxy | — |
| [`ui-ux-pro-max`](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) (MIT) | UI/UX design reference — styles, palettes, font pairings, charts, and per-stack guidance across 22 stacks | **Depend — 2026-08-18, and it opens `harness-frontend`** | The blocker was never the candidate, it was demand: *zero occurrences in this repository*. That is cleared the way [`claude-video`](https://github.com/bradautomates/claude-video)'s was — **the owner stating a need**, which §2's site-dependent rows already accept as a basis. Delivery is the `harness-python` shape exactly: one manifest, no files of ours. **Two things the README could not have told us.** ① It advertises *"a single unified skill"* and the installed plugin ships **seven** (`banner-design`, `brand`, `design`, `design-system`, `slides`, `ui-styling`, `ui-ux-pro-max`) — the ADR-0011 rule again, on our own survey. ② One of those seven is named `slides` and another `design`, so it lands on `results-deck`'s seat and on the platform's own `design` skill; the negative-routing measurement below is what decides whether that matters. Its npm installer (`uipro init`) writes skill files into the consumer tree and is **not** the path we use — that is §6's second-installer objection, the one that stopped `mattpocock/skills` | **Measured 2026-08-18: ~716 tok always-on**, `claude plugin details` in a scratch `CLAUDE_CONFIG_DIR`. Worst case moves ~7,211 → ~7,927 against a 9,000 ceiling, so **1,073 headroom** and the profile is opt-in, not default. **Routing measured 2026-08-18, paired with a control arm**: negatives **6/6 with it and 6/6 without**, positives **10/18 in both**, and **no miss in either arm reached a `ui-ux-pro-max` skill** — the seven extra descriptions take no seat of ours (§4b) | **~716 tok measured**, and only when `frontend` is installed |
| [`taste-skill`](https://github.com/Leonxlnx/taste-skill) (MIT) | Frontend design taste — DESIGN_VARIANCE / MOTION_INTENSITY / VISUAL_DENSITY dials. **13 skills**, not the one the README leads with | **Held — the same row as above** | Domain-profile material, zero occurrences here, so the verdict is unchanged. What it changes is the §7 entry: that row was blocked on **occurrences, not candidates**, and it now has two. **It is also the wrong thing to park at user scope** — see the cost | **Measured 2026-08-13: ~1,697 tok always-on.** Predicted "near zero" before installing and it is more than `rules/core/workflow.md` (1,539), paid in every session on every project. The §4 second axis decides this one: at zero frontend work a month it is pure loss, so project scope on frontend repositories or nothing. **It is also a family, not one repo**: `emilkowalski/skill` and `pbakaus/impeccable` are merged with it in `h3nryprod01/design-taste`, and `senlindesign/taste-skill` inverts the direction — reverse-engineering an existing site's taste into tokens. If `harness-frontend` ever opens, survey the family, not the one name | **~1,697 tok measured** |
| `claude-mem` | Session capture via 5 lifecycle hooks → SQLite | **Held** | Stores **all tool I/O**. Not possible in a repository running `secret-scrubber` without checking first | — | — |
| [`agentmemory`](https://github.com/rohitg00/agentmemory) (Apache-2.0) | Persistent memory — 12 lifecycle hooks, 54 MCP tools, 15 skills, SQLite plus vectors on a pinned `iii-engine`, four local ports | **Rejected — it is the design we deliberately inverted** | The row above's property at a larger scale: `PostToolUse` records tool name, input parameters **and output results**. §7 closed session records with [`harness-log`](harness-log.md), whose whole design is *not storing* them — 10 of its 44 cases watch for what must not appear. It does ship a "strip secrets" privacy filter, and that is precisely the claim that would have to be run against our own 65-case incident corpus before it could be believed | Their claim only | 15 skills always-on, plus a third-party runtime |
| `omniroute` | A local gateway for 290+ providers | **Rejected** | Not a plugin but a proxy. A security decision, not a harness one | — | — |
| `handoff` | Context hand-off between sessions | **Held** | The five-document set covers the research side. Zero occurrences on the development side | — | — |
| [`claude-video`](https://github.com/bradautomates/claude-video) (MIT) | `/watch` — video → scene frames plus a timestamped transcript. ffmpeg and yt-dlp, with a Whisper key needed only when a video has no captions | **Depend — approved 2026-08-13, gated on the upstream fix** | The first verdict ("not shipped — a personal tool") rested on a misreading of §1: the non-goal forbids **building** general-purpose working skills, and *composing the ability to do work through a profile's `dependencies`* is the prescribed path — the same reading that admitted Superpowers. Re-tested, everything passes: ADR-0001's admission (video review is domain- and stack-agnostic), delivery (a plugin; zero new files on our side), and the shape is exactly the `slides-grab` precedent — external tools on PATH, checked by `doctor` (`ffmpeg`, `yt-dlp`). Demand basis is the site owner's stated recurring need, the same basis as §2's site-dependent rows. Ships as a `harness-dev` dependency once the defect in the next column is fixed upstream | **Measured 2026-08-13: ~98 tok always-on** (1 skill, 1 `SessionStart` hook) — **the cheapest description and the most expensive body in this table**, the §4 second axis in one row. Their figures for the call side: a 49-minute video is 9.8–22.8k image tokens by detail mode, plus ~26.6k of transcript. **Running it also found a defect the README could not have shown**: `frames.py:256` and `:615` pass `-vsync vfr`, an option **removed in ffmpeg 8**, so on ffmpeg ≥ 8 every frame-producing mode dies and only `--detail transcript` survives. One line (`-fps_mode vfr`) fixes it — verified on ffmpeg 9.0.1 in a scratch copy, 12 frames extracted. Not patched in the plugin cache, which `claude plugin update` overwrites | **~98 tok measured** |
| [`ECC`](https://github.com/affaan-m/ECC) (MIT) | "Agent harness operating system" — 68 agents, 378 skills, 94 command shims, 7 hooks, an MCP server, always-loaded rules, AgentShield | **Rejected on the ceiling — measured** | Structurally it is not a module but **the same product** — rules, hooks, agents, installer, profiles — so adopting it means replacing this harness, not extending it. But the verdict does not need that argument: the always-on cost is 3.1× the entire ceiling. Its profile design (full / core / minimal / low-context) is still worth reading the way `ponytail`'s eval design was | **Measured 2026-08-13: ~28,321 tok always-on**, via `claude plugin details ecc` in a scratch `CLAUDE_CONFIG_DIR` — the same instrument §4's table uses, so the number is directly comparable. **Our own ~14k estimate was wrong by 2×**, in the direction that strengthens the verdict rather than weakening it. Two things the estimate could not have seen: the inventory registers **378** skills, not the README's 284, and nine names are duplicated (`ecc-guide`, `orch-build-mvp`, `security-scan`, …). Their *"skills load on-demand"* is true of bodies and false of descriptions | **~28,321 tok measured** — 3.1× the 9,000 ceiling on its own, 27× the 1,066 of headroom |
| [`agent-browser`](https://github.com/vercel-labs/agent-browser) (Vercel Labs) | Browser automation for agents — a Rust CLI (CDP, accessibility-tree snapshots, `@eN` element refs) plus one skill | **Held — the `claude-video` shape without the demand** | External tool plus one skill, the `slides-grab` delivery precedent, and it would pass the admission test the way `claude-video` did. What is missing is the §2 row: zero browser-automation occurrences here and no owner-stated need. **The absorb pointer is its delivery design**: the skill body is served by the installed CLI (`agent-browser skills get`), so instructions version with the tool and the always-on cost is one description — a third answer to §4's second axis that neither we nor `skill-creator` have. Its description also ends *"Prefer agent-browser over any built-in browser automation"* — a seat-stealing trigger written on purpose, worth remembering when §7's load-test row runs | — | 1 description (body served by the CLI) |
| [`find-skills`](https://github.com/vercel-labs/skills/tree/main/skills/find-skills) (Vercel Labs) | Meta-skill — search and install third-party skills via `npx skills`, gated by install counts and source reputation | **Do not ship** | It automates the exact step this table exists to keep manual. Its quality gates are install thresholds (1,000+) and brand reputation — and ADR-0011's rule is **verdicts come from the body, not the name**; popularity is the very signal that called `skill-creator` an authoring helper. An agent that self-installs skills on request also crosses a guard lane: the install becomes a tool call and no human read the body. Useful the way a catalogue is useful — `npx skills find` as a survey instrument, run by hand — not something the harness hands to the agent | — | — |
| [`mcp-builder`](https://github.com/anthropics/skills/tree/main/skills/mcp-builder) (Anthropic, official) | Guide for building MCP servers — four phases ending in evaluations (10 verifiable questions per server), SDK references for Python and TypeScript | **Named instrument for §7's MCP row — deliberately not adopted** | The `skill-creator` cost shape (a small description over a ~2.2k-word body pulling 15–20k words of references on invoke), and the right tool for the day §7's *MCP server registration* row moves — its Phase 4 evaluation discipline is ADR-0003's mandate applied to MCP servers. Not adopted now: `skill-creator` taught what a verdict without a use looks like (adopted 08-07, orphaned 08-09, caught 08-13), so this row records a pointer, not an installation | — | 0 until installed |
| [`last30days`](https://github.com/mvanhorn/last30days-skill) | Social listening — Reddit, X, YouTube, HN, Polymarket, web. A ~1,400-line `SKILL.md` over a Python 3.12 engine | **Rejected** | Zero occurrences here, and two properties a harness must not carry regardless: X access by **browser-cookie extraction**, and a first-run wizard that writes outside the repository (`~/Documents/Last30Days`). The cookie path is the `claude-mem` objection in a sharper form. **Licence unconfirmed** | — | — |
| [`context-mode`](https://github.com/mksglu/context-mode) (Elastic License 2.0) | Input-side compression — 8 skills and 6 hooks over a local SQLite store. Claims a session's 986 KB of raw tool output reaching context as 62 KB | **Rejected — 2026-08-18. It lands on the `agentmemory` row, not on the compression row it appeared to open** | It was picked up as *the first candidate on the compression row that is not a proxy* — `headroom`, `omniroute` and `caveman` were all turned away for routing prompts through someone else's process, and this one is local with no telemetry. **Reading the hooks reverses that.** Its `PostToolUse` writes `tool_input` and `tool_response` into a database, which is precisely the property that held `claude-mem` and rejected `agentmemory`; [`harness-log`](harness-log.md) exists to do the opposite, and 10 of its 44 cases watch for what must not appear. Local storage answers an objection nobody made — the objection was never the network, it was the capture. Two more, either sufficient alone: its `PreToolUse` matches `Bash` and can return `"deny"`, making it **a second blocking hook on the same event and matcher as four of our five guards**, and the licence is not OSI-approved | **Measured 2026-08-18: ~631 tok always-on** (8 skills; the 6 hooks cost no model context). Fits the remaining headroom, which is what makes the hook and capture findings the deciding ones rather than the arithmetic | ~631 |
| [`compound-engineering`](https://github.com/EveryInc/compound-engineering-plugin) (MIT) | A six-step loop — brainstorm → plan → work → simplify → review → **compound** — where the last step writes what was learned into `solutions/` | **Rejected on the ceiling, absorb the return arrow — 2026-08-18** | **The arithmetic decides it before the design argument is needed**: 2,354 tok is 2.2× the 1,073 of headroom left once `frontend` is installed, so it cannot go in without raising a ceiling there is no reason to raise. The design argument holds anyway — `ce-brainstorm` / `ce-plan` / `ce-work` sit at the same lifecycle stage as Superpowers, so [ADR-0009](adr/0009-external-dependencies.md)'s dividing line has nothing to cut on, and its command tree is a second installer in the consumer config (§6). **What is worth taking is one arrow.** `.claude/harness-gaps.md` records observations and nothing carries them back into planning; `/ce-compound` is that return path, and it is the mechanism half of what [ADR-0011](adr/0011-ecosystem-survey.md) already took from `task-observer`. Separately, `ce-handoff` is a second concrete shape for §7's open development-side hand-off row | **Measured 2026-08-18: ~2,354 tok always-on**, 33 skills. The per-skill split is worth knowing — `ce-brainstorm` alone is ~200 always-on and ~13.3k on invoke | ~2,354 |
| [`i-have-adhd`](https://github.com/ayghri/i-have-adhd) (MIT) | Ten output rules — lead with the action, cap lists at five, no preamble or recap | **Held — 2026-08-18. The cheapest thing measured in this table, and still not yet** | It competes with our own `CLAUDE.md` §6 at the same layer, and §6 was written from a real session review while this ships no evidence beyond a before/after example. §7's threshold is unmet: **zero occurrences here**. Two of its rules are genuinely absent from §6 and are the absorb candidates if a second occurrence ever arrives — *restate state every turn*, and *end with one concrete next step* | **Measured 2026-08-18: ~67 tok always-on** (1 skill; its `SessionStart` hook only reads a flag and costs no model context) | ~67 |
| [`claude-hud`](https://github.com/jarrodwatts/claude-hud) (MIT) | A statusline showing context usage, active tools and todo progress from **native token counts, not estimates** | **Do not ship, absorb the technique — 2026-08-18** | Genuinely free in context, and still not ours to install: a statusline is the consumer's own surface, so shipping it means writing `statusLine` into their `settings.json` and owning its removal (§6). Nothing stops anyone installing it personally. **The absorb pointer is the reading**: `context-budget` measures the *installed* maximum in CI and there is no view of what a session actually spends, which §2d names as the reason a developer machine cannot gate. This reads the transcript's native token data, and [`harness-log`](harness-log.md) could carry a per-session cost column the same way | **Measured 2026-08-18: ~0 tok always-on** — 0 skills, 0 hooks, statusline only. The one candidate whose "near zero" guess survived measurement | **0** |

**A third pass on 2026-08-18 measured four candidates and admitted none.** It came out of a star-ranked index rather than a curated list, and the index's own shape is the first finding: a quarter of its hundred entries are not plugins at all (`next.js`, `storybook`, `mlflow`), and four repositories appear twice under different owners with identical descriptions, so the canonical source cannot be told from the ranking. Nineteen entries already had rows here and about ten more fell onto rows that existed.

**Measurement reversed the pass's top-ranked candidate, which is now the third time that has happened.** `context-mode` was written up from its README as the compression row's first non-proxy candidate; its hooks put it on the capture row instead, beside `claude-mem` and `agentmemory`. The README-level read was not merely imprecise, it was answering a question nobody had asked — *does data leave the machine* — when the recorded objection was *is tool output stored at all*. **Two of the four verdicts turned on something no README stated**: this one, and `compound-engineering`, whose 33 skills cost more than twice the headroom the ceiling has left.

**A second pass on 2026-08-13 judged sixteen candidates across two batches and admitted one.** Most were new; the rest fell onto rows that already existed. The second batch (`agent-browser`, `find-skills`, `get-shit-done`, `taste`, `mcp-builder`) changed no rule — its verdicts reused the same-stage test, §6's second-installer objection, and the `skill-creator` lesson, and `taste` landed on the row `taste-skill` had made the same morning. What is worth recording is *where they landed*: `agentmemory`, `Understand-Anything` and `taste-skill` each fell onto **a row that already existed** (`claude-mem`, the graph row, `ui-ux-pro-max`), and the rest were turned away by tests already written down — the 9,000 ceiling and [ADR-0009](adr/0009-external-dependencies.md)'s same-stage overlap rule. The one admission, `claude-video`, is also the pass's one caught misreading: it was first refused under §1's non-goal, which forbids *building* working skills, not *depending on* them — the reading that admitted Superpowers. One more correction came out of the pass (`caveman`'s basis, above), and one finding that is not a candidate verdict at all is tracked in the ledger instead.

**The pass's method lesson: the verdict column and the Measured column answer different questions, and running the candidates settled things reasoning had got wrong.** The first write-up of this pass reported "nothing to add" with nine empty Measured cells — conflating *does this go into the harness* with *is this worth running*. Filling the cells the same day reversed or corrected three of its own judgements: `ECC`'s rejection had rested on a ~14k estimate and measurement said **~28,321** (right verdict, wrong size, by 2×); `taste-skill` was installed at user scope on a "near zero" guess and measured **~1,697** (wrong call, corrected the same day — uninstalled from user scope); and running `claude-video` at all is what surfaced the ffmpeg ≥ 8 defect **and** the demand conversation that flipped its verdict. Only `agentmemory` and `last30days` carry a reason not to try them casually — tool-I/O capture and browser-cookie extraction — and those belong in a throwaway repository if anywhere. **An empty Measured column is not a negative result**, which is what this table says at the top and what the pass that wrote these rows forgot.

**Verdicts come from the body, not the name.** All four verdicts made from names alone were wrong (ADR-0011). `skill-creator` was an instrument, not an authoring helper; `harness-100` was a collection of project templates, not of skills; `slide-deck` (ehr-research) looked orphaned but sat under another pipeline's front door. **The fourth was not even a name** — `headroom` and `ponytail` were written down as *"an inactive install under another project's scope"*, which is not a verdict but a description of this machine. Reading the bodies, one had measured our own §2 more rigorously than we had, and the other was a proxy.

**What those three rows say together.** Half our always-on context is norms telling the model to *write less* and *change narrowly* (`CLAUDE.md` §2 and §3, `workflow.md`), and we have never measured whether those norms change behaviour. `ponytail` measured the same claim with **the same agent ±skill, a real repository, and grading on the git diff** — the design `bench-convention` was reaching for, so the next measurement is one to copy rather than invent. Conversely `codebase-memory-mcp`'s 0.83 vs 0.92 means **a 10× token saving costs 10% of the quality**, a measured instance of what §4b already suspected: *accuracy can peak at intermediate cost*. Both push the question from "how cheap" to **"what does the cheapness cost"**.

## 4. The verification mandate

**A guard merged without verification is not a guard, it is decoration** ([ADR-0003](adr/0003-verification-mandate.md)).

**Supported platforms: macOS, Linux, and Windows under Git Bash.** `make verify` is expected to come out green on all three, and a check that fails only on one of them is a bug in the check until shown otherwise. This was written down after the first Windows run: **34 failing cases from four causes**, none of them previously observed.

| Cause | Where it showed | Cases |
|---|---|---|
| `jq` writes CRLF; `$(...)` strips the newline and keeps the CR | `gh-account-guard` (8), `harnessctl`'s manifest round trip (7) | 15 |
| `os.path.join` mixes separators, so string comparison misses | `verify-doc-refs` exemptions | 10 |
| Windows `make.exe` re-encodes recipe text through the ANSI codepage | `TRIGGER_LANGS` reaching the frontmatter check | 5 |
| `ln -s` exits 0 and leaves a copy | three hook verifiers | 4 |

**One of those 34 was not a test problem.** `gh-account-guard` let through a push it should have blocked: the login read from `gh` was compared as `chpark-ML<CR>` against `chpark-ML`. Note the shape — a trailing CR leaves *substring* matches working and breaks *exact* ones, so the guard did not misfire, it went silent. Three things follow, and they are the general lesson rather than Windows trivia.

- **A platform nobody runs is a platform where the guards are decoration.** The tempting reading is "1 real bug, 33 environment quirks". The honest one is 34 defects that no environment had ever asked about, and the only reason the guard failure was visible at all is that eight cases were already pinning it.
- **Prefer one code path to a platform branch.** The CR fix is an unconditional `tr -d` wrapper, because `tr` is a no-op on LF and a `case $(uname -s)` arm would be a line that only ever runs in one environment — the §4 rule two paragraphs down.
- **Write the reproduction so it runs everywhere.** `PYTHONIOENCODING=ascii` reproduces the encoding crash on Linux too, so that case lives in CI. A Windows-only case would have been invisible to the job that runs on every push, which is how the defect got in.

Line endings are part of this: [`.gitattributes`](../.gitattributes) pins `eol=lf`, because Git for Windows defaults to `core.autocrlf=true` and bash does not treat CR as whitespace — it lands inside the last token on the line, so `BOTH="a b"` assigns `a b<CR>` and a heredoc writes that CR into whatever it generates.

| Category | Verification |
|---|---|
| Hooks | `plugins/harness-core/scripts/verify-<name>.sh` — one per hook, 8 cases or more, carrying all three kinds: no-op, block, boundary. Two more are added by `verify_begin` to every hook that parses stdin, so a new hook cannot arrive without them: it normalises jq's line endings, and it resolves jq with `type -P` rather than `command -v` (which the CR wrapper turns into a guard that cannot fail) |
| Installer | `scripts/verify-install.sh` — harnessctl's init → reinstall → module swap → uninstall round trip, **and `install.sh` itself** (is there an executable line in the header; do `--help` and the argument rejections run without the Claude CLI; the jq bootstrap — right asset, checksum enforced, nothing left behind when it refuses, and jq on the PATH harnessctl inherits; and the jq guards themselves — what a user with no jq is actually told by `harnessctl`, `doctor` and `harness-log`, plus a globbed check that no file carrying the CR wrapper resolves jq with `command -v`), **and `uninstall.sh`** (the shims are written by one script and found by the other on a marker string held in both, so the fixture is generated with `install.sh` and swept with `uninstall.sh` — a renamed marker would otherwise leave every shim behind in silence; plus that `--dry-run` writes nothing, that a missing manifest is reported rather than fatal, and that a bootstrapped jq and an unmarked executable in the same directory both survive). User scope is checked against a scratch directory via `CLAUDE_CONFIG_DIR`, so the real `~/.claude` is never touched |
| Frontmatter | `scripts/verify-frontmatter.sh` — YAML parsing of every skill, agent, rule and command, plus a skill description's negative routing and the second-language triggers `.claude/trigger-langs` declares (this repository declares `한국어\|Korean`; the English triggers cannot be checked by machine and stay a human review item). Runs its own 7 cases first, none of them about frontmatter — they hold the reporting path, which once died on a console that could not encode an em-dash, and glob every python-embedding verifier for the same two defects. Needs only python3 |
| Output tools | `plugins/harness-core/scripts/verify-harness-log.sh` — 44 cases. The same three kinds as a hook, but centred on **must-not-appear**: if tool output, a subagent transcript, a skill injection or a compaction summary leaked onto the page, then in a repository running `secret-scrubber` whatever a command printed would survive in a file ([harness-log](harness-log.md)) |
| Document references | `scripts/verify-doc-refs.sh` — does the file a link points at exist, does `#anchor` resolve to a heading, and does the first segment of a path an instruction file calls exist. Runs its own 19 cases first (false positives being this checker's only failure mode) |
| Check total | `scripts/verify-check-total.sh` — do the three published totals (the README badge, the README table, §4 of this document) agree with each other **and with what the run actually produced**. `make verify-all` runs verify and then reads its output |
| Context budget | `scripts/context-budget.sh` — sums the always-on footprint **of what this harness ships** (declarative plus our plugins) per scope × profile and fails past `CONTEXT_CEILING`. Third-party plugins the user installs are deliberately outside the gate — a consumer's install must not turn our CI red — and are reported informationally by `harnessctl doctor`, whose composite section prices every enabled plugin with the same instrument as this table (added after two third-party installs pushed a real session past the ceiling while the gate printed green, 2026-08-13). The file list is a glob, so a new rule cannot become quietly free |
| Manifests | `claude plugin validate --strict` — its own CI job. Everything else runs without the CLI |
| Syntax | `make syntax` — parses every shipped script with `bash -n` |
| Conventions and skills | Human review plus [`harness-reviewer`](../.claude/agents/harness-reviewer.md)'s structural audit |

**Now**: 7 hook verifiers / 260 cases, session-log renderer 46, claim checker 50, block provenance checker 21, harnessctl round trip + install.sh and uninstall.sh 198 assertions, context-budget gate 14, inventory figures 39 + selftest 7, frontmatter 12 + selftest 7, plugin manifests 13, benchmark health 14, document references 64 files + 19 own cases, documented commands 45 + 12, context-budget ceiling 1 — a total of 822. That number is itself checked by `make verify-all` (`verify-check-total.sh`) — the total has to wrap `verify` and read its output, so it does not count itself. `make verify` runs everything, and CI executes it as three jobs: ubuntu (bash 5), macOS (`/bin/bash` 3.2), and manifests.

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
| `harness-frontend` + `ui-ux-pro-max` | ~0 + **~716** | `frontend` |
| **worst case** (project, every profile) | **~7,927 tok / session** — measured in CI, and ~7,211 without the opt-in `frontend` profile | ceiling 9,000, enforced in CI |
| Every profile at user scope | ~3,919 | no rules there |
| `skill-creator` (developer — orphaned 2026-08-13, no longer installed) | ~112 when installed | ~10.9k when called |

**This table has been wrong twice, and both times for the same reason — it was maintained by hand.**

- **The declarative half was missing entirely.** The first version counted skills only and put it at `~2.2k`. The `CLAUDE.md` and `rules/` that `harnessctl` installs load every session and appeared in no table. The real figure is **3.6× higher**, and `workflow.md` alone approaches the cost of all our skills combined. **We were judging "we can fit a bit more" on top of a fake baseline** — which is how bringing in 62 external harnesses (~560 tok each) briefly sounded survivable.
- **The plugin numbers were stale too.** The table said core 390 / dev 351 / slides 300; measurement says 329 / 240 / 446.

So instead of pinning numbers into a document, they moved into **a script that reads the source**, and `make verify` fails past the ceiling. The file list is a glob — a hardcoded list is the path by which a new rule file becomes quietly free.

**Hooks and LSPs are still zero** (`plugin details` classifies them as "harness-only — no model context cost"). What changed is that the conclusion *only skills cost anything* was wrong — **rules cost more than skills.** Our per-skill unit cost is high (Superpowers: 688 across 14, so ~49 each, against our ~240) because ours carry English and Korean triggers plus negative routing together, and whether that convention earns its cost is measured in §4b. We observed external skills attaching to Korean prompts **on an English description alone**, so this stays an open question.

**Adding is not addition, it is a trade.** There is ~1k of headroom under the ceiling, and it is there for the next one thing, not to be filled. To go past it, either say what comes out in the same change, or raise `CONTEXT_CEILING` in the Makefile with a reason.

**We also learned there is a second axis.** `skill-creator` is 112 always-on and 10.9k when called — a short description over a huge body. We have built the opposite way. Which is right is decided by call frequency: a frequently triggered skill needs a cheap body, and a rarely used tool needs a cheap description. Design on always-on cost alone and this axis is invisible.

**Repo-only verifiers owe no cases by default; how they fail decides.** Hooks are required to carry 8 cases or more, but there was no rule for `scripts/verify-*.sh`, so three of them were judged on the spot — `verify-frontmatter` (0 cases at the time, 4 today and every one of them about its *reporting* path rather than its checks), `verify-doc-refs` (19), `context-budget` (0). Lined up, the criterion was one thing: **if it fails by false positive, add cases** (a check that cries wolf gets switched off, and a switched-off check is zero); **if it fails by omission, prevent it in the design** — glob rather than hardcode, so a new file does not become quietly free. When true or false is self-evident, neither is needed. The rule is written into `CLAUDE.md` §4.

**And a line that runs in only one of the environments is an unverified line.** `verify-check-total` was written on a machine with the Claude CLI, and the branch that runs only without it executed for the first time in CI and broke in two ways — `grep -c`'s exit 1, and treating an unmeasurable total as a failure. The same disease as the fixture item below, except this time it was the *environment* that was singular.

**The third occurrence moved the axis from CI to the locale, and it landed on the reporting path.** `verify-frontmatter` and `verify-doc-refs` format their output with em-dashes, and Python's stdout carries the locale encoding with `errors='strict'`. On a cp949 console the frontmatter checker passed 11 / 11 and then raised `UnicodeEncodeError` printing the summary — a fully green run exiting 1, and on the doc-refs side the checker died precisely when it had failures to name. Two things came out of it worth keeping. **A verifier's output is part of the verifier**: its checks had been judged self-evident, which was true and irrelevant, because nothing had ever asked whether it could speak. And **a reproduction has to run where CI runs** — `PYTHONIOENCODING=ascii` triggers it on any platform, so the case sits in `make frontmatter` rather than in a Windows-only corner nobody executes. The structural half of that selftest globs `scripts/verify-*.sh`, which immediately caught a third script (`verify-benches`) that a hand-picked list would have missed.

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
| **Guards** (hooks) | Do they stop incidents? | raw 0/35 → harness **33/35**, false positives on ordinary work **2/30** | Deterministic. A count, so no error bars |
| **Conventions** (CLAUDE.md, rules) | Does written prose change behaviour? | branch naming raw 0/12 → harness **10/12** | **Significant** (*p* ≈ 0.00007) |
| **Skill routing** | Does work reach the skill we said it would? | **59/60** | Descriptive. The 6/6 negatives confirmed across three runs each |
| **Deck number traceability** | Does the filter have holes? | 41 flagged of 143 tokens in the frozen corpus, **0 new unclassified shapes** | Deterministic |
| **LSP** | Does it improve tokens or accuracy? | accuracy 3/3 against 3/3, tokens −6.3% | **Inconclusive** — this design can only resolve effects above 61% |
| **Installer** | Does uninstall restore the original? | 198 assertions | An invariant, not an A/B subject |

**Every agent-session measurement came from `model=opus` and `effort=high`** (change them with `BENCH_MODEL` and `BENCH_EFFORT`). The first version did not pass these through and inherited the caller's `settings.json`, and which configuration produced a number was recorded nowhere — no comparison with another machine's figures was possible, and a reader had no way to know. The benches now print it at the start.

**That effort can move the result is left open.** More reasoning may mean more convention-following without the harness, which raises the raw arm and shrinks the effect below what is reported here. It has not been measured at `effort=xhigh`.

Below is the basis for each row. **If you take one line: guards and conventions earn their place, the LSP is not yet known, and some of the conventions earn nothing at all.**

### Guards (`make bench`)

`evals/incidents.sh` is a 65-case corpus written **independently of the verifiers** (drawn from the §2 accident table and from things that actually happen, without looking at the regexes). By category: attribution 5/5, protected 6/6, ghaccount 6/6, secret 10/11, bigfile 6/7. **The 2 misses and the 2 false positives are exactly the four `docs/hooks/*.md` already records as limits** — an independent corpus rediscovering the documentation, which is also evidence that the limits are described accurately.

The raw arm being 0/0 is self-evident (no hooks, so nothing blocked and nothing blocking). The meaning is not in that contrast but in **the 7% price tag** — a guard that blocks 100% is switched off within a day, and its block rate is zero from then on.

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

> *Added 2026-08-17*: `cross-model-review` measured on the same instrument at 3 runs — **12/12**, pass@1 1.00, pass^3 1.00, spread 0.00. This is a separate measurement with its own date and its own room, not an edit to the 59/60 above. **The claim under test was sharper than for the other five**: this skill's input is *the same commit range* `superpowers:requesting-code-review` takes, so ADR-0009's dividing line has no lifecycle stage to cut on and the boundary had to be *who reviews* instead. The negatives reached the seats the description names — `requesting-code-review`, `pr-review`, `pr-create`, `receiving-code-review` — so a prompt that does not name another model does not arrive here.
>
> **It could not be measured the way the other five were.** The instrument reads the *installed* plugin and an unmerged skill is not in the cache, so it ran as a project skill in a scratch clone under `--cwd` — the method the Korean-trigger pilot below used, for the same reason. Run through the plugin untouched it would have printed six clean zeros: the shape of every instrument failure catalogued further down, and the reason `.claude/harness-gaps.md` now carries it as occurrence 1.
>
> **Two negatives wobbled, neither onto us.** Pre-merge commit-range review went to `requesting-code-review` twice and to `Bash` once, and "get me GPT's ideas for designing this feature, no code written yet" went to `Bash` all three times rather than to `brainstorming`. Our skill was silent in all 18 negative runs, so this is the delegate-does-not-accept consequence recorded in the paragraph above, not a defect in our routing.

> *Added 2026-08-18*: `results-deck` measured **paired, with and without `ui-ux-pro-max` in the room**, 3 runs each — the first time a routing number here has a control arm rather than a published baseline for comparison. It was run because the new dependency ships seven skills, two of which are called `slides` and `design`.
>
> | | with `ui-ux-pro-max` | without (control) |
> |---|---|---|
> | negatives silent in every run | **6/6** | **6/6** |
> | positives fired (18 trials) | **10** | **10** |
>
> **No seat was taken.** Not one miss in either arm routed to a `ui-ux-pro-max` skill: the two prompts that could plausibly have been captured — rendering a deck outline to HTML, and drawing a diagram for a deck — opened with `Bash` in all three runs of both arms, and `research-notes` held its own negative 3/3 throughout. The seven extra descriptions changed nothing measurable about where the work went.
>
> **The control is what makes that statement safe, and it also caught a second thing.** Both arms return 10 of 18 positives where the row above publishes 14 of 18. Since the drop reproduces with the dependency *absent*, it is not the dependency — the difference is the room the measurement was taken in: a fresh clone under `--cwd`, not the live tree the 14/18 was measured in. Had the treatment arm run alone, a four-case drop would have been sitting there looking exactly like interference. **This is the fourth time the rule "check the instrument can ring before believing a negative" has paid, and the first time it was paid forward rather than after the fact.**
>
> **What is now open is the baseline, not the profile.** Whether `results-deck`'s published 14/18 survives re-measurement in its original room is a separate question with its own cost, and it is not this change's to answer.

### Do the Korean triggers earn their cost? (pilot, 2026-08-08)

The Korean triggers in a skill description take a fifth of a typical skill description, and their value had never been measured. **Counted from the `한국어 트리거:` label through the period closing the last quoted phrase, the five clauses are 410 characters** (52 · 52 · 82 · 92 · 132) — an earlier figure of 565 is not reproducible under that rule or any obvious neighbour of it, so it is replaced here by the number and the boundary that produced it. Each description also ends with a Korean negative-routing sentence outside this count; those add 198 characters and have never been measured at all. A pilot ran on `results-deck` — **the single variable is the 133-character `한국어 트리거: '...'` clause**, with the English description, the negative-routing clause and the body byte-identical. `harness-slides` was disabled and both arms were project skills (§4b trap 3 — an installed skill cannot be measured through a stand-in).

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
- **The installer is not an A/B subject in principle.** "Uninstall restores the original" is an invariant, not a claim with a comparison group, and `scripts/verify-install.sh`'s 198 assertions pin it (particularly that `settings.json` is canonically identical after uninstall).

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
- ⏳ Measuring the Korean *negative-routing* sentences. ADR-0011's pilot varied the `한국어 트리거` clause only; the 198 characters of `… 이 스킬 말고 X 로.` that every description also carries were never an arm. Same instrument, one more arm — but it is a paid bench, so it waits for a reason to spend.
- ⏳ A trigger-space **load test**. Every routing number in §4b — the 59/60 included — was measured in a 19-skill room (our 5 plus Superpowers' 14), and a consumer's room is bigger. **`harness-frontend` makes this concrete**: installing it adds seven descriptions, two of which (`slides`, `design`) name seats we or the platform already hold. The 2026-08-13 partial run (2 of 5 sets with 25 third-party skills added: 11/12 and 11/12, both misses opening with `Bash`, all 12 negatives holding their named seats) saw no seat-stealing, but was stopped as wrongly framed — it measured one competitor, not load. The right instrument is synthetic distractor descriptions laid down at stepped densities (19 → 30 → 45), not a real third-party install. A paid bench, so it too waits for a reason to spend.
- ⏳ Release / changelog skill — a `dev` module candidate. Release conventions differ too much per project for a common core to be visible yet.
- ⏳ A post-hoc output scrubber — blocking a command with PreToolUse and catching sensitive strings in *output* with PostToolUse are different accidents. The mirror-pair pattern itself is proven (the reference harness's PHI pair), but a general-purpose harness has no payload to use. If site-specific patterns are needed, it goes in a consumer-owned config file like `protected-paths`.
- ⏳ **Model and effort orchestration.** The harness currently ships no sub-agents to consumers, so this lever does not exist. Plugin agent frontmatter supports `model` and `effort` (`hooks`, `mcpServers` and `permissionMode` are refused for security), so keeping the main loop on Opus high while pushing mechanical delegation down to a cheaper tier is possible. This session is the evidence — 12 subagents were launched and all inherited the session model, and half of them (path substitution, counting, updating documents) did not need Opus. But *which work goes to which tier* takes judgement, and getting it wrong costs more when the expensive model redoes what the cheap one missed. Candidate axis: exploration, counting and mechanical edits low; design, adversarial review and root cause high.
- ⏳ Anchoring the `hooks.json` matcher. Today `Read|Write|...|Bash` has no anchors. If Claude Code treats a matcher as a regex, `Bash` also matches `BashOutput` and four guards spin uselessly on every call (each reading stdin, calling jq, exiting 0). Wrapping in `^(...)$` would remove that for free, but **we could not confirm how matching works** — if it is string comparison rather than regex, the anchors break matching instead. Both reference harnesses run without anchors, so we followed the convention. When it is confirmed, change it.
- ⏳ **Submit `harness-core` to the community marketplace.** Nothing outside this repository can find the harness today. **The target is `claude-community`, not `claude-plugins-official`** — the two are different, and only the first takes submissions: Anthropic curates the official one at its discretion, states there is no application process, and says explicitly that the submission form does not add anything to it. Approved plugins are pinned to a commit SHA in [`anthropics/claude-plugins-community`](https://github.com/anthropics/claude-plugins-community), CI advances the pin as commits land, and the public catalogue syncs nightly, so approval and installability are separated by up to a day. The gate is `claude plugin validate <dir>`, which the review pipeline re-runs alongside automated safety screening — ours passes today, `--strict` included, and CI already runs it. Two submission routes exist and the difference matters: the claude.ai form needs a Team or Enterprise organisation with directory-management access, the Console form does not. **What is undecided is which plugin to submit**, since the value here is the composite and the form takes one: `harness-core` carries the guards and the installer and is the only one that stands alone.
- ⏳ `harnessctl --scope local` (targeting `settings.local.json`) — the place for permissions you will not commit. No real demand yet.
- ✅ ~~More language profiles for game and app work~~ — added 2026-08-18. `harness-csharp` (Unity, .NET), `harness-cpp` (Unreal, native), `harness-lua` (Roblox, love2d), `harness-swift` (iOS, macOS) and `harness-kotlin` (Android), one manifest each over the official LSP plugins. Answers §2's *game and app code gets no symbol layer* row. **The list this row used to name was wrong** — `go`, `rust` and `java`, none of them asked for, while the languages behind a stated goal went unlisted. Those three are still available the same way, on the same terms: when actually used.
- ⏳ **Flutter has no route yet, and it is the one gap in the row above.** Dart has no plugin on the official marketplace, so unlike the other five there is nothing to depend on. A profile would have to ship its own `.lsp.json` naming `dart language-server`, which is supported but is a different shape from every language profile so far — and it could not be verified on the machine that would have written it, since neither `dart` nor `flutter` was installed. React Native needs nothing new: `harness-typescript` already covers it.
- ⏳ **`harness-paper`** — the publication half of research. `harness-research` stops at *what is established now* (`FINDINGS.md`) and *which run produced it* (`ARTIFACTS.md`), and nothing crosses from there into a manuscript. Answers §2's *an established result has no path to a manuscript* row. **Copy `results-deck` rather than invent**: it already performs this transform for a talk, and its traceability check (`check-claims.sh`) is the part a manuscript needs most. Unlike every other profile so far there is nothing external to compose from — the official marketplace carries no paper, LaTeX or citation plugin — so this one is built, not depended on. [ADR-0001](adr/0001-harness-scope.md) named a LaTeX build as excluded and was corrected on 2026-08-18; the exclusion governs `core`, not profiles.
- ✅ ~~A `harness-frontend` profile~~ — opened 2026-08-18 on `ui-ux-pro-max` (§3b). What moved was not the candidate list but **the owner stating a need**, which is the basis §2's site-dependent rows and `claude-video` already run on. `taste-skill` remains the other candidate and is not installed; if the profile ever needs a second asset, survey that family rather than the one name. **The one risk it carried was measured before merge and did not materialise**: the dependency ships a skill called `slides` and one called `design`, and a paired run with and without it returned the same 6/6 negatives and the same 10/18 positives (§4b). The row below still stands — one competitor is not a load test.
- ⏳ Session hand-off on the development side — the `handoff` family exists and the research side is already covered by the five-document set. `mattpocock/skills` (§3b) adds two concrete shapes for the seat: a `handoff` that compacts the conversation for another agent, and `to-tickets` / `wayfinder`, which plan multi-session work as a ticket map with blocking edges. Neither is a reason to install that suite — it competes with Superpowers at the same stage — but they are the design to copy if this row ever moves. When real demand appears twice on the development side.
- ⏳ An agent-layer security scan — ECC's **AgentShield** names a guard-lane seat we have empty: scanning the agent configuration itself (hooks, skills, permissions) rather than the code it guards. Its body has not been read; read it before any verdict. Zero occurrences here.
- ⏳ A skill *quality* audit. [`harness-reviewer`](../.claude/agents/harness-reviewer.md) audits structure — is the bundle complete — and nothing audits whether a skill body is any good. ECC's `skill-stocktake` (a checklist plus holistic judgement over changed skills) is the design to read when demand appears twice.
- ⏳ Content-level exclusion for [`harness-log`](harness-log.md) — agentmemory's `<private>` tag excludes at content granularity where ours drops whole categories. A different axis, zero demand so far.
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
- A jq-free path in `install.sh`. Hooks require jq, so an install without it delivers nothing but self-disabled guards, and an honest failure is better ([ADR-0002](adr/0002-hook-contract.md)). This still holds, and the jq bootstrap is not a softening of it — the installer now *supplies* the dependency rather than proceeding without it, and still stops when it cannot (no build for the platform, no curl, no hasher, checksum mismatch).
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
│   ├── harness-frontend/       # deps: core, ui-ux-pro-max — one manifest, no files
│   ├── harness-python/         # deps: core, pyright-lsp
│   ├── harness-typescript/     # deps: core, typescript-lsp
│   └── harness-{csharp,cpp,lua,swift,kotlin}/   # deps: core + one official LSP each
├── install.sh                          # thin bootstrap
├── uninstall.sh                        # its counterpart — both halves, plus shims
├── scripts/verify-{install,frontmatter}.sh
├── Makefile · CLAUDE.md · .claude/     # developing this repository itself
├── AGENTS.md                           # the same conventions, summarised for other agents
├── .github/workflows/verify.yml        # ubuntu · macOS bash 3.2 · plugin manifests
└── docs/ (agent-layer.md · engineering-axes.md · harness-log.md · adr/0001..0013 · hooks/*.md · superpowers/{specs,plans}/ — dated design records)
```

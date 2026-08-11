# Engineering layers — context, loop, graph, and where the harness stands

Building an agent system is not one problem. The distinction the field is converging on is **layers**, and layers compose rather than replace each other.

| Layer | What it controls |
|---|---|
| prompt engineering | A single model response |
| **context engineering** | **What the model sees** |
| **loop engineering** | **One agent's behavioural cycle** |
| **graph engineering** | **The topology across heterogeneous nodes** — who exists, which transitions are allowed, and how the runtime task graph forms and mutates |

Source: [TrueFoundry, *Graph Engineering: An Enterprise Guide*](https://www.truefoundry.com/blog/graph-engineering-enterprise-guide). A line from that piece stands in for this document's thesis — **"a bad graph with good loops is an org chart of unreliable employees, and unrefined loops inside a well-designed graph collapse at scale."**

**This is a design note. It is not shipped to consumers, so its always-on context cost is zero.** The source of truth for scope, inventory and backlog is [`agent-layer.md`](agent-layer.md), and the ecosystem verdicts are its §3b. This document covers only *which levers exist where, how others do it, and where we stand*.

---

## One-page summary

| Layer | Where we are | Measured |
|---|---|---|
| **harness** (governance) | **The body of the work** — 6 guards, 3 permission tiers, conventions, a budget ceiling | ✅ guards 27/29, branch convention 10/12 |
| **loop** | No rules. Not even the platform's own (`/goal`, `maxTurns`) | ⚠️ one claim measured, and it came back **0** |
| **graph** (topology) | **Zero consumer agents.** None of the four execution modes in use | ❌ |
| **context — code comprehension** | Two LSPs. No knowledge-graph asset | ❌ (the LSP is inconclusive) |

**"Not measured" is not "no effect."** Three of the four cells are empty, and that is the honest current state.

---

## 1. Harness engineering — the governance layer

### Definition

Making things the agent **cannot** do, and fixing the things it has **agreed** to do. The layer taxonomy above has no name for it, but the **four governance concerns** TrueFoundry lists as necessary for the graph layer are exactly this seat — identity, access policy, budgets and rate limits, guardrails.

**We already have three of the four, and built the fourth recently.**

| TrueFoundry's governance | Ours |
|---|---|
| access policy — per-tool restriction | `permissions`, 3 tiers (allow 47 / ask 3 / deny 8) |
| guardrails — pre/post tool-invoke hooks | 5 blocking PreToolUse hooks + 2 informational Stop hooks |
| budgets | `make context-budget` — an always-on context ceiling of 9,000 |
| identity — a per-node identity | **Missing.** We are a single-session harness, so there are no nodes yet |

### Where it is configured

`hooks/*.sh` + `hooks.json` (guard), `settings.json permissions` (guard), `CLAUDE.md` (guide, global), `.claude/rules/**` (guide, **project scope only**), `harnessctl` (installs reversibly).

Guards and guides cannot substitute for each other — a guide can be ignored, and a guard cannot encode every case in advance.

### Measured

| What | Result |
|---|---|
| Do the guards stop incidents | **27 / 29**, false positives on ordinary work **2 / 24** |
| Does written prose change behaviour (branch names) | 0/12 → **10/12**, *p* ≈ 0.00007 |
| Commit subject ≤ 70 characters | 6/6 against 6/6 — **zero. Removed from the rules** |
| Does uninstall restore the original | 112 assertions, canonically identical |

**This is the only layer properly measured.** And one of the things measured came back zero, so it was deleted.

---

## 2. Loop engineering — one agent's cycle

### Definition

**When to stop and when to go round again.** The verify in observe → reason → act → **verify**, and the feedback from it.

### What the platform already gives — and we are not using

| What | When the next turn starts | When it stops |
|---|---|---|
| **`/goal`** | When the previous turn ends | **A small model judges whether the condition is met** |
| `/loop` | After a time interval | The user stops it, or the model decides it is finished |
| Stop hook | When the previous turn ends | A user script or prompt decides |

`/goal` is **a wrapper around a session-scoped, prompt-based Stop hook.** After every turn it sends the condition and the conversation to a small fast model and gets back yes/no with a reason. The condition can run to 4,000 characters, and a turn clause like `or stop after 20 turns` sets a ceiling. The evaluator **calls no tools, so it judges only what is visible in the conversation** — which means the condition has to be something the agent's own output can prove, such as *"`npm test` exits 0"*.

An agent's frontmatter **`maxTurns`** is the only **hard** ceiling at this layer.

### Prior art — Superpowers is already thick here

| Skill | Lines | What |
|---|---|---|
| `test-driven-development` | 320 | The failing test first |
| `systematic-debugging` | 283 | The cause before the fix |
| `verification-before-completion` | 120 | Evidence before declaring done |
| `executing-plans` | 64 | Review at each checkpoint |

787 lines in total. **There is no seat for us on top of that.**

### Where we stand

**Nothing.** `CLAUDE.md` §4 says *"Define success criteria. Loop until verified"* but gives no stopping condition, and we use neither `/goal` nor `maxTurns`.

A draft R6 (three scales — turn, session, experiment; 525 tok) was written and **withdrawn**.

### Measured

| What | raw | harness | Verdict |
|---|---|---|---|
| Did it run the verification command itself | **3 / 3** | **3 / 3** | **No discriminating power** |

Given a task whose first attempt necessarily fails, and without the verification command being mentioned, both arms ran it. **Running the verification is what the model does anyway, not something the rule buys.**

**And the survey strengthens that conclusion** — `/goal` already provides "repeat turns until a condition is met, judged by a separate model" as a platform feature. Much of what we were about to write in prose already exists as machinery. **Before writing more prose, check whether the machinery is being used.**

---

## 3. Graph engineering — topology

### Definition

**The structure of the system itself.** Which nodes exist (agent loops, deterministic functions, routers, joins, **human checkpoints**, tool calls), which transitions are allowed, and how the runtime task graph forms and mutates. Edges are **communication and delegation**, and the topology itself is treated as a *programmable, version-controlled artifact*.

**This is a different thing from a knowledge graph, which structures data** (that is §4).

### A second use of the same name

[Eigent](https://www.eigent.ai/blog/graph-engineering-ai-agents) uses the same word for **"the craft of weaving feedback loops into a network that watches, constrains and corrects itself"** (spreading since mid-July 2026). It names four ways a single loop breaks at scale — Goodhart's law, an inability to doubt its own objective, conflict between loops, and the measurement itself going stale. The prescriptions are **paired and opposing metrics, baselines owned by a higher loop, separated cadences, frozen nodes** (held-out test sets, safety constraints), and **anchors** (external fixed references).

**The two uses do not fight.** One is *who hands work to whom* (topology), the other is *which loop watches which loop* (control). The second is closer to us — we have a bench (a measurement loop), hooks (a guard loop) and a ledger (an improvement loop), and **none of the three watches the others.**

### Where it is configured — Claude Code offers four

| Mode | What it gives | When |
|---|---|---|
| **Subagents** | Delegated workers inside one session. They work in their own context and return only a summary | When side work would fill the main conversation with search results and logs |
| **Agent view** | Dispatch and watch background sessions on one screen (research preview) | When several independent tasks are handed off and you intervene only as needed |
| **Agent teams** | A shared task list plus inter-agent messaging, managed by a lead (experimental, off by default) | When you want Claude to split, assign and synchronise as well |
| **Dynamic workflows** | A script runs many subagents and cross-checks the results | Work too large to coordinate in one turn, or needing verification from several angles |

Supporting: **worktrees** (file-conflict isolation), **cross-session messaging**, and `/batch` (a large change across 5–30 worktree-isolated subagents).

An agent's frontmatter sets the node properties of the topology — `model` (`haiku`, `sonnet`, `opus`, `fable`, `inherit`), `effort` (`low`–`max`), `maxTurns`, `tools`/`disallowedTools`, `skills`, `memory`, `background`, `isolation` (`worktree`). **`hooks`, `mcpServers` and `permissionMode` are refused in plugin agents for security.**

### Prior art — topology patterns and tiering

Five topologies recur across the field: **fan-out, pipeline, debate, supervisor, swarm**. And the cost pattern is **model tiering** — split requests into complexity tiers, run each on the cheapest model that suits, and keep the higher model for the orchestrator. Reported savings are **40–60%** ([Requesty](https://www.requesty.ai/blog/multi-agent-orchestration-patterns-that-work-in-production), [Beam](https://beam.ai/agentic-insights/multi-agent-orchestration-patterns-production), [MindStudio](https://www.mindstudio.ai/blog/ai-model-orchestration-smart-model-cheaper-sub-agents)).

**We do not take those numbers at face value.** Our discipline is *an A/B whose samples are agent sessions does not claim an effect below 20%*, and a 40–60% claim leaves out **the rework rate** — when the expensive model redoes what the cheap one missed, total cost goes up.

`harness-100` is an example of topology written as prose — a dependency DAG, parallel markers, `_workspace/NN_role.md` hand-offs. But **its frontmatter carries neither `model` nor `effort`, so nothing is enforced.**

### Where we stand

**We ship no sub-agents to consumers at all.** None of the four execution modes is in use. There is one agent, `harness-reviewer`, and it is for this repository.

**Agents are not free** — their description is always loaded, exactly as a skill's is. What you save by dropping a tier comes back as always-on cost.

### Measured

**Not measured.** There is one observation — a single session launched 12 subagents, and half of them (path substitution, counting) did not need the top model. **That is an observation, not a measurement.**

Measuring it means watching **accuracy, tokens and rework rate** together. Watch only the first two and you make the same mistake as the industry numbers.

---

## 4. The context layer — how the codebase is understood

Kept separate because it is easily confused with the graph layer. **This is a data structure, not a topology.**

### This category is getting crowded fast

`CodeGraph` reached 47.4k stars five months after release; `GitNexus` went 1.2k → 42k between April and June. Four more open-source projects doing the same thing appeared in the space of a few weeks ([Enterprise DNA](https://enterprisedna.co/resources/ai-pulse/ai-pulse-2026-07-23-codebase-knowledge-graph-for-ai-agents-is-now-a-crowded-fast/)).

**One pattern has converged**: precompute the structure **locally** and serve it **over MCP** — no cloud, no embedding API, no code leaving the machine. `CodeGraph` parses 20+ languages with tree-sitter into a SQLite graph of symbol relations, call graphs and dependency edges, and reports **47% fewer tokens and 58% fewer tool calls** across 7 real repositories ([ToKnow.ai](https://toknow.ai/posts/codegraph-knowledge-graph-ai-coding-agents-fewer-tokens/), [Ry Walker's comparison](https://rywalker.com/research/code-intelligence-tools)). On the academic side there is [CodexGraph](https://arxiv.org/pdf/2408.03910), connecting a code graph database to an LLM.

`graphify` (an ehr-research project skill, 702 lines) is the same family but not limited to code — it ingests documents, papers and images, keeps an audit trail marking provenance as `EXTRACTED` / `INFERRED` / `AMBIGUOUS`, and carries the rule *"when you do not know, use AMBIGUOUS and never invent an edge"*.

### An LSP is a different answer to the same question

|  | LSP | Knowledge graph |
|---|---|---|
| Unit | A symbol | A corpus |
| Timing | Immediate | Asynchronous (precomputed) |
| Always-on cost | **0** | Index maintenance and rebuilds |
| Good at | "Where is this function defined" | "Where is this decision scattered across documents and code" |

**They are not competitors. Measure both with the same ruler and both numbers are meaningless.**

### Where we stand, and what is measured

The only assets are two LSPs, and those are the symbol layer. **A knowledge graph has not even been attempted.** The LSP was measured and is **inconclusive** — tokens −6.3%, against a minimum detectable effect of 61% for that design.

**That others report 47% while we cannot resolve 6.3% means our ruler is short, not that there is no effect.** Measuring it means first deciding *which question types the answers diverge on*.

---

## Why separate the layers

| Symptom | Which layer |
|---|---|
| A secret went onto the command line | harness — guardrail |
| Fixing the same failure for the third time | loop — stopping conditions (`/goal`, `maxTurns`) |
| The top model was used for counting | graph — node properties (`model`, `effort`) |
| No idea what this change touches | context — code comprehension |
| The bench is green but things actually got worse | graph — loops not watching each other (Eigent's Goodhart) |

**Mix them up and you fix the wrong place.** Block a loop that will not stop with a guard and you block ordinary work; solve a comprehension gap with topology and you just launch more cheap models.

## How the next thing is chosen

1. **Which layer is it** — with no layer decided, what to measure is not decided either.
2. **Is it already in the platform** — `/goal`, `maxTurns`, subagents, workflows. **Check the machinery before writing prose.** R6 is the case where that check was skipped.
3. **Is it a hard lever** — `maxTurns`, `model` and `permissions` are enforced; a rule is not.
4. **Does a way to measure it exist** — a claim that cannot be measured does not go in as a rule. And **a cost-saving claim without a rework rate is not a cost-saving claim.**
5. **What is the always-on cost** — `make context-budget`. Hooks and LSPs are zero; skills, agents and rules are not.

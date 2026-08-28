---
name: ecosystem-review
description: "Use when something outside this repository is being judged for it — an external repo, plugin, skill, marketplace entry or npm tool that someone asks you to review, evaluate, or consider adopting. Settles which of two questions is being answered, reads the body rather than the README, runs the cheap measurements that actually reverse verdicts, and produces a row for the ecosystem table. 한국어 트리거: '이 레포 검토해줘', '이거 우리 하네스에 쓸만해?', '이 플러그인 어때', '흡수할 거 있나', '이거 도입할까', '외부 도구 훑어줘'. 이미 열린 PR 은 이 스킬 말고 pr-review, 우리 저장소의 현재 diff 나 커밋 범위는 code-review 와 superpowers 의 requesting-code-review, 다른 모델에게 같은 변경을 교차 검토받는 것은 cross-model-review 로."
---

# ecosystem-review

Judges an outside candidate and writes the verdict where the next person will find it. The procedure lived in [ADR-0011](../../../../docs/adr/0011-ecosystem-survey.md) and in one person's memory for three sessions before becoming this file; that is why it exists.

## Step 0 — Which question is being asked

**Two, and they are not the same.** Answering one silently is how the reader gets the wrong answer.

| | The question | What the answer looks like |
|---|---|---|
| ① | **What does it ship?** | A row in `docs/agent-layer.md` §3b — adopt, depend, absorb, or refuse |
| ② | **What was it for?** | The candidate's *intent*, held against our own assets. Do we have a seat for that intent, and does the thing sitting in it use the whole seat? |

Ask which, or answer both and label each. ① and ② diverge routinely: a candidate can be correctly refused as an artefact while its intent names a gap we half-closed and forgot. `docs/agent-layer.md:148` records the same shape one pair over — a pass that conflated *does this go into the harness* with *is this worth running*, and reported "nothing to add" with nine empty measurement cells.

## Step 1 — The body decides, not the README

[ADR-0009](../../../../docs/adr/0009-external-dependencies.md) turned this into a rule after it was got wrong three times: **conflicts with an external skill are judged by the body, not the name.** A README describes intent; the tree describes the product.

- Clone it and read the tree. Count what actually ships — one candidate advertised "a single unified skill" and installed seven, two of which sat on seats we already held.
- Check the licence file exists, not just the badge.
- For anything with skills: is the file `SKILL.md`? Lowercase `skill.md` loads on a case-insensitive macOS filesystem and silently does not on Linux or in a container.

## Step 2 — The cheap measurements, before the verdict

**This is the pillar that earns the most and is easiest to skip.** In one pass, running the candidates reversed or corrected three judgements that reasoning had settled: a rejection resting on a ~14k estimate measured **~28,321** (right verdict, wrong size by 2×), a "near zero" guess measured **~1,697** and reversed the call the same day, and a defect plus the demand conversation that flipped a verdict surfaced only because the thing was actually run.

None of these costs a model session:

```bash
claude plugin validate <dir> --strict          # the marketplace's own gate
D=$(mktemp -d)
CLAUDE_CONFIG_DIR=$D claude plugin install <name>   # a scratch config, not yours
CLAUDE_CONFIG_DIR=$D claude plugin details <name>   # always-on tok
```

**Two traps in those three lines, both met in practice.** `validate --strict` passes on a bare repository with a `skills/` directory and no plugin manifest at all, so a green validation is not evidence the thing is installable as a plugin — check for `.claude-plugin/plugin.json` yourself. And `details` prices **only what is installed**, which is why the scratch config is not optional; asked about something absent it suggests `--plugin-dir <path>`, an option `details` does not accept.

Plus: parse every frontmatter block (an unquoted scalar containing a colon-space loads the description **blank** — no triggers, no routing, and nothing says so), and run whatever tests it has.

**An empty measurement cell is not a negative result.** It means nobody looked. Say which it is.

## Step 3 — The verdict

Six columns, and the table in §3b is where they go — scattered, the same candidate gets judged twice.

`Subject · What · Verdict · Basis · Measured · Always-on cost`

Three tests do most of the work:

- **Same lifecycle stage?** [ADR-0009](../../../../docs/adr/0009-external-dependencies.md)'s dividing line has nothing to divide when the overlap sits at the same stage as something we already depend on. That is a refusal, however good the candidate is.
- **Does it bring a second installer?** A tool that writes its own files into the consumer tree collides with the ownership model in §6.
- **Does it fit under the ceiling?** 9,000 tok always-on, and the headroom is usually small. Measure, do not estimate — see Step 2.

**Popularity is not measurement.** A star count answers no column in that table.

## What this skill does not do

- Install a candidate to find out. Reading the body is cheaper, and two of the nine in the first survey made changes that are hard to undo.
- Fill the Measured column with someone else's published number without attributing it in the cell.
- Decide ② on the owner's behalf. Whether a stated need exists is theirs; §7's two-occurrence gate is what this skill applies to everything else.

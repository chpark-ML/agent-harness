# ADR-0013: A repository tag versions the snapshot, independently of the plugin versions

- **Status**: Accepted
- **Date**: 2026-08-08
- **Related**: [ADR-0005](0005-installer.md) (the installer) · [ADR-0008](0008-plugin-declarative-split.md) (the plugin/declarative split) · [`README`](../../README.md) · [`SECURITY.md`](../../SECURITY.md)

## Context

`install.sh --ref <ref>` pins the marketplace to a revision. That handle **exists and works, and there is nothing to grab** — this repository has never published a tag (`git tag` and `git ls-remote --tags` both empty). So the README and `SECURITY.md` each say *"no release tags are published yet"* in three places and recommend a commit SHA instead.

**We told consumers `main` moves, and handed them no handle to stop it.** It does move — there was a day with more than ten PRs.

The reason for not tagging was not laziness but one unanswered question: **six plugins carry their own versions, so what is a repository tag the version of?**

| Plugin | Version |
|---|---|
| `harness-core` | 1.9.3 |
| `harness-slides` | 1.4.1 |
| `harness-dev` | 1.0.4 |
| `harness-research` | 1.0.2 |
| `harness-python`, `harness-typescript` | 1.0.0 |

> *After 2026-08-11*: several of these have moved (`harness-core` most of all). The table shows the state **at the time of the decision**; the manifests under `plugins/*/.claude-plugin/plugin.json` are the source of truth — the figures here are a record of that moment.

When `harness-core` reaches 2.0 and `harness-python` is still at 1.0.0, what should the repository tag's major be? Tag anything without answering that and **the question freezes unanswered** — so it was deferred, and recorded in the ledger as occurrence 1.

## Decision

**A repository tag versions the snapshot.** It is not any plugin's version, and it does not try to summarise them.

`v<major>.<minor>.<patch>`, **starting at `v0.1.0`.**

What is versioned is **everything a consumer receives at that revision** — `install.sh`, `harnessctl`, the `declarative/` payload, and the six plugin versions at that commit. Because `--ref` pins the marketplace, the plugin versions are pinned **transitively**. That is what pinning means.

The bump rule keys off **the declarative contract**, because that is the only single surface.

| What changed | Bump |
|---|---|
| An existing install must **re-run `harnessctl init`** to be correct — the shape of the settings fragment, rule paths, the `CLAUDE.md` marker convention, what uninstall reverses | major |
| Consumers **receive more** — a new hook, skill, rule or profile, a new permission entry | minor |
| Everything else — bug fixes, documents, verifiers, repo-only scripts | patch |

**Why 0.x.** Much of what the harness asserts is still unmeasured (whether `CLAUDE.md` §2 and §3 change behaviour, the entire graph axis). 1.0 is a promise that *this contract will not break*, and that promise cannot be staked on something unmeasured.

## Consequences

- The three *"no release tags are published yet"* notes in the README and `SECURITY.md` go away. The `--ref` examples use a tag instead of a commit SHA.
- **The per-plugin version-bump obligation is unchanged** ([`CLAUDE.md`](../../CLAUDE.md) §2). A repository tag does not stand in for it — Claude Code decides its cache on the plugin version string, so bumping only the tag delivers nothing to a consumer. **The two layers turn independently.**
- Tagging is not automated. A release is a judgement, and moving a judgement into CI is how the major/minor distinction above quietly collapses into patch. [§7](../../CLAUDE.md)'s resistance to over-design points the same way — a release pipeline after the second occurrence.

## Alternatives considered

- **Date tags (`2026-08-08`).** Honest, in that it does not have to summarise six versions — but it cannot answer *"will this upgrade break my install"*, which is the only reason to use `--ref` at all.
- **Follow the highest plugin version (`v1.9.3`).** Makes `harness-core`'s version pretend to be the whole repository's. The other five quietly become false.
- **No tags, keep SHAs.** The current state. It makes `--ref` apologise three times across the documentation, and leaves a consumer with no way to know which revision is stable.

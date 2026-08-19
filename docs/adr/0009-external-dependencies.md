# ADR-0009: External plugins come in as profile dependencies, and a skill conflict is settled by picking one

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

When [ADR-0008](0008-plugin-declarative-split.md) turned profiles into plugins, `dependencies` opened up. Somebody else's maintained asset can be brought in with one manifest line — the shape is `{name, version, marketplace}`, and `version` takes a semver range. Pointing at another marketplace requires that marketplace's `marketplace.json` to carry `allowCrossMarketplaceDependenciesOn`, and ours lists `claude-plugins-official`.

Two things confirmed on the official marketplace:

- **Superpowers** (source `obra/superpowers`, pinned to a SHA) — 14 skills: `brainstorming`, `dispatching-parallel-agents`, `executing-plans`, `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `using-superpowers`, `verification-before-completion`, `writing-plans`, `writing-skills`.
- **14 language-server plugins** — `pyright-lsp`, `typescript-lsp` and others. **The LSP plugins do not bundle a server binary.**

A rule catches here. [ADR-0001](0001-harness-scope.md)'s admission test is "would this still make sense installed as-is on a project in another domain, on another stack?". Applied literally, pyright only makes sense on a Python project, so it cannot come in.

The cost structure differs by asset, too. **A skill costs you even unused** — its description is always loaded for routing, so 14 skills you do not use is 14 servings of context. **An LSP does not.** A language server runs when a tool calls it, and loads no standing text.

## Decision

**1. Superpowers is adopted as a dependency of `harness-dev`.** `dev` rather than `core` because of that cost structure — there is no case for loading the descriptions of `test-driven-development` and `requesting-code-review` on every turn for a user who only runs the research profile.

**2. When skills overlap, pick one. Do not ship both.** Two skills fighting over one trigger is exactly the failure our negative-routing discipline exists to prevent — routing becomes non-deterministic, and which one won is invisible to the user. Overlap is treated as a defect, not as "both are available, how rich".

The overlaps we observed fall into four kinds.

| Kind | Superpowers | Ours | Verdict |
|---|---|---|---|
| Direct conflict | `finishing-a-development-branch` | `pr-create` | **Use ours** |
| Direct conflict | `requesting-code-review`, `receiving-code-review` | `pr-review` | **Use ours** |
| Principle overlap | `test-driven-development`, `verification-before-completion` | `CLAUDE.md` §4 Goal-Driven Execution | Coexist. The principle is a standing instruction, the skill is its procedural form |
| Clears a backlog item | `using-git-worktrees` | (none — backlog ⏳) | Adopt. We no longer need to build one |
| Pure addition | the other 8 | — | Take as they are |

Ours wins the two direct conflicts on **coupling**, not on quality. `pr-create` executes R1–R4 from `rules/harness/workflow.md`; `pr-review` executes the checklist in `rules/harness/dev/review.md`. A general-purpose skill does not know those files exist. The choice is enforced instead by **negative routing that names the superpowers skill** in our descriptions — a dependency's skills are not ours to delete, so our description is the only way to make routing deterministic.

**3. Create the language profiles `harness-python` and `harness-typescript`.** Each is one manifest with `harness-core` plus one official LSP as dependencies, and no files. Another language is added the same way with `gopls-lsp`, `rust-analyzer-lsp` and so on. The server binary is the user's to install, and `harnessctl doctor` checks PATH and prints the install command.

**4. ADR-0001's project-agnostic test governs `core`, not the opt-in profiles.** That is what holds point 3 up. Extend the test to profiles and neither `research` nor `dev` could exist, which makes the whole module structure pointless — modules exist precisely to hold what does not suit everybody. Read the rule this way: **`core` must make sense installed on any project; a profile only has to make sense to the person who chose it.**

Worth recording honestly: the first draft of this plan excluded pyright as "language-specific, violates ADR-0001". That mixed up two rules. By the same logic the research-note discipline would have had to go, and it did not — so the test was not being applied consistently either.

**5. The `ml` and `review` profiles are held.** Zero occurrences. Below the "a problem that actually happened twice" bar `CLAUDE.md` §7 sets, so they sit in the `docs/agent-layer.md` backlog.

### Update (2026-08-06, measured after installing Superpowers)

**The "two conflicts" were not conflicts.** The pre-install verdict came from reading skill names; reading the bodies put them at different points in the lifecycle.

| Superpowers | What it does | Ours | What it does |
|---|---|---|---|
| `requesting-code-review` | **Pre-merge self-review**, sending the `BASE_SHA..HEAD_SHA` commit range to a subagent. Never touches the forge | `pr-review` | Reads an **already-open PR** with `gh pr diff` and walks this repository's checklist |
| `finishing-a-development-branch` | Choosing an integration route and cleaning up. Option 2 pushes and creates a PR, and its body says *"following the repo's PR template and conventions if present"* | `pr-create` | Those repo conventions themselves — slug format, `[<slug>] title`, the body sections, no AI attribution |
| `receiving-code-review` | How to respond to a review you received | — | Nothing |

Different inputs, different outputs. `finishing-a-development-branch` is in fact **written to delegate to ours**.

> *Measured 2026-08-07*: that dividing line turns out to be more than a declaration. `pr-review` 12/12, `pr-create` 12/12, and the negative cases actually reached the neighbour we named — commit-range review went to `superpowers:requesting-code-review` (stable across three repeats), responding to a review to `receiving-code-review`, PR creation to `pr-create`. **The reverse direction did not hold**: "merge this PR and clean up the branch" is `finishing-a-development-branch`'s seat, and all three runs went to `Bash` instead. There is a stretch where the side we delegated to does not accept, which shows that "we now depend on somebody else's repository" in the Consequences below is not an abstraction. Method and numbers are in [agent-layer §4b](../agent-layer.md).

**So the remedy changes.** The rule "two skills sharing a trigger, pick one" still holds, but what overlapped here was not the *skills*, it was the *trigger phrase* ("review this"). Instead of deleting, we **redrew the dividing line along the lifecycle** and wrote it into the descriptions — is the PR open, or is this still a commit range?

The correction produces a rule of its own: **conflicts with an external skill are judged by the body, not the name.** Both pre-install verdicts made from names alone were wrong (this one, and the draft's exclusion of pyright).

> *Added 2026-08-07*: wrong a third time — `skill-creator` was judged from its name as "overlaps `writing-skills`, keep one", and its body turned out to be not a skill-writing helper but an **evaluation harness**. Three means the rule is not being followed, so [ADR-0011](0011-ecosystem-survey.md) takes on the judging procedure itself.

## Consequences

- Installing `harness-dev` loads 16 skills, not our two (`pr-create`, `pr-review`). The context cost is real, and it is why Superpowers is not in `core`.
- **The descriptions of `pr-create` and `pr-review` have to name the superpowers counterpart.** Without that, decision 2 is a declaration on paper and runtime routing still fights.
- Our routing discipline now depends on somebody else's repository. Superpowers adding a skill can create a new conflict, and today the only way we would notice is a periodic check.
- `pr-create` is in `harness-core` and Superpowers is a `harness-dev` dependency, so a user who installed only `core` does not have this conflict at all. It appears the moment `dev` is chosen.
- Installing a language profile creates no files. From the user's seat it looks like "installed, and nothing happened" — and with no server binary, nothing does. `harnessctl doctor` is the only thing that turns that silence into a diagnosis.
- A cross-marketplace dependency resolves only while `claude-plugins-official` is alive. If that marketplace disappears or a plugin is renamed, installing `harness-dev`, `harness-python` or `harness-typescript` breaks. That failure mode is not ours to prevent.

> *Added 2026-08-18*: **`harness-frontend` widens this past the official marketplace for the first time.** Its dependency, [`ui-ux-pro-max`](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill), is published by its author rather than curated by Anthropic, so `allowCrossMarketplaceDependenciesOn` now lists two names instead of one. The risk above is the same in kind and larger in degree — a single maintainer, not a vendor programme, and nothing between an upstream change and our consumers.
>
> Two mechanics were measured on a clean config directory rather than assumed, because both are silent when wrong. **A cross-marketplace dependency does not register the marketplace it names**: `claude plugin install harness-frontend` prints success and exits 0, and the plugin then sits at *"failed to load — Dependency "ui-ux-pro-max@ui-ux-pro-max-skill" is not installed"*. Registering it first is what resolves it, and `marketplace add` pulls the plugin in on its own (*"+ 1 dependency: ui-ux-pro-max"*). `install.sh` therefore registers it — but **only when `--profile` names `frontend`**, so a consumer who never asks for the profile is never pointed at the third-party marketplace at all. On the way out, `--prune` takes the plugin with it exactly as it takes Superpowers, and `uninstall.sh` **reports the marketplace registration rather than removing it**: it can serve a plugin the consumer installed for their own reasons, and §6's ownership model does not delete a value they already had.
>
> *Added 2026-08-19*: **`frontend` moved into the default profile set**, so the clause above — a consumer who never asks for the profile is never pointed at the third-party marketplace — no longer describes the default path. It now describes a `--profile` list without `frontend`, which is the flag a consumer passes to stay off that marketplace, and the README says so in the same row that names the cost. The reversal rests on the holdout not having protected anyone: being opt-in made the profile invisible, so what it actually cost was a consumer doing UI work who never learned it existed. **The risk statement above is unchanged and now applies by default** — a single-maintainer marketplace is registered on every default install. That is the price of the reversal, not an argument that the risk went away, and it is the reason the opt-out is documented rather than buried. `uninstall.sh` still reports the registration rather than removing it, for the same ownership reason.
- Taking `using-git-worktrees` clears the worktree-helper item from the backlog. Not building our own is always cheaper.

## Alternatives considered

- **Put Superpowers in `core`** — every consumer gets it, and a research-only user loads 14 unused descriptions every turn.
- **Vendor the Superpowers skills into this repository** — we could then cut the conflicts ourselves, but upstream updates become a manual chore, and it undoes what `dependencies` solves.
- **Ship both conflicting skills and let the model route** — flexible on the surface, and precisely the failure negative routing prevents. Non-determinism where the winner is invisible cannot be debugged.
- **Drop `pr-create` and `pr-review` and use the Superpowers ones** — less to maintain, but those two skills exist to execute our rule files, so the rules would stop being enforced.
- **No language profiles, just documentation** ("on Python, install `pyright-lsp` yourself") — pushes a manifest's worth of convenience onto the user, and leaves `doctor` with no way to know what to check.
- **Build the `ml` and `review` profiles now** — adding at zero occurrences because they seem nice to have, which is exactly what `CLAUDE.md` §7 forbids.

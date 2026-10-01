# archify and DESIGN.md — design

Status: approved in conversation; **implementation blocked on §8** (the context budget). Date: 2026-10-01.

> Dated design record. Counts and case totals quoted below describe the tree at the time of writing; [`agent-layer.md`](../../agent-layer.md) is the source of truth for current numbers — the figures here are a record of that moment.

Two outside assets enter the harness, by two different routes, in two PRs:

- **[`archify`](https://github.com/tt-a1i/archify)** (MIT) — an agent skill that turns a description, a Mermaid block or a repository into a validated standalone-HTML diagram (architecture, workflow, sequence, dataflow, lifecycle). It becomes a **dependency of `harness-dev`**.
- **[`awesome-design-md`](https://github.com/VoltAgent/awesome-design-md)** (MIT) — a collection of 74 brand-derived `DESIGN.md` files, installed into a project one at a time by its CLI, [`getdesign`](https://www.npmjs.com/package/getdesign). It ships **no skill**, so it enters as a **convention**: a `frontend` rule module.

## 1. Demand basis

The owner stated the need on 2026-10-01 after a survey of four candidates (`archify`, `img2threejs`, `ui-ux-pro-max`, `awesome-design-md`). That is the basis `claude-video` and `ui-ux-pro-max` were admitted on (`docs/agent-layer.md` §3b) — *site-dependent*, not two occurrences in this repository. `img2threejs` was not asked for; `ui-ux-pro-max` is already a dependency.

## 2. What was read, and what was not run

Read from a clone (`tt-a1i/archify@d5a1333`, `VoltAgent/awesome-design-md@f696123`) and from the Claude Code plugin docs. When this section was written nothing from either candidate had been executed — the auto-mode classifier refused `node bin/archify.mjs doctor` as external code, and that refusal is logged in `.claude/harness-gaps.md`. The owner then asked for archify to be run, and §7 records that run; it settles one row of §6 by hand, and every other behavioural claim below is still read, not measured.

Facts the design rests on:

| Fact | Source |
|---|---|
| archify has **no** `.claude-plugin/plugin.json` and no marketplace; its only installer is `npx skills add` | the tree |
| `archify/` holds `SKILL.md` at its root plus `bin/`, `schemas/`, `references/`, `examples/` — 313 files, 11 MB | the tree |
| A marketplace entry whose fetched source has no `plugin.json` **is** the manifest, regardless of `strict` | marketplace reference, *How an entry combines with plugin.json* |
| A plugin with `SKILL.md` at its root, no `skills/` and no `skills` key **loads as a single skill** | manifest reference, *Standard layout* |
| `git-subdir` fetches one subdirectory by sparse partial clone and takes `ref` + `sha` | marketplace reference, *Plugin sources* |
| archify's runtime has zero dependencies: `package.json` lists only `devDependencies`, and no file under `bin/` imports them (`scripts/generate-brand-marks.mjs` is the one that does) | the tree |
| A `package-lock.json` beside `package.json` makes Claude Code install Node dependencies in a separate step, scripts disabled | marketplace reference, *npm plugin source* → loading |
| archify makes a ~daily GET to a fixed manifest to show an update notice; it never installs. `ARCHIFY_UPDATE_CHECK_DISABLED=1` turns it off. The notice says the installed skill is unchanged and links release notes — it does not tell the user to run an installer | `README_EN.md:207`, `references/update-awareness.md` |
| archify needs Node ≥ 18 | `package.json` `engines` |
| `getdesign add <slug>` writes `./DESIGN.md` at the project root; `getdesign list` prints the catalog | `npm view getdesign readme` |
| `ui-ux-pro-max` never mentions `DESIGN.md` | `grep -r DESIGN.md` over its seven `SKILL.md` files: no hit |

## 3. PR 1 — archify as a `harness-dev` dependency

### Approaches

- **A, chosen: an entry in our own marketplace.** `.claude-plugin/marketplace.json` gains

  ```json
  {
    "name": "archify",
    "displayName": "Archify",
    "description": "Third-party (tt-a1i/archify, MIT), pinned: validated architecture, workflow, sequence, dataflow and lifecycle diagrams as standalone HTML. Needs Node 18+",
    "source": {
      "source": "git-subdir",
      "url": "tt-a1i/archify",
      "path": "archify",
      "ref": "v3.0.1",
      "sha": "2ab3cae7ac2c2a55d7386ca789d03c4fcd31816c"
    },
    "license": "MIT",
    "homepage": "https://github.com/tt-a1i/archify",
    "category": "development"
  }
  ```

  and `plugins/harness-dev/.claude-plugin/plugin.json` gains `"archify"` in `dependencies` (a bare name resolves against our own marketplace, so `allowCrossMarketplaceDependenciesOn` and `install.sh` are untouched). `2ab3cae` is the commit the `v3.0.1` tag points at, not the default-branch head.
- **B, rejected: vendor `archify/` into `plugins/harness-dev/skills/`.** No fetch at install time, but 11 MB of someone else's tree in ours, a manual sync for every upstream release, and the shape [ADR-0009](../../adr/0009-external-dependencies.md) already turned down for Superpowers.
- **C, unavailable: a cross-marketplace dependency.** There is no upstream marketplace to depend on.

### What A changes about trust

Every earlier dependency is served by **its author's** marketplace. This is the first time our marketplace serves somebody else's code under our name. The consequence is a responsibility, recorded as an addendum to ADR-0009: **whoever moves the `sha` reads the upstream diff between the two commits**, because nothing else stands between an upstream change and every default install. The upside is the same fact read the other way — an upstream change reaches nobody until we move the pin.

### Decisions inside PR 1

- **The update check stays on.** It installs nothing, and switching it off by default would need an `env` merge in `harnessctl` — `settings-fragment.json` writes top-level scalars only, and `env` is an object, so a consumer who already has an `env` key would silently not get it. New machinery for a notice is §7 over-design. `docs/agent-layer.md` names the variable for anyone who wants it off.
- **`harnessctl doctor` reports `node`.** One line in the same style as the `slides-grab` check (`harnessctl:227-232`): `ok` when `node --version` is ≥ 18, otherwise a `--` line naming archify and `harness-dev`. `doctor` is not profile-aware today and this does not make it so.
- **The skill's namespaced name is `archify:archify`.** Plugin skills are prefixed by the plugin name. To be confirmed by the install in §6, not assumed.

### Files

| File | Change |
|---|---|
| `.claude-plugin/marketplace.json` | the entry above |
| `plugins/harness-dev/.claude-plugin/plugin.json` | `"archify"` in `dependencies`; `version` bump |
| `plugins/harness-core/bin/harnessctl` | the `node` line in `doctor` |
| `scripts/verify-install.sh` | cases for that line — node present ≥ 18, present < 18, absent (it is the verifier that already drives `doctor`) |
| `plugins/harness-core/.claude-plugin/plugin.json` | `version` bump (harnessctl changed) |
| `scripts/context-budget.sh` | `"archify@agent-harness:DEV_P"` in the plugin list |
| `docs/agent-layer.md` | §3 inventory (skills row: `archify` 1 under `dev`), §3b verdict row, the profile cost table, the `harness-dev` tree line |
| `docs/adr/0009-external-dependencies.md` | the trust addendum |
| `README.md`, `README.ko.md` | the profile and external-skills rows that count skills |

## 4. PR 2 — the `frontend` rule module

### The rule

`plugins/harness-core/declarative/rules/frontend/design-md.md`, installed as `.claude/rules/harness/frontend/design-md.md`. `harnessctl` already globs `rules/<module>/*.md` (`harnessctl:452`), so it needs no change; `install.sh:114` adds `frontend` beside `dev|research` so the default profile list passes `--with frontend`.

Body, in substance (final wording in the PR):

1. If `DESIGN.md` exists at the project root, read it before writing or changing UI. Its tokens — colour, type scale, spacing, radius, components, motion — are the source of truth.
2. It outranks generic recommendations, including `ui-ux-pro-max`'s styles, palettes and font pairings. Use those only for what `DESIGN.md` leaves open, and say that you did.
3. No `DESIGN.md`, and the user wants a recognisable look: `npx getdesign list` and `npx getdesign add <slug>` fetch one from the `awesome-design-md` catalog. It writes a file at the project root, so ask first, and never overwrite an existing `DESIGN.md` without explicit consent.
4. The catalog imitates real companies' visual identity. Fine for prototypes and internal tools; say so when the output is headed for public release.

### Scope: `paths: ["**/*"]`

Narrowing `paths` to UI extensions looks cheaper and breaks the rule's main case: a new project has no UI file yet, so on "build me a landing page" the rule would not be loaded at the moment it matters. `rules/dev/review.md` uses `**/*` for the same reason. The cost is the rule's size in every session of a project-scope install — estimated ~200 tok, measured in §6.

### Known limit

Rules are not installed at user scope (`harnessctl:445`). A user-scope consumer gets neither this rule nor `dev`'s and `research`'s. That is the existing, accepted constraint, and the rule's document says so rather than working around it.

### Files

| File | Change |
|---|---|
| `plugins/harness-core/declarative/rules/frontend/design-md.md` | new; description quoted (`verify-frontmatter`) |
| `install.sh` | `frontend` in the module case at line 114, and the comment above it |
| `scripts/verify-install.sh` | the default profile list installs the rule; uninstall leaves the tree as it was |
| `plugins/harness-core/.claude-plugin/plugin.json` | `version` bump (declarative payload changed) |
| `docs/agent-layer.md` | rules row of the inventory, the `harness-frontend` description |
| `README.md`, `README.ko.md` | the frontend profile row |
| `.claude-plugin/marketplace.json`, `plugins/harness-frontend/.claude-plugin/plugin.json` | description strings mention the rule; `harness-frontend` `version` bump |

## 5. What this does not do

- Install `getdesign` or any `DESIGN.md`. The rule tells the agent the tool exists; the choice of brand is the user's.
- Write a skill for either asset. archify is a dependency; `awesome-design-md` has no skill to depend on, and building a working skill around it is the §1 second non-goal.
- Switch off archify's update check by default (PR 1, *Decisions*).
- Touch `img2threejs`. Not requested.

## 6. Verification

| Claim | Check | When |
|---|---|---|
| Manifests are valid | `claude plugin validate . --strict` | both PRs |
| archify installs and loads as one skill | scratch `CLAUDE_CONFIG_DIR`, add this checkout as a directory marketplace, `claude plugin install harness-dev@agent-harness`, then `claude plugin details archify` — record the skill name and the always-on figure | PR 1 |
| Whether the lockfile pulls `devDependencies` into the cache | inspect the installed cache directory for `node_modules/` after the step above | PR 1 |
| archify's body runs | one diagram end to end through the installed skill (`finalize … --quality showcase`) — **external code; ask for permission at this step** | PR 1 |
| Routing is undisturbed | `results-deck` paired, with and without archify, 3 runs each — the `ui-ux-pro-max` method (§4b). **Costs model sessions** | PR 1 |
| The rule installs and uninstalls cleanly | `scripts/verify-install.sh` new cases | PR 2 |
| The rule changes behaviour | one UI task in a scratch project that has a `DESIGN.md`: the first UI action reads it, and the output uses its tokens | PR 2 |
| Everything else | `make verify-all`, `make verify BASH=/bin/bash` | both PRs |
| Published totals | the check total moves and `verify-all` fails until the five copies agree; the always-on worst case is produced by the first CI run and republished in a second commit (`CLAUDE.md` §2d) | both PRs |

A step that cannot run is reported as not run, beside the claim it would have supported — not dropped.

## 7. First run, 2026-10-01

The owner asked for a status report on this repository built with archify, so the body ran once before any of PR 1 exists. **It ran by hand, not through the plugin path PR 1 creates**: a scratch clone at `d5a1333` (the default-branch head, not the `v3.0.1` pin in §3), invoked as `node bin/archify.mjs` with `ARCHIFY_UPDATE_CHECK_DISABLED=1`. It therefore settles §6's *archify's body runs* row and none of the install or loading rows.

| Step | Result |
|---|---|
| `doctor` | every runtime `ok`, ending `Archify is ready.` |
| The diagram | one Architecture overview of this repository pinned at `739fdcd` (origin/main): 9 components, 9 relationships, 1 boundary, 4 status cards, every component carrying `sources` with line ranges. Authored in Korean |
| `finalize … --repo-root <this repo> --quality showcase` | **first draft, all four gates pass** — `validate`, `deliver`, `check`, `browser-check` — in 6,559 ms; a 767,592-byte standalone HTML; receipt `update.status: "disabled"`, so no request left the machine |
| `visual-check --summary --require-provenance` | `containment`, `readability`, `viewerChrome`, `themeStates`, `captures` pass. The 1440×900 light and 2048×1320 dark captures were then looked at: nodes, labels and cards legible in both themes; two relationship labels sit on the boundary's dashed edge, readable, left alone |

The input is kept as [`2026-10-01-archify-run/candidate.json`](2026-10-01-archify-run/candidate.json) — its sha256 `33fa5904…67e2` is the `specification.sha256` in the `finalize` receipt, so it is the file that ran, not a later copy — and the 1440×900 light capture as [`harness-status-1440-light.png`](2026-10-01-archify-run/harness-status-1440-light.png). The 767 KB HTML and the receipts are not committed: the HTML is regenerated from the input, and the receipts carry this machine's absolute paths. To regenerate, from a directory that contains the input at the path its `meta.output` expects:

```bash
node <archify>/bin/archify.mjs finalize architecture candidate.json harness-status.html \
  --repo-root <this repository> --quality showcase --json
```

The status cards are a snapshot of 2026-10-01 — installed versions, the local budget run, PR counts — and go stale on the next `claude plugin update`; the topology and its `sources` are pinned to `739fdcd` and do not.

Three things the run showed that reading had not:

- **The browser gate found Chrome on its own** (`/Applications/Google Chrome.app`). Whether `finalize` passes, degrades or fails on a machine with no Chrome was not tested, so §3's `doctor` line may need a second check beside `node`. Open until tested.
- **The Viewer's fixed controls stay English for a Korean diagram.** Only `en` and `zh-CN` ship built-in catalogs; any other `meta.locale` needs a hand-supplied `meta.translations`. Authored content is unaffected. Worth one sentence in the dependency's documentation, not a change.
- **The repository-evidence contract is strict and it helped.** `meta.repository` pins a forty-character revision and every cited path is checked against committed bytes at that revision, which is why the diagram cites `739fdcd` rather than this branch's unpushed head.

The status cards themselves surfaced the finding in §8.

## 8. The context budget — the gap this design missed

§3 and §4 add standing text and never price it against the ceiling. `docs/agent-layer.md:221` says adding is a trade, and the trade was not made.

| Figure | Value | Source |
|---|---|---|
| Ceiling | 9,000 tok | `Makefile` `CONTEXT_CEILING` |
| Published worst case | ~8,558 → headroom ~442 | `docs/agent-layer.md:208`, measured in CI |
| Local worst case, 2026-10-01 | 8,968 → headroom 32 | `make verify-all`, **stale**: it measured installed `harness-core` 1.23.1, `harness-dev` 1.1.1 and `harness-slides` 1.6.0 against a tree at 1.23.2, 1.2.0 and 1.7.0 |
| PR 1 adds | ~170 tok, **inferred** from the 665-character description | not measured |
| PR 2 adds | ~200 tok at project scope, **inferred** | not measured |

~370 inferred against ~442 of published headroom fits with ~70 to spare; against the local figure it does not fit at all. Neither number is good enough to decide on, and two oddities from the same run say so: `ui-ux-pro-max` measured **1 tok** locally against a published ~716, and `docs/agent-layer.md:221` states ~610 of headroom where `:208` implies ~442. Both are in the ledger as first occurrences.

**Implementation starts only after this is decided**, in this order:

1. `claude plugin update` the three stale plugins and re-run `context-budget`, so the local figure measures the tree.
2. Measure PR 1's real cost in a scratch config (§6, second row) instead of the inferred ~170.
3. Then choose one: it fits and ships as designed; or narrow PR 2's `paths` and accept losing the new-project case §4 argued for; or raise `CONTEXT_CEILING` with a stated reason in the same change; or name what comes out.

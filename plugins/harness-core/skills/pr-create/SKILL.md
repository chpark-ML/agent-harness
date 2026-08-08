---
name: pr-create
description: "Use when the user wants the current work turned into a pull request following this repo's conventions — detect the working state, branch off the default branch if needed, commit in semantic units, push, and open the PR with `gh`. Stops at PR open; never merges. 한국어 트리거: 'PR 올려', 'PR 만들어줘', '이거 PR 로', '커밋하고 푸시해줘'. 이미 열린 PR 을 읽고 리뷰하는 것은 이 스킬 말고 pr-review, 머지 전 커밋 범위 자기검토는 requesting-code-review 로. Superpowers 의 finishing-a-development-branch 가 'PR 을 만든다' 를 택했다면 그 다음이 이 스킬이다 — 그쪽이 따르라고 말하는 저장소 규약이 여기 있다."
---

# pr-create

Runs `.claude/rules/harness/workflow.md` R1–R4 end to end. **Scope ends at PR open** — merging is the user's. The post-merge harness retro (R3.1) is a separate trigger.

## Step 0 — Is this a PR unit at all?

Judge with R1's three cases. A single-file typo, a one-line fix, throwaway exploration — **stop here** and report the result. Do not commit, do not push. Skip this judgement when the user explicitly said "open a PR".

## Step 1 — Establish state

```bash
git status --porcelain
git branch --show-current
git log --oneline @{upstream}..HEAD 2>/dev/null || git log --oneline -5
```

Three things: what changed, which branch you are on, and whether something is committed but unpushed.

**Show the user the list of changed files** and confirm none of them belong to something else — leftovers from other work, local experiments, accidental artefacts. Do not reach for `git add -A` uncritically.

## Step 2 — Branch

On the default branch, pick a slug and branch.

```bash
git switch -c {feat|fix|chore}-<slug>
```

- `feat` new capability / `fix` a bug / `chore` everything else (build, config, docs, refactor)
- the slug is 2–4 words in kebab-case, no `/`
- already on a feature branch: use it

The slug becomes the PR title's prefix, so it has to say *what the change does*. `chore-fix` is not a slug.

## Step 3 — Commit

Split by meaning. A refactor mixed with a new capability is two commits.

```bash
git add <paths>          # explicit paths, not -A
git commit -m "<verb-first subject>" -m "<why>"
```

Hold to R2: no AI attribution. The `ai-attribution-guard` hook blocks it, but do not write it in the first place.

## Step 4 — Self-check

Actually run R4's checklist. In particular:

```bash
git status                                    # nothing missing, nothing stray
git log --format='%B' <default-branch>..HEAD  # no attribution
```

And **actually run the verification** — whichever of tests, build and lint this project has. That output goes into Step 5's verification section. If there is none, write "this project has no automated checks, so <what> was confirmed by hand".

## Step 5 — Push and open

**Count the title first.** R4 asks for 70 characters or fewer and nothing counts them, so the repository that wrote that rule opened PRs at 71 and 79 characters. A rule counted by hand is a rule forgotten by hand.

```bash
TITLE="[<slug>] <description>"
[ "${#TITLE}" -le 70 ] || { echo "title is ${#TITLE} chars — shorten to 70 or fewer: $TITLE"; }
```

Over the limit, shorten the description. The slug is the branch name and does not change.

```bash
git push -u origin <branch>
gh pr create --title "$TITLE" --body "$(cat <<'EOF'
## Motivation
<why this change is needed — the problem or the request>

## Changes
- <change 1>
- <change 2>

## Verification
<the commands you actually ran and their output. If you ran none, say so.>

## Notes
<trade-offs, follow-ups, and what was deliberately left undone>
EOF
)"
```

`git push` and `git merge` sit in `settings.json`'s `ask` tier, so an approval prompt appears. That is normal in an interactive session.

**In a non-interactive session (`claude -p`, CI) push is always refused.** There is nobody to answer, and `--permission-mode` does not get around it — `acceptEdits`, `dontAsk` and `bypassPermissions` were all measured as refused. What to do then is fixed.

- **Do not fire the same command again.** The second attempt is refused too.
- **Do not substitute a commit to `main`.** That is the path by which a convention violation arrives quietly.
- The commits are already made, so **stop there** and print the two remaining commands verbatim:

  ```bash
  git push -u origin <branch>
  gh pr create --title "..." --body "..."
  ```

- If automation genuinely has to reach the end, the only route is that project moving `"Bash(git push:*)"` into `permissions.allow` in its own `settings.json` — and **that is a human's decision, not this skill's.** Say so and stop.

## Step 6 — Read the harness-gap ledger

A PR is the natural moment to read it: the work closes as one unit, and it is the only point where `CLAUDE.md` §5's "propose after two occurrences" can be judged.

```bash
[ -f .claude/harness-gaps.md ] && tail -40 .claude/harness-gaps.md
```

- If the same file and the same symptom appear **twice or more**, put one line in the PR body under `## Notes`: `*harness gap*: <file>:<line> — <diagnosis> (occurrence N)`.
- Once only: leave it. It stays in the ledger waiting for a second.
- **An empty or missing ledger is not evidence there are no gaps.** It usually means nobody wrote to one. If something snagged during this work and is not written down, write it now.

## Step 7 — Report

Report the PR URL and title. **Do not merge.** The user merges, then asks for the R3.1 retro separately or it follows naturally in the next turn.

## What this skill does not do

- `gh pr merge` — out of scope.
- Force push — `deny` tier.
- Include a file in a commit that the user has not seen.
- Fill in the verification section without running the verification.

---
name: pr-review
description: "Use when a pull request is already open on the forge and you want it read against this repo's review checklist — resolves the PR, reads `gh pr diff` plus the surrounding files, and reports a ranked punch list separating blocking from non-blocking findings. 한국어 트리거: '이 PR 리뷰해줘', 'PR 봐줘', '머지해도 되나', 'PR 점검해줘'. 아직 PR 이 없는 커밋 범위를 머지 전에 검토하는 것은 이 스킬 말고 requesting-code-review, 받은 리뷰에 대응하는 것은 receiving-code-review, PR 생성은 pr-create 로."
---

# pr-review

Reviews one already-open PR against the checklist in `.claude/rules/harness/dev/review.md` and **reports**.

**What this skill does not do** — it does not commit or push, does not comment on GitHub unless the user explicitly asks, and does not merge. The output is one punch list for the user.

## Step 1 — Resolve the PR number

Use the number if one was given. Otherwise find it from the current branch.

```bash
gh pr view --json number,title,state,headRefName    # the PR for the current branch
```

If the current branch has no PR, **stop and ask** — reviewing changes that are not open is a different job. Going as far as `gh pr list --limit 20` to show candidates is enough.

## Step 2 — Gather context

```bash
gh pr view <N> --json title,body,author,baseRefName,headRefName,files,additions,deletions
gh pr diff <N>
```

Read the `body` first. **The author's stated intent** is the baseline for the checklist's first item — *does every changed line trace to that intent*. An empty body is itself the first blocking finding.

## Step 3 — Read the changed files with their surroundings

Do not review from the diff alone. A diff shows *changed lines*, so it cannot show that a caller disappeared, that an existing contract broke, or that the same file already has a function doing the same thing.

```bash
gh pr diff <N> --name-only        # the changed files
```

Open each with Read. If the branch is not local and the files are not current:

```bash
git status --short                # confirm clean first, always
gh pr checkout <N>                # changes the working tree — never run this when dirty
```

When dirty, do not check out. Work from `gh pr diff` and the base files, and **say in the report that the surrounding context was not read**.

## Step 4 — Apply the checklist

Walk `review.md` R2's six items in order. For each, collect the `file:line` of what it caught. Omit items that caught nothing — a list of passes is not output.

When the change is too large to read fully, state what was covered. **A partial review that gives the impression of a full one is worse than no review.**

## Step 5 — Report

Two lists, each ordered by impact.

```
## Blocking (N)
1. `path/to/file.py:88` — <what breaks if this merges>. Fix: <specifically what>.

## Non-blocking (M)
1. `path/to/other.ts:12` — <suggestion>.

## Needs a decision
- <items requiring judgement the reviewer should not make on the author's behalf>
```

Follow `review.md` R3 exactly — one line per blocking item on what breaks, `file:line` on everything, and the fix rather than the name of the problem.

## Step 6 — Only if the user asks for it on GitHub

```bash
gh pr comment <N> --body-file <file>              # a summary comment
gh pr review <N> --comment --body-file <file>     # as a review
```

`--approve` and `--request-changes` only when the user says those words. Approval is a human judgement.

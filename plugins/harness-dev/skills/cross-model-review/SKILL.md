---
name: cross-model-review
description: "Use when the user wants the current commit range reviewed by a different model — checks that Chrome and a logged-in ChatGPT session are actually reachable, sends the `main..HEAD` diff only after explicit consent, and reports the outside findings with our own verdict on each. 한국어 트리거: 'ChatGPT 한테도 리뷰받아줘', 'GPT 의견도 들어보자', '다른 모델로 교차 검토해줘', '외부 의견도 받아보자'. 모델을 지정하지 않은 머지 전 자기검토는 이 스킬 말고 requesting-code-review, 이미 열린 PR 은 pr-review, 받은 리뷰에 대응하는 것은 receiving-code-review 로."
---

# cross-model-review

Sends `<default-branch>..HEAD` to a **different model** and brings back what it found.

**The boundary is who reviews, not when.** The input here is the same commit range `superpowers:requesting-code-review` takes, so the two cannot be separated by lifecycle stage the way `pr-create` and `pr-review` are — see ADR-0009 in `docs/adr/`. This skill is for when the user asked for an **outside opinion** — another model, ChatGPT, a cross-check. A plain "review my commits" is not this skill; it belongs to `requesting-code-review`, which stays inside Claude and needs no consent gate.

## Step 0 — Was a second opinion actually asked for?

If the request never named another model, a cross-check, or an outside opinion, **stop and hand off**. Getting this wrong is expensive in a way an ordinary misroute is not: this skill's whole job is to move the user's code off their machine.

## Step 1 — Preflight the channel, before promising anything

Two legs, in order. Stop at the first failure.

```
mcp__claude-in-chrome__tabs_context_mcp     # is the extension connected at all?
mcp__claude-in-chrome__navigate  →  chatgpt.com
```

Then look at what came back. A composer means a live session; a login or paywall screen means there is nothing to talk to. The extension also gates by site, so a first visit may need the user to grant `chatgpt.com` in the extension.

**Report the failing leg by name and hand off to `requesting-code-review`.** Do not quietly substitute a Claude review for the outside one that was requested — the user asked for a second model precisely because the first one is already in the room.

## Step 2 — Build the range

```bash
DEFAULT="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
DEFAULT="${DEFAULT:-main}"
BASE="$(git merge-base HEAD "$DEFAULT")"
git log --oneline "$BASE..HEAD"
git diff --stat "$BASE..HEAD"
```

An empty range is not a review, it is a mistake upstream — say so and stop. Read the commit subjects and bodies before the diff: **the author's stated intent is what the outside model has to be told**, or it reviews against a purpose it invented.

## Step 3 — The consent gate

This is the step the skill exists to get right. Everything in the diff leaves the machine and reaches a third party, and once sent it cannot be recalled.

Show the user, in chat, before anything is pasted:

- the file list and `--stat` totals from Step 2
- one plain sentence that this content will be sent to ChatGPT under their account
- anything in the range that looks like a credential, a customer name, or a fixture with real data

Then wait for an explicit yes. **Per invocation** — an approval from earlier in the session does not carry, because the diff is not the same diff. Silence, "sure, whatever", or a yes to a different question is not consent.

If the user declines, that is a complete outcome: say the review did not happen and offer `requesting-code-review`.

## Step 4 — Send it, with the two guards

Compose one message: the intent from Step 2, then the diff, then what shape of answer you want (blocking versus non-blocking, `file:line` on everything).

Both guards below come from failures actually observed driving this UI on 2026-08-17. Neither is theoretical, and neither announces itself.

**Guard 1 — read the composer back before pressing Enter.** Typing `파리의 수도는?` produced `파리의수도는` in the box: the space and the `?` were dropped in IME composition. A prompt that loses characters gets you a confident review of a question you did not ask. Compare what is in the composer against what you meant to type, and retype if they differ.

**Guard 2 — poll until two consecutive reads agree.** Mid-stream, the page text returns a prefix that looks like a finished answer — `1,` where the model went on to write `1, 4, 9, 16, 25`. Two identical reads in a row, or a screenshot as the tiebreak. One read is how a truncated review gets reported as the whole review.

**On size, say what is not known.** This path has only been exercised on short prompts. A large diff may hit the composer rather than the model, and where that ceiling sits has not been measured. Over roughly 800 changed lines, **do not truncate silently** — report the size and ask the user what to leave out. A review of a diff the reviewer never saw all of is worse than no review, because it reads like a clean bill.

## Step 5 — Report, with your own verdict on each finding

Bring back what the other model said, and then **judge it**. An unevaluated second opinion is noise the user now has to sort through themselves.

```
## From ChatGPT (N findings)
1. `path/file.py:88` — <their finding>
   → agree / disagree / needs checking, and why in one line

## Conflicts with this repo's conventions
- <finding> contradicts `.claude/rules/harness/dev/review.md` <item>
```

Cross-model review has a specific failure mode: **the outside model does not know this repository's rules**, so it will confidently suggest things our conventions forbid. Flag those rather than passing them through. Say plainly which findings you could not verify.

## Step 6 — Clean up

Close the tab you opened. Tell the user the conversation stays in their ChatGPT history — the tab closing does not delete it.

## What this skill does not do

- Send anything before Step 3's explicit yes.
- Fall back to a Claude review when the channel is down. Say it is down.
- Log in, solve a bot check, or enter a credential.
- Truncate a diff to make it fit.
- Present the other model's output as a verdict. It is one opinion, and Step 5 is where it gets weighed.

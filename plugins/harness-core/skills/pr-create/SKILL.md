---
name: pr-create
description: "Use when the user wants the current work turned into a pull request following this repo's conventions — detect the working state, branch off the default branch if needed, commit in semantic units, push, and open the PR with `gh`. Stops at PR open; never merges. 한국어 트리거: 'PR 올려', 'PR 만들어줘', '이거 PR 로', '커밋하고 푸시해줘'. 이미 열린 PR 을 읽고 리뷰하는 것은 이 스킬 말고 pr-review, 머지 전 커밋 범위 자기검토는 requesting-code-review 로. Superpowers 의 finishing-a-development-branch 가 'PR 을 만든다' 를 택했다면 그 다음이 이 스킬이다 — 그쪽이 따르라고 말하는 저장소 규약이 여기 있다."
---

# pr-create

`.claude/rules/harness/workflow.md` R1–R4 를 end-to-end 로 실행한다. **PR open 까지가 범위** — 머지는 사용자가 한다. 머지 직후의 harness retro (R3.1) 도 별도 trigger.

## Step 0 — PR 단위인지 먼저 판정

R1 의 세 case 로 판정한다. 단일 파일 typo·한 줄 수정·임시 탐색이면 **여기서 멈추고** 결과만 보고한다. 커밋도 푸시도 하지 않는다. 사용자가 명시적으로 "PR 올려" 라고 했으면 이 판정은 건너뛴다.

## Step 1 — 상태 파악

```bash
git status --porcelain
git branch --show-current
git log --oneline @{upstream}..HEAD 2>/dev/null || git log --oneline -5
```

세 가지를 확인한다: 어떤 파일이 변경됐나, 지금 어느 브랜치인가, 이미 커밋됐지만 안 올라간 게 있나.

**변경 파일 목록을 사용자에게 보여주고**, 그 중 이번 PR 에 들어가면 안 되는 것 (다른 작업의 잔재, 로컬 실험, 실수로 생긴 artifact) 이 있는지 확인한다. `git add -A` 를 무비판적으로 쓰지 않는다.

## Step 2 — 브랜치

Default branch 위라면 slug 를 정해 분기한다.

```bash
git switch -c {feat|fix|chore}-<slug>
```

- `feat` 새 기능 / `fix` 버그 / `chore` 그 외 (빌드·설정·문서·리팩터)
- slug 은 2–4 단어 kebab-case, `/` 금지
- 이미 feature branch 위라면 그대로 쓴다

Slug 은 PR title 의 prefix 로도 쓰이므로, *무엇을 하는 변경인지* 가 드러나야 한다. `chore-fix` 는 slug 이 아니다.

## Step 3 — 커밋

의미 단위로 나눈다. 리팩터와 기능 추가가 섞여 있으면 두 커밋으로.

```bash
git add <paths>          # -A 대신 명시적 경로
git commit -m "<동사로 시작하는 70자 이하 제목>" -m "<why>"
```

R2 를 지킨다: AI 귀속 문구 금지 (`ai-attribution-guard` 훅이 차단하지만, 애초에 쓰지 않는다).

## Step 4 — self-check

R4 체크리스트를 실제로 돌린다. 특히:

```bash
git status                                    # 누락·잔재 없음
git log --format='%B' <default-branch>..HEAD  # 귀속 문구 없음
```

그리고 **검증을 실제로 실행한다** — 테스트, 빌드, 린트 중 이 프로젝트에 있는 것. 그 출력이 Step 5 의 verification 섹션에 들어간다. 없으면 "이 프로젝트에는 자동 검증이 없어 <무엇을> 수동 확인했다" 라고 적는다.

## Step 5 — push + PR

**제목 길이를 먼저 센다.** R4 는 70자 이하를 요구하는데 세는 것이 없어서, 이 규약을 적어둔 저장소가 71자와 79자짜리 PR 을 실제로 열었다. 사람이 세는 규칙은 사람이 잊는다.

```bash
TITLE="[<slug>] <description>"
[ "${#TITLE}" -le 70 ] || { echo "제목 ${#TITLE}자 — 70자 이하로 줄인다: $TITLE"; }
```

넘으면 description 을 줄인다. slug 는 브랜치 이름이라 바꾸지 않는다.

```bash
git push -u origin <branch>
gh pr create --title "$TITLE" --body "$(cat <<'EOF'
## Motivation
<왜 이 변경이 필요한가 — 문제 또는 요구>

## Changes
- <변경 1>
- <변경 2>

## Verification
<실제로 돌린 명령과 그 결과. 안 돌렸으면 안 돌렸다고 적는다.>

## Notes
<리뷰어가 알아야 할 트레이드오프·후속 작업·의도적으로 안 한 것>
EOF
)"
```

`git push` 와 `git merge` 는 `settings.json` 의 `ask` 티어라 승인 프롬프트가 뜬다. 대화형 세션에서는 정상이다.

**비대화형 세션(`claude -p`·CI)에서는 push 가 반드시 거부된다.** 답할 사람이 없어서이고, `--permission-mode` 로는 못 뚫는다 (`acceptEdits`·`dontAsk`·`bypassPermissions` 셋 다 실측으로 거부됨). 그때 할 일은 정해져 있다.

- **같은 명령을 다시 쏘지 않는다.** 두 번째도 거부된다.
- **`main` 에 커밋하는 것으로 대체하지 않는다.** 규약 위반이 조용히 들어가는 경로다.
- 커밋까지는 이미 끝났으므로 **거기서 멈추고**, 남은 두 명령을 그대로 출력한다:

  ```bash
  git push -u origin <branch>
  gh pr create --title "..." --body "..."
  ```

- 자동화에서 끝까지 돌려야 한다면 그 프로젝트의 `settings.json` 에 `"Bash(git push:*)"` 를 `permissions.allow` 로 올리는 것이 유일한 방법이고, **그건 사람이 내릴 결정이지 이 스킬이 내릴 결정이 아니다.** 그렇게 안내만 한다.

## Step 6 — harness gap 원장 확인

PR 은 원장을 읽는 자연스러운 지점이다 — 작업이 한 덩어리로 닫히는 순간이고, `CLAUDE.md` §5 의 "두 번 이상 발생하면 제안한다" 를 판정할 수 있는 유일한 자리이기 때문이다.

```bash
[ -f .claude/harness-gaps.md ] && tail -40 .claude/harness-gaps.md
```

- 같은 파일·같은 증상이 **두 번 이상** 적혀 있으면 PR 본문 `## Notes` 에 한 줄로 올린다: `*harness gap*: <file>:<line> — <진단> (원장 N회차)`.
- 한 번뿐이면 올리지 않는다. 원장에 남아 두 번째를 기다린다.
- **원장이 비어 있거나 없다고 해서 gap 이 없다는 뜻이 아니다.** 대개는 아무도 안 적었다는 뜻이다. 이번 작업에서 뭔가 걸렸는데 안 적혀 있으면 지금 적는다.

## Step 7 — 보고

PR URL 과 title 을 보고한다. **머지하지 않는다.** 사용자가 머지한 뒤 R3.1 retro 를 별도로 요청하거나, 다음 turn 에서 자연스럽게 이어간다.

## 하지 않는 것

- `gh pr merge` — 범위 밖.
- Force push — `deny` 티어.
- 사용자에게 안 보여준 파일을 커밋에 포함.
- 검증을 안 돌리고 verification 섹션을 채우기.

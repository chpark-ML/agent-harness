---
name: pr-review
description: "Use when a pull request is already open on the forge and you want it read against this repo's review checklist — resolves the PR, reads `gh pr diff` plus the surrounding files, and reports a ranked punch list separating blocking from non-blocking findings. 한국어 트리거: '이 PR 리뷰해줘', 'PR 봐줘', '머지해도 되나', 'PR 점검해줘'. 아직 PR 이 없는 커밋 범위를 머지 전에 검토하는 것은 이 스킬 말고 requesting-code-review, 받은 리뷰에 대응하는 것은 receiving-code-review, PR 생성은 pr-create 로."
---

# pr-review

이미 열려 있는 PR 하나를 `rules/harness/dev/review.md` 의 체크리스트로 검토하고 **보고**한다.

**본 스킬이 하지 않는 것** — commit·push 하지 않고, GitHub 에 코멘트를 남기지 않으며(사용자가 명시적으로 요청할 때만), 머지하지 않는다. 출력은 사용자에게 주는 punch list 하나다.

## Step 1 — PR 번호 확정

인자로 번호가 주어지면 그대로 쓴다. 없으면 현재 branch 에서 찾는다.

```bash
gh pr view --json number,title,state,headRefName    # 현재 branch 의 PR
```

현재 branch 에 PR 이 없으면 **거기서 멈추고 물어본다** — 열려 있지 않은 변경을 리뷰하는 건 다른 작업이다. `gh pr list --limit 20` 으로 후보를 보여주는 정도까지만.

## Step 2 — 컨텍스트 수집

```bash
gh pr view <N> --json title,body,author,baseRefName,headRefName,files,additions,deletions
gh pr diff <N>
```

`body` 를 먼저 읽는다. **작성자가 선언한 의도** 가 체크리스트 R2 의 첫 항목("모든 줄이 그 의도로 추적되는가")의 기준선이기 때문이다. body 가 비어 있으면 그 자체가 첫 blocking 항목이다.

## Step 3 — 변경 파일을 주변 맥락과 함께 읽는다

diff 만으로 리뷰하지 않는다. diff 는 *바뀐 줄* 만 보여주므로, 호출자가 사라졌는지·기존 계약을 깼는지·같은 파일 안에 이미 같은 일을 하는 함수가 있는지를 못 본다.

```bash
gh pr diff <N> --name-only        # 변경 파일 목록
```

각 파일을 Read 로 연다. branch 가 로컬에 없어 파일이 최신 상태가 아니면:

```bash
git status --short                # 반드시 clean 인지 먼저 확인
gh pr checkout <N>                # working tree 를 바꾸므로 dirty 면 실행 금지
```

dirty 면 checkout 하지 말고 `gh pr diff` 와 base 파일만으로 진행하되, **주변 맥락을 못 봤다는 사실을 보고에 적는다**.

## Step 4 — 체크리스트 적용

`review.md` R2 의 6 항목을 순서대로 걸어간다. 각 항목마다 걸린 지점의 `file:line` 을 모은다. 걸린 게 없는 항목은 보고에서 생략한다 — 통과 목록은 출력이 아니다.

변경 규모가 커서 전부 못 볼 때는 훑은 범위를 명시한다. "전부 봤다" 는 인상을 주는 부분 리뷰가 리뷰 없음보다 나쁘다.

## Step 5 — 보고

두 목록으로 분리한다. 각 목록 안에서는 영향 큰 것부터.

```
## Blocking (N)
1. `path/to/file.py:88` — <머지되면 무엇이 깨지는가>. 고칠 내용: <구체적으로>.

## Non-blocking (M)
1. `path/to/other.ts:12` — <제안>. 

## 확인 요청
- <판단이 필요해 리뷰어가 대신 정하지 않는 항목>
```

`review.md` R3 의 보고 규약을 그대로 따른다 — blocking 은 "무엇이 깨지는가" 한 줄, 모든 항목에 `file:line`, 문제 이름이 아니라 고칠 내용.

## Step 6 — 사용자가 GitHub 반영을 요청한 경우에만

```bash
gh pr comment <N> --body-file <file>              # 요약 코멘트
gh pr review <N> --comment --body-file <file>     # 리뷰로 남길 때
```

`--approve` / `--request-changes` 는 사용자가 그 단어로 지시했을 때만. 승인은 사람의 판단이다.

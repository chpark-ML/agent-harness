---
description: Branch, commit and PR conventions, plus the harness-gap loop. Catch-all — applies to every session.
paths: ["**/*"]
---

# Workflow — catch-all rules

**우선순위.** `CLAUDE.md` (global default) ⊂ 본 파일 (catch-all) ⊂ 도메인 rule (`rules/harness/<module>/*.md`) ⊂ skill·agent. 좁은 scope 가 이긴다.

본 파일은 [agent-harness](https://github.com/chpark-ML/agent-harness) 가 관리한다. 재설치 시 덮어써지므로 여기서 고치지 말고 하네스 저장소에서 고칠 것 — 근거는 [`CLAUDE.md` §5](../../../CLAUDE.md).

---

## R1 — 작업 단위가 끝나면 PR 을 올린다

**"작업 단위" 의 정의** (셋 중 하나):

1. 사용자가 "PR 올려" / "머지 준비" 등으로 명시.
2. 한 주제·여러 파일에 걸친 **응집된 변경 묶음** 이 자연스러운 단락에 도달. *판정 기준*: diff 만 떼어 본 reviewer 가 "이건 한 PR 이군" 이라고 즉시 읽히는가.
3. (예외) 단일 파일 typo · 한 줄 수정 · 임시 탐색은 PR 단위가 **아니다**. 결과만 보고하고 commit·push 는 보류.

**절차** (자동화는 `pr-create` 스킬):

```
1. git status && git diff --stat        # 변경 범위 확인
2. git switch -c {feat,fix,chore}-<slug>  # main 직접 push 금지, slug 에 / 금지
3. git commit                           # 의미 단위로 분할
4. git push -u origin <branch>
5. gh pr create                         # title `[<slug>] <description>`
```

**불변량**:

- **`main` (또는 default branch) 직접 push 금지.** 항상 feature branch 경유. `check-uncommitted` Stop 훅이 default branch 에 변경이 쌓이면 알린다.
- **비대화형 실행은 push 에서 멈춘다.** `ask` 티어는 사람이 답해야 통과하므로 `claude -p` 와 CI 에서는 push 가 항상 거부된다. 설계상 그렇다 — 자동화에서 PR 까지 가야 한다면 그 프로젝트가 `Bash(git push:*)` 를 `allow` 로 올리는 결정을 내려야 한다.
- **Force push 금지.** `git push --force` / `-f` 는 `settings.json` 의 `deny`.
- **Branch 이름 = slug**, `{feat,fix,chore}-<short>` 형식. `/` 금지 — worktree·디렉터리 이름으로 그대로 쓰이는 경우가 흔하다.
- **PR title** 은 `[<slug>] <description>`, 70자 이하. slug 가 이미 type prefix 를 포함하므로 description 에 `feat:` 를 다시 붙이지 않는다.
- **PR description** 은 motivation → changes → verification → notes. 한·영 혼용 — 한국인 reviewer 가 1분 안에 의도를 잡게 쓰되 경로·명령·키워드는 영어 그대로.

---

## R2 — Commit

- 제목은 **동사로 시작** 하는 1행. 본문에는 *what* 이 아니라 *why*.
  <!-- 글자 수 상한은 뺐다. 하네스 있고 없고를 6회씩 재보니 양쪽 다 6/6 이라
       이 규칙이 만든 차이가 0 이었다. 모델이 원래 짧게 쓴다. 다시 넣으려면
       먼저 재고, 차이가 있을 때만 넣는다. → docs/agent-layer.md §4b -->
- Commit 과 PR description 은 다른 축이다. Commit 은 *그 changeset 의 why*, PR 은 *작업 단위 전체의 서사*.
- **AI 귀속 금지.** `Co-Authored-By: Claude` trailer 도, `🤖 Generated with Claude Code` footer 도 남기지 않는다. `settings.json` 의 `includeCoAuthoredBy: false` 가 내장 부착을 끄고, PreToolUse 훅 `ai-attribution-guard` 가 명령 단계에서 차단한다. `CLAUDE.md` 파일명·`.claude/` 디렉터리·`anthropic` API 백엔드 같은 정당한 참조는 귀속이 아니므로 그대로 둔다.

---

## R3 — Harness gap detection

`CLAUDE.md` §5 의 surface 정책을 rule 로 고정한다. **작업 중 발견한 harness 결함은 조용히 우회하지 않고 제안한다.**

**채택 criterion — 둘 다 충족해야 rule 이 된다**:

- **≥ 2회 발생.** 단발 case 는 rule 이 아니다. PR description 이나 세션 메모로 남긴다.
- **Project-agnostic.** *다른* 프로젝트 (다른 도메인·다른 스택) 에서도 별 수정 없이 그대로 적용되는가. ✅ "머지 후 브랜치 정리 패턴" / ❌ "이 서비스의 재시도 임계값 3회".

둘 중 하나라도 미충족이면 프로젝트 문서로 보내고, *다음에* 같은 패턴이 또 나오면 그때 승격한다. 이 보수성은 의도된 것이다.

**Harness 변경은 기능 변경과 별도 PR.** 섞으면 리뷰어가 둘 다 제대로 못 본다.

---

## R3.1 — 머지 직후 harness retro

R3 이 *작업 도중* 의 즉시 보고라면, R3.1 은 *작업 단위가 끝난 시점* 의 체계적 회고다. 둘 다 돈다.

**Trigger**: PR 머지 직후.

**절차**: 그 작업에서 (a) 어디서 수동 보정이 있었나, (b) 어디서 같은 명령을 반복했나, (c) 사용자가 어디서 방향을 돌렸나, (d) 어떤 단계가 명시되지 않은 가정에 기댔나 — 를 훑고, R3 의 criterion 으로 거른 뒤, 남은 후보를 before/after 패치와 함께 제시한다.

**Gap 없음 case**: "본 작업 회고: 신규 harness gap 없음" 을 **한 줄로 명시 보고**한다. Silent skip 금지 — gap 이 0 이라는 명시적 신호 자체가 retro 가 돌았다는 증거다. Gap 없는 turn 이 절대 다수인 것이 정상이다.

---

## R4 — PR 직전 self-check

- [ ] `git status` — 누락 파일 없음, 의도치 않은 artifact 없음.
- [ ] Commit message 가 동사로 시작하고 body 에 why 가 있다.
- [ ] `git log --format='%B' origin/<default>..HEAD` 에 AI 귀속 문구가 없다 (R2).
- [ ] PR title 이 `[<slug>] <description>` 형식이고 70자 이하.
- [ ] PR description 이 motivation → changes → verification → notes 를 담는다.
- [ ] 검증을 *실제로 돌린* 결과를 description 의 verification 에 적었다 — "돌 것 같다" 는 검증이 아니다 (`CLAUDE.md` §4).

---

## R5 — Plan 단계 진단 검증

**Plan / Explore 단계에서 나온 수치·구조 claim 은 plan 에 박기 전에 1줄로 검증한다.** 빠른 `grep`/`wc` 진단을 최종 설계의 근거로 그대로 쓰면, 실제 구조와 어긋난 진단이 계획에 굳는다. 구현 단계에 가서야 드러나면 재설계 비용이 든다.

**대상**: "N개의 X 가 있다", "A 와 B 가 70% 중복", "정의가 두 곳에 있다", "line N 이 Y 다" 같은 claim.

**규약**:

1. 핵심 claim 1–3개에 대해 *명령과 그 출력을 함께* plan 에 적는다. `grep -c '^class ' foo.py → 10` 형태. "탐색 결과 10개라고 함" 은 근거가 아니다.
2. Claim 과 실제가 다르면 plan 을 다시 짠다. 부정확한 진단 위에 세운 설계는 2차 문제로 번진다.
3. 검증 자체를 과하게 하지 않는다. 탐색 결과 전체를 재확인할 필요는 없다 — 설계를 좌우하는 claim 만.

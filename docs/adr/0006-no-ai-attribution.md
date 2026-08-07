# ADR-0006: 커밋·PR 에 AI 귀속을 남기지 않는다

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

Claude Code 는 기본적으로 커밋에 `Co-Authored-By: Claude <noreply@anthropic.com>` trailer 를 붙이고, PR 본문에 `🤖 Generated with [Claude Code]` footer 를 넣는다. 두 동작의 스위치가 다르다 — 전자는 `settings.json` 의 `includeCoAuthoredBy`, 후자는 모델이 본문을 작성하는 시점의 판단이다.

참조 하네스 두 곳의 방침이 정반대였다. 하나는 `includeCoAuthoredBy: true` 로 두고 워크플로 규약에서 trailer 를 *의무화* 했고, 다른 하나는 `false` 로 끄고 PreToolUse 훅으로 명령 단계에서 차단했다. 후자를 쓰는 사용자가 본 저장소의 사용자다.

방침이 갈리는 항목이므로, 기록해 두지 않으면 다음에 참조 하네스를 다시 볼 때 "저쪽은 true 던데" 로 되돌려질 수 있다.

## Decision

**커밋 메시지·PR·이슈 어디에도 AI 를 author 나 co-author 로 남기지 않는다.**

세 겹으로 건다.

1. `plugins/harness-core/declarative/settings-fragment.json` 의 `includeCoAuthoredBy: false` — 내장 부착을 끈다. 컨슈머가 이미 이 키를 갖고 있으면 값을 바꾸지 않고 경고만 낸다 (설치기가 남의 명시적 설정을 뒤집지 않는다).
2. `ai-attribution-guard` 훅 — 커밋·PR·이슈를 작성하는 Bash 명령에서 trailer·footer·로봇 이모지를 차단한다. 명령 단계에서 걸리므로 `--no-verify` 로도 우회되지 않는다.
3. `rules/harness/workflow.md` R2 — 규약으로 명시. 가드가 없는 경로(예: 하네스 저장소 자신)에서는 이것만 남는다.

정당한 참조는 귀속이 아니므로 그대로 둔다: `CLAUDE.md` 라는 파일명, `.claude/` 디렉터리, `anthropic` API 백엔드, 산문 속 모델 이름. 사람 co-author trailer 도 물론 통과한다.

## Consequences

- 참조 하네스 하나와 정반대다. 그 저장소를 다시 참고할 때 이 divergence 를 발견하면 본 ADR 을 근거로 유지한다.
- 본 저장소는 자기 자신에게 설치할 수 없으므로(ADR-0001) 여기서는 훅의 보호를 받지 못한다. `CLAUDE.md` §6 의 규율로만 지킨다.
- `includeCoAuthoredBy` 를 이미 `true` 로 둔 컨슈머는 설치 후에도 `true` 로 남는다. 설치기가 경고를 내지만 자동으로 바꾸지 않는다 — 그 값이 명시적 선택일 수 있기 때문이다.
- 훅이 오탐을 낼 수 있는 지점이 하나 있다: 커밋 메시지 안에서 이 정책 자체를 인용하는 경우("drop the Co-Authored-By: Claude trailer"). 실제로 걸리면 문구를 바꿔 쓰면 된다 — 정책 문구를 커밋 제목에 넣을 이유가 거의 없다.

## Alternatives considered

- **`includeCoAuthoredBy: false` 만** — 내장 trailer 는 막지만 모델이 직접 쓴 footer 는 못 막는다. 실제로 새는 경로는 후자다.
- **commit-msg 단계 스트리퍼** — `--no-verify` 로 우회되고, git hook 설치 상태가 환경마다 비대칭이다. 보조망으로는 유효하나 주 방어선이 될 수 없다.
- **규약만, 가드 없음** — 기본 동작이 반대 방향이라 규약만으로는 반복해서 샌다.

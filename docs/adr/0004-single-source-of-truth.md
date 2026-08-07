# ADR-0004: `docs/agent-layer.md` 가 단일 SOT 이고, 설치되는 index 파일은 만들지 않는다

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

참조 하네스 하나는 `.claude/README.md` 에 계층 다이어그램과 rule·skill·agent·hook 인벤토리를 유지하고, 그 문서 안에 "무엇이든 추가하면 이 index 를 갱신한다" 는 자기 유지 규칙(§8)까지 두고 있었다. 그럼에도 탐색 시점에 확인된 drift 가 최소 두 건이었다 — index 가 `settings.json` 의 실제 값과 다른 값을 적고 있었고, 훅 목록에서 실제 등록된 훅 하나가 빠져 있었다.

같은 저장소가 별도 로드맵 문서를 두었다가 drift 를 이유로 삭제한 이력도 있다.

교훈은 "규칙을 더 강하게 쓰라" 가 아니다. **손으로 유지하는 인벤토리는 규칙이 있어도 drift 한다**, 그리고 drift 한 index 는 없는 index 보다 나쁘다 — 읽는 쪽이 그것을 믿기 때문이다.

## Decision

**`docs/agent-layer.md` 가 하네스의 범위·인벤토리·backlog 에 대한 유일한 출처다.** 이 셋을 바꾸는 변경은 이 파일만 갱신한다. README 나 별도 로드맵에 같은 내용을 복제하지 않는다.

**컨슈머에 설치되는 index 파일(`.claude/README.md` 류)은 만들지 않는다.** 컨슈머는 파일을 받고, 인벤토리는 하네스 저장소 한 곳에 있다.

**기계로 확인 가능한 것은 문서에 적는 대신 검증한다.**

- 설치되는 파일 목록은 harnessctl 의 계획 코드 한 곳에서 나온다 — 문서에 옮겨 적을 목록이 없다.
- 배포되는 모든 스크립트가 실행 가능한지, 모든 fragment·매니페스트가 유효한 JSON 인지, `hooks.json` 의 모든 등록이 실재하는 파일로 해석되는지는 `scripts/verify-install.sh` 가 CI 에서 확인한다. *(ADR-0008 이후 `templates.txt` 는 없다 — tier 는 harnessctl 의 계획 코드가 선언한다.)*

즉 `agent-layer.md` 에는 **기계가 확인할 수 없는 것** 만 남긴다: 왜 이 하네스가 존재하는지, 무엇이 범위 밖인지, 다음에 무엇을 만들지, 왜 어떤 것을 안 만들기로 했는지.

## Consequences

- `agent-layer.md` 의 §3 인벤토리 수치(훅 6, 스킬 4 등)는 여전히 손으로 유지되고 여전히 drift 할 수 있다. 다만 그것이 틀려도 잃는 것은 요약의 정확도일 뿐, 설치 동작이 아니다.
- 컨슈머가 "이 하네스가 뭘 설치했나" 를 알려면 `.claude/harness-manifest.json` 을 보거나 하네스 저장소를 봐야 한다. manifest 는 기계 생성이므로 언제나 정확하다.
- 새 기여자는 README 가 아니라 `agent-layer.md` 로 안내된다.

## Alternatives considered

- **자기 유지 규칙을 명시한 index 파일** — 참조 하네스가 정확히 이것을 했고 drift 했다.
- **index 자동 생성 (스크립트로 트리에서 만들어 커밋)** — drift 는 막지만, 생성된 파일이 트리를 다시 서술할 뿐이라 트리를 직접 보는 것보다 나은 점이 없다.
- **README 를 SOT 로** — README 는 컨슈머용 quick-start 다. 청중이 다르면 문서도 다르다.

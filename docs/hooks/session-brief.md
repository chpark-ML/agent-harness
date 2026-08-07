# session-brief

세션 시작 시점에 압축된 저장소 상태 브리핑을 컨텍스트로 주입한다.

## 동작

`SessionStart` 이벤트, matcher `startup|resume|clear|compact` 로 등록된다 ([`hooks.json`](../../plugins/harness-core/hooks/hooks.json)).

**Informational — 항상 exit 0 이고 세션을 막지 않는다.** 이 훅의 stdout 은 세션 컨텍스트가 된다.

출력 순서:

1. `[session-brief] repo 상태` 헤더
2. `- branch:` — `git branch --show-current`. 비어 있으면 `(detached: <short sha>)` 로 대체
3. `- upstream(<ref>): ahead N / behind M` — upstream 이 설정되어 있고 **ahead·behind 가 둘 다 0 이 아닐 때만**
4. `- 미커밋 변경: N 파일` — `git status --porcelain | wc -l`, **0 이 아닐 때만**
5. `- 최근 커밋:` + `git log -5 --pretty='  %h %s'`

먼저 `git rev-parse --show-toplevel` 로 저장소 루트를 한 번 구하고 이후 모든 호출을 `git -C "$root"` 로 보낸다 — 세션이 하위 디렉터리에서 시작될 수 있고, 형제 Stop 훅 [check-uncommitted](check-uncommitted.md) 와 방식을 맞추기 위해서다. 저장소 밖이면 아무것도 출력하지 않고 exit 0.

`jq` 를 쓰지 않는다 — stdin 을 파싱하지 않고 `git` 만 호출하므로, 다른 pre-tool-use 훅들과 달리 jq self-disable 분기가 없다.

**출력 예산은 10줄이다.** 이 훅은 모든 start·resume·clear·compact 마다 돌기 때문에, 여기서의 장황함은 프로젝트 수명 내내 매 세션에 부과되는 세금이다. 그래서 "모델이 어차피 tool call 한 번을 써서 알아낼 사실" 만 담는다.

## 통과하는 것

침묵하는 조건이 이 훅의 핵심 성질이다. 조건부 줄들은 기본값일 때 아예 나오지 않는다.

- **git 저장소가 아니면 완전 침묵** — 출력 0바이트, exit 0.
- **upstream 이 없으면 upstream 줄 없음.** 있어도 ahead·behind 가 모두 0 이면 생략한다. "동기화됨" 은 정보가 아니다.
- **작업 트리가 깨끗하면 미커밋 줄 없음.**
- **detached HEAD 도 정상 출력** — 실패로 취급하지 않고 `(detached: <sha>)` 로 라벨링한다.

## 우회

차단하지 않으므로 우회할 것이 없다. 등록은 `settings.json` 이 아니라 플러그인의 `hooks.json` 에 있으므로 `settings.json` 을 편집해서는 끌 수 없고, 플러그인 단위로 (`/plugin` 에서 `harness-core` 비활성화) 끄는 것이 유일한 방법이다 — 나머지 다섯 훅도 함께 꺼진다. 브리핑 내용이 문제라면 하네스 저장소에서 스크립트를 고칠 것.

## 한계

- **10줄 예산에 여유가 없다.** 최악의 경우(upstream 차이 + 미커밋 변경 + 커밋 5개)가 **정확히 10줄** 이다. 무언가를 넣으려면 무언가를 빼야 한다. 이건 이제 문서상의 당부가 아니라 verifier 가 그 최악 케이스를 직접 렌더링해 단언한다 — 필드를 늘리면 테스트가 깨진다.
- **커밋이 없는 저장소에서 `- 최근 커밋:` 이 빈 채로 남는다.** `git log` 실패는 `2>/dev/null` 로 삼켜지지만 헤더 줄은 이미 출력된 뒤다.
- **`wc -l` 은 파일 수를 센다** — 변경 줄 수가 아니다. 한 파일의 대규모 수정과 한 줄 오타가 똑같이 `1 파일` 이다.
- **submodule·worktree 를 구분하지 않는다.** 현재 트리 기준의 값만 보고한다.

## 검증

[`plugins/harness-core/scripts/verify-session-brief.sh`](../../plugins/harness-core/scripts/verify-session-brief.sh) — 19 케이스 (저장소 밖 2, clean repo 5, 출력 예산 1, dirty repo 3, detached HEAD 2, **upstream 과 예산 최악 케이스 4**). "나오지 않아야 할 줄" 을 검사하는 `expect_absent` 헬퍼는 [`_verify-lib.sh`](../../plugins/harness-core/scripts/_verify-lib.sh) 에 있다 — 이 파일이 두 곳, protected-paths 가 한 곳에서 쓴다.

마지막 4건은 bare 저장소를 remote 로 붙이고 한 커밋 앞선 dirty 트리를 만든 fixture 로 돈다. upstream 블록에 도달하는 유일한 fixture 이자 (그전까지는 이 코드 경로가 아예 실행되지 않았다) 모든 선택적 줄이 동시에 렌더링되는 예산 최악 케이스다.

```
bash plugins/harness-core/scripts/verify-session-brief.sh
```

## 관련

- 훅 스크립트: [`plugins/harness-core/hooks/session-brief.sh`](../../plugins/harness-core/hooks/session-brief.sh) (consumer 트리에는 설치되지 않는다 — 플러그인 캐시에서 로드된다)
- 등록 위치: [`plugins/harness-core/hooks/hooks.json`](../../plugins/harness-core/hooks/hooks.json)
- 대칭을 이루는 informational 훅: [check-uncommitted](check-uncommitted.md) — 이쪽은 턴 끝에서 같은 `git status --porcelain` 카운트를 보되, default branch 에서만 말을 한다. 두 훅 모두 toplevel 을 구해 `git -C "$root"` 로 git 을 호출한다.

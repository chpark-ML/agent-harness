# check-uncommitted

턴이 끝날 때, default branch 에 작업이 쌓이고 있으면 알린다.

## 동작

`Stop` 이벤트, matcher `""` (모든 Stop) 로 등록된다 ([`hooks.json`](../../plugins/harness-core/hooks/hooks.json)).

**Informational — 항상 exit 0 이고 턴을 막지 않는다.** 알림 한 줄을 stdout 으로 낸다.

말을 하기까지 네 관문을 모두 통과해야 한다.

1. `git rev-parse --show-toplevel` 성공 — 저장소 밖이면 exit 0.
2. `git -C "$root" branch --show-current` 가 비어 있지 않음 — detached HEAD 면 exit 0.
3. **현재 브랜치가 default branch** — 아니면 exit 0.
4. `git status --porcelain | wc -l` 이 0 초과 — 깨끗하면 exit 0.

Default branch 판정은 `git symbolic-ref refs/remotes/origin/HEAD` 에서 remote 가 보고하는 이름을 쓴다. remote HEAD 가 없으면 현재 브랜치가 `main` 또는 `master` 인 경우에만 그것을 default 로 간주하고, 그 외에는 exit 0 으로 물러난다. remote 도 없고 이름도 관례를 벗어나면 판단하지 않는 쪽을 택한다.

`jq` 를 쓰지 않는다 — stdin 을 파싱하지 않고 `git` 만 호출하므로 jq self-disable 분기가 없다.

**default branch 에서만 발화하는 것이 설계의 전부다.** 조건 없는 "미커밋 변경이 있습니다" 는 모든 세션의 모든 턴에서 울리고 하루 안에 무시당한다. 그러면 guard rail 이 아니라 rail 모양 주석이 달린 소음이다.

## 통과하는 것

verifier 가 "차단" 보다 "침묵" 을 더 많이 검사한다. 아래는 모두 의도적으로 조용하다.

- **feature branch 에서의 미커밋 변경** — 여기가 변경이 있어야 할 자리다. 알릴 이유가 없다.
- **default branch 이지만 깨끗한 트리.**
- **detached HEAD** — 브랜치 이름이 없으면 브랜치 규약을 논할 수 없다.
- **git 저장소 밖.**
- **remote HEAD 도 없고 브랜치가 `main`/`master` 도 아닌 경우** — default 를 추측하지 않는다.
- **default 가 `trunk` 인 저장소에서 `main` 이라는 이름의 브랜치** — 이름 fallback 이라면 말을 했겠지만 remote 조회가 이긴다. `main` 이 여기서는 feature branch 이므로 침묵이 옳다.

## 우회

차단하지 않으므로 우회할 것이 없다. 메시지 자체가 무시해도 되는 경우를 명시한다 — 단발 typo 나 탐색이면 그냥 두라고 적혀 있다. 알림이 맞는 상황이면 `{feat,fix,chore}-<slug>` 브랜치로 옮기는 것이 정해진 대응이다 ([`pr-create`](../../plugins/harness-core/skills/pr-create/SKILL.md) 스킬이 자동화 — 이 훅과 같은 플러그인으로 배포된다).

## 한계

- **`wc -l` 은 파일 수를 센다** — 변경 규모가 아니다. `1 건` 이 한 글자 수정일 수도, 파일 전체 재작성일 수도 있다.
- **untracked 파일도 카운트에 들어간다.** `--porcelain` 기본 출력에 포함되므로, 빌드 산출물이 무시되지 않은 채 널려 있으면 숫자가 부풀고 알림이 반복된다.
- **매 턴 발화한다.** 조건이 유지되는 동안 억제 장치가 없어 같은 문구가 턴마다 반복된다. default branch 한정이라는 게이트 하나로 소음을 막고 있다.
- **`origin` 이라는 이름을 가정한다.** remote 가 다른 이름이면 `refs/remotes/origin/HEAD` 조회가 실패하고 `main`/`master` fallback 으로 떨어진다.
- **작업이 리뷰 단위인지 판정하지 않는다.** 그 판단은 규칙 R1 이 사람·모델에게 맡긴 몫이고, 훅은 사실만 보고한다.

## 검증

[`plugins/harness-core/scripts/verify-check-uncommitted.sh`](../../plugins/harness-core/scripts/verify-check-uncommitted.sh) — 16 케이스 (침묵 5, `main` 발화 4, `master` 발화 2, **remote 가 정한 default 발화 2**, 카운트 추적 1). 침묵 케이스는 전용 `quiet_case` 헬퍼로 exit 0 과 **빈 stdout** 을 함께 검사한다. verifier 헤더가 밝히듯 load-bearing 한 성질은 "무엇을 차단하는가" 가 아니라 "무엇에 대해 입을 다무는가" 다.

`origin/HEAD` 를 네트워크 없이 `symbolic-ref` 로 직접 세운 fixture 두 개가 추가되어, 실제 clone 에서 늘 실행되는 조회 경로가 처음으로 검증된다 (그전에는 모든 fixture 가 remote 없는 `git init` 이라 `main`/`master` fallback 만 돌았다). 둘 중 값을 하는 쪽은 default 가 `trunk` 인데 브랜치 이름이 `main` 인 케이스다 — 이름 fallback 과 remote 조회가 정면으로 어긋나는 유일한 배치이고, remote 가 이겨야 한다.

```
bash plugins/harness-core/scripts/verify-check-uncommitted.sh
```

## 관련

- 훅 스크립트: [`plugins/harness-core/hooks/check-uncommitted.sh`](../../plugins/harness-core/hooks/check-uncommitted.sh) (consumer 트리에는 설치되지 않는다 — 플러그인 캐시에서 로드된다)
- 등록 위치: [`plugins/harness-core/hooks/hooks.json`](../../plugins/harness-core/hooks/hooks.json)
- 이 훅이 집행을 돕는 규칙 R1 ("`main` 직접 push 금지", 작업 단위의 정의): [`declarative/rules/core/workflow.md`](../../plugins/harness-core/declarative/rules/core/workflow.md) — 훅과 달리 rule 은 플러그인이 나르지 못해 `harnessctl init` 이 프로젝트의 `.claude/rules/` 에 설치한다.
- 대칭을 이루는 informational 훅: [session-brief](session-brief.md) — 세션 시작 시점에 같은 `git status --porcelain` 카운트를 브랜치와 무관하게 보고한다.

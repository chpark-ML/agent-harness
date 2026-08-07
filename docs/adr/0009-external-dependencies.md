# ADR-0009: 외부 플러그인은 프로파일의 dependency 로 들이고, 스킬 충돌은 하나를 골라 푼다

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

[ADR-0008](0008-plugin-declarative-split.md) 로 프로파일이 플러그인이 되면서 `dependencies` 가 열렸다. 남이 유지보수하는 자산을 매니페스트 한 줄로 들일 수 있다 — `{name, version, marketplace}` 형태이고 `version` 은 semver 범위를 받는다. 다른 marketplace 를 가리키려면 대상 marketplace 의 `marketplace.json` 에 `allowCrossMarketplaceDependenciesOn` 이 있어야 하고, 우리 것에는 `claude-plugins-official` 이 들어 있다.

공식 marketplace 에서 확인한 것 둘.

- **Superpowers** (source `obra/superpowers`, SHA 고정) — 스킬 14개: `brainstorming`, `dispatching-parallel-agents`, `executing-plans`, `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `using-superpowers`, `verification-before-completion`, `writing-plans`, `writing-skills`.
- **언어 서버 플러그인 14종** — `pyright-lsp`, `typescript-lsp` 등. **LSP 플러그인은 서버 바이너리를 번들하지 않는다.**

여기서 규칙 하나가 걸린다. [ADR-0001](0001-harness-scope.md) 의 편입 기준은 "다른 도메인·다른 스택의 프로젝트에 그대로 설치해도 말이 되는가" 다. 그 기준을 문자 그대로 대면 pyright 는 파이썬 프로젝트에서만 말이 되므로 들어올 수 없다.

비용 구조도 자산마다 다르다. **스킬은 안 써도 비용이다** — description 이 라우팅을 위해 항상 로드되므로, 쓰지 않는 스킬 14개는 컨텍스트 14인분이다. **LSP 는 그렇지 않다.** 언어 서버는 도구가 호출될 때 동작하고 상시 로드되는 텍스트가 없다.

## Decision

**1. Superpowers 를 `harness-dev` 의 dependency 로 채택한다.** `core` 가 아니라 `dev` 인 이유는 위의 비용 구조다 — 연구 프로파일만 쓰는 사용자에게 `test-driven-development` 와 `requesting-code-review` 의 description 을 매 턴 로드시킬 근거가 없다.

**2. 스킬이 겹치면 하나를 고른다. 둘 다 배포하지 않는다.** 한 트리거를 두 스킬이 다투는 상태는 우리 negative-routing 규율이 막으려고 존재하는 바로 그 실패다 — 라우팅이 비결정적이 되고, 어느 쪽이 이겼는지 사용자에게 보이지 않는다. 겹침은 "둘 다 있으니 풍성하다" 가 아니라 결함으로 취급한다.

관측한 겹침은 넷으로 갈린다.

| 구분 | Superpowers | 우리 것 | 판정 |
|---|---|---|---|
| 직접 충돌 | `finishing-a-development-branch` | `pr-create` | **우리 것을 쓴다** |
| 직접 충돌 | `requesting-code-review` · `receiving-code-review` | `pr-review` | **우리 것을 쓴다** |
| 원칙 중복 | `test-driven-development` · `verification-before-completion` | `CLAUDE.md` §4 Goal-Driven Execution | 공존. 원칙은 상시 지침, 스킬은 그 원칙의 절차판이다 |
| backlog 해소 | `using-git-worktrees` | (없음 — backlog ⏳) | 채택. 우리가 만들 필요가 없어졌다 |
| 순수 추가 | 나머지 8개 | — | 그대로 받는다 |

직접 충돌 둘에서 우리 것을 고르는 이유는 품질이 아니라 **결합** 이다. `pr-create` 는 `rules/harness/workflow.md` 의 R1–R4 를, `pr-review` 는 `rules/harness/dev/review.md` 의 체크리스트를 실행한다. 범용 스킬은 그 파일들의 존재를 모른다. 대신 이 선택은 우리 쪽 description 에 **superpowers 스킬 이름을 박은 negative routing** 으로 집행한다 — dependency 의 스킬은 우리가 지울 수 없으므로, 라우팅을 결정적으로 만드는 유일한 수단이 우리 description 이다.

**3. 언어 프로파일 `harness-python` · `harness-typescript` 를 만든다.** 각각 `harness-core` + 공식 LSP 하나를 dependency 로 갖는 매니페스트 한 장이고, 파일은 없다. 다른 언어는 같은 모양으로 `gopls-lsp` · `rust-analyzer-lsp` 등을 추가하면 된다. 서버 바이너리는 사용자가 설치하며 `harnessctl doctor` 가 PATH 를 확인하고 설치 명령을 알려준다.

**4. ADR-0001 의 project-agnostic 기준은 `core` 를 규율하지, opt-in 프로파일을 규율하지 않는다.** 이것이 3번을 떠받치는 논거다. 기준을 프로파일까지 확장하면 `research` 도 `dev` 도 들어올 수 없고, 그러면 모듈 구조 자체가 무의미해진다. 모듈이 존재하는 이유가 바로 "모두에게 맞지는 않는 것" 을 담는 것이다. 규칙은 이렇게 읽는다 — **`core` 는 아무 프로젝트에나 설치해도 말이 돼야 하고, 프로파일은 고른 사람에게 말이 되면 된다.**

정직하게 기록해 둘 것: 이 계획의 첫 초안은 pyright 를 "언어 특화라 ADR-0001 위반" 이라며 뺐다. 두 규칙을 뒤섞은 오류다. 같은 논리라면 연구 노트 규율도 빠져야 했는데 그것은 빼지 않았으니, 기준을 일관되게 적용한 것도 아니었다.

**5. `ml` · `review` 프로파일은 보류한다.** 발생 0회다. `CLAUDE.md` §7 이 요구하는 "실제로 두 번 이상 발생한 문제" 에 미달하므로 `docs/agent-layer.md` 의 backlog 에 둔다.


### 갱신 (2026-08-06, Superpowers 설치 후 실측)

**"충돌 2건" 은 실제로 충돌이 아니었다.** 설치 전에는 스킬 이름만 보고 판정했고, 본문을 읽으니 생애주기의 다른 지점에 있었다.

| Superpowers | 무엇을 하나 | 우리 | 무엇을 하나 |
|---|---|---|---|
| `requesting-code-review` | `BASE_SHA..HEAD_SHA` 커밋 범위를 서브에이전트에 보내는 **머지 전 자기 검토**. forge 를 건드리지 않는다 | `pr-review` | **이미 열린 PR** 을 `gh pr diff` 로 읽고 이 저장소 체크리스트로 훑는다 |
| `finishing-a-development-branch` | 통합 방식 선택 + 정리. Option 2 가 push 후 PR 생성이고, 본문이 *"following the repo's PR template and conventions if present"* 라고 명시한다 | `pr-create` | 그 "repo's conventions" 자체 — slug 형식, `[<slug>] title`, 한·영 body, AI 귀속 금지 |
| `receiving-code-review` | 받은 리뷰에 대응하는 법 | — | 없음 |

입력도 출력도 다르다. `finishing-a-development-branch` 는 오히려 우리 쪽에 **위임하도록 쓰여 있다**.

> *2026-08-07 실측*: 이 구분축이 선언에 그치지 않는다는 것을 확인했다. `pr-review` 12/12, `pr-create` 12/12 이고, 음성 케이스가 실제로 이름 박아둔 이웃으로 갔다 — 커밋 범위 검토는 `superpowers:requesting-code-review`(3회씩 반복해도 안정), 리뷰 대응은 `receiving-code-review`, PR 생성은 `pr-create`. **다만 반대 방향은 성립하지 않았다**: "이 PR 머지하고 브랜치 정리해줘" 는 `finishing-a-development-branch` 가 맡을 자리인데 세 번 다 `Bash` 로 갔다. 우리가 위임한 쪽이 받지 않는 구간이 있다는 뜻이고, 아래 Consequences 의 "남의 저장소에 의존한다" 가 추상론이 아님을 보여준다. 방법과 수치는 [agent-layer §4b](../agent-layer.md).

**그래서 remedy 가 바뀐다.** "trigger 가 겹치는 두 스킬은 하나를 고른다" 는 규칙은 유효하지만, 여기서 겹친 것은 *스킬* 이 아니라 *트리거 문구* ("리뷰해줘") 였다. 삭제 대신 **구분축을 생애주기 단계로 다시 그어** description 에 박았다 — PR 이 열려 있는가, 아직 커밋 범위인가.

이 정정 자체가 규칙 하나를 낳는다: **외부 스킬과의 충돌은 이름이 아니라 본문으로 판정한다.** 설치 전에 이름만으로 내린 판정은 두 번 다 틀렸다 (여기, 그리고 초안의 pyright 배제).

> *2026-08-07 추가*: 세 번째로 틀렸다 — `skill-creator` 를 이름만 보고 "`writing-skills` 와 겹치니 하나만" 으로 판정했는데, 본문은 스킬 작성기가 아니라 **평가 하네스** 였다. 셋이면 규칙이 지켜지지 않는다는 뜻이므로 [ADR-0011](0011-ecosystem-survey.md) 에서 판정 절차 자체를 다룬다.

## Consequences

- `harness-dev` 를 설치하면 스킬이 우리 것 2개(`pr-create` · `pr-review`)가 아니라 16개 로드된다. 컨텍스트 비용이 실제로 늘고, 그것이 Superpowers 를 `core` 에 넣지 않는 이유다.
- **`pr-create` 와 `pr-review` 의 description 은 superpowers 쪽 대응 스킬을 이름으로 지목해야 한다.** 지목하지 않으면 2번 결정이 문서상의 선언으로만 남고 런타임 라우팅은 여전히 다툰다.
- 우리 라우팅 규율이 남의 저장소에 의존하게 된다. Superpowers 가 스킬을 추가하면 새 충돌이 생길 수 있고, 그때 알아차리는 방법은 지금 정기 점검밖에 없다.
- `pr-create` 는 `harness-core` 에 있고 Superpowers 는 `harness-dev` 의 dependency 이므로, `core` 만 설치한 사용자에게는 이 충돌이 존재하지 않는다. 충돌은 `dev` 를 고른 순간 생긴다.
- 언어 프로파일은 설치해도 아무 파일이 생기지 않는다. 사용자가 보기에 "설치했는데 아무 일도 없는" 상태이며, 서버 바이너리가 없으면 실제로 아무 일도 일어나지 않는다. `harnessctl doctor` 가 이 침묵을 진단으로 바꾸는 유일한 장치다.
- cross-marketplace dependency 는 `claude-plugins-official` 이 살아 있는 동안만 해석된다. 그 marketplace 가 사라지거나 플러그인이 이름을 바꾸면 `harness-dev` · `harness-python` · `harness-typescript` 설치가 깨진다. 우리 저장소만으로는 막을 수 없는 실패 모드다.
- `using-git-worktrees` 를 받으면서 backlog 의 worktree 도우미 항목이 해소된다. 우리 것을 만들지 않는 쪽이 항상 더 싸다.

## Alternatives considered

- **Superpowers 를 `core` 에 넣는다** — 모든 컨슈머가 받지만, 연구 전용 사용자가 쓰지 않는 스킬 14개의 description 을 매 턴 로드한다.
- **Superpowers 스킬을 우리 저장소에 vendoring** — 충돌을 우리가 직접 잘라낼 수 있으나 업스트림 업데이트를 손으로 따라가야 하고, dependency 가 해결하는 문제를 되돌린다.
- **충돌하는 스킬을 둘 다 배포하고 라우팅은 모델에 맡긴다** — 겉으로는 유연하지만 정확히 negative routing 이 막으려는 실패다. 어느 쪽이 이겼는지 보이지 않는 비결정성은 디버깅이 불가능하다.
- **`pr-create` · `pr-review` 를 버리고 Superpowers 쪽을 쓴다** — 유지보수가 줄지만, 두 스킬은 우리 rule 파일을 실행하는 물건이라 rule 이 집행되지 않게 된다.
- **언어 프로파일 없이 문서로만 안내** ("파이썬이면 `pyright-lsp` 를 직접 설치하세요") — 매니페스트 한 장 값어치의 편의를 사용자에게 떠넘기고, `doctor` 가 무엇을 점검해야 하는지도 알 수 없게 된다.
- **`ml` · `review` 프로파일을 지금 만든다** — 발생 0회에 "있으면 좋을 것 같아서" 추가하는 모양이고, `CLAUDE.md` §7 이 정확히 금지하는 것이다.

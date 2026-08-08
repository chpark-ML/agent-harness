# 엔지니어링 층 — context · loop · graph, 그리고 하네스가 서는 자리

에이전트 시스템을 만들 때 다루는 문제는 하나가 아니다. 업계가 수렴 중인 구분은 **층**이고, 층은 서로를 대체하지 않고 합성된다.

| 층 | 무엇을 통제하나 |
|---|---|
| prompt engineering | 모델의 단일 응답 |
| **context engineering** | **모델이 무엇을 보는가** |
| **loop engineering** | **에이전트 한 개의 행동 사이클** |
| **graph engineering** | **이종 노드 간 위상** — 누가 존재하고, 어떤 전이가 허용되며, 런타임 작업 그래프가 어떻게 형성·변형되나 |

출처: [TrueFoundry, *Graph Engineering: An Enterprise Guide*](https://www.truefoundry.com/blog/graph-engineering-enterprise-guide). 같은 글의 표현이 이 문서의 요지를 대신한다 — **"좋은 루프를 가진 나쁜 그래프는 신뢰할 수 없는 직원들의 조직도이고, 잘 설계된 그래프 안의 다듬지 않은 루프는 규모에서 무너진다."**

**본 문서는 설계 노트다. 컨슈머에게 배포되지 않으므로 상시 컨텍스트 비용은 0 이다.** 범위·인벤토리·backlog 의 SOT 는 [`agent-layer.md`](agent-layer.md), 생태계 판정은 그 §3b 다. 여기는 *어떤 레버가 어디 있고, 남들은 어떻게 하며, 우리는 어디에 서 있나* 만 다룬다.

---

## 한 장 요약

| 층 | 우리 위치 | 쟀나 |
|---|---|---|
| **harness** (governance) | **본체** — 가드 6 · 권한 3티어 · 규약 · 예산 천장 | ✅ 가드 27/29 · 브랜치 규약 10/12 |
| **loop** | 규칙 없음. 플랫폼 기본(`/goal`·`maxTurns`)도 안 씀 | ⚠️ 한 주장만 쟀고 **0** |
| **graph** (위상) | **컨슈머 에이전트 0.** 네 가지 실행 방식 중 아무것도 안 씀 | ❌ |
| **context — 코드 이해** | LSP 둘. 지식그래프 자산 없음 | ❌ (LSP 는 결론 없음) |

**"안 쟀다" 는 "효과 없다" 가 아니다.** 네 칸 중 셋이 비어 있고, 그게 정직한 현재 상태다.

---

## 1. Harness engineering — governance 층

### 정의

에이전트가 **할 수 없게** 만드는 것과, **하기로 약속된 것**을 고정하는 것. 위 층 구분에는 이름이 없지만, TrueFoundry 가 graph 층에 필요하다고 나열한 **네 가지 governance** 가 정확히 이 자리다 — identity · access policy · budgets/rate limits · guardrails.

**우리는 그 넷 중 셋을 이미 갖고 있고, 하나는 최근에 만들었다.**

| TrueFoundry 의 governance | 우리 것 |
|---|---|
| access policy — 도구 단위 제한 | `permissions` 3티어 (allow 42 / ask 3 / deny 8) |
| guardrails — pre/post tool-invoke 훅 | PreToolUse 차단 훅 4 + Stop 정보 훅 2 |
| budgets | `make context-budget` — 상시 컨텍스트 천장 9,000 |
| identity — 노드별 신원 | **없다.** 우리는 단일 세션 하네스라 아직 노드가 없다 |

### 설정 지점

`hooks/*.sh` + `hooks.json` (가드) · `settings.json permissions` (가드) · `CLAUDE.md` (가이드, 전역) · `.claude/rules/**` (가이드, **프로젝트 스코프만**) · `harnessctl` (되돌릴 수 있게 설치).

가드와 가이드는 대체 불가다 — 가이드는 무시될 수 있고, 가드는 모든 케이스를 사전 인코딩할 수 없다.

### 측정

| 무엇 | 결과 |
|---|---|
| 가드가 사고를 막나 | **27 / 29**, 정상 작업 오탐 **2 / 24** |
| 글이 행동을 바꾸나 (브랜치 이름) | 0/12 → **10/12**, *p* ≈ 0.00007 |
| commit 제목 70자 | 6/6 대 6/6 — **0. 규칙에서 지웠다** |
| 제거하면 원래대로인가 | 92 assertion, 정준 동일 |

**이 층만 제대로 재봤다.** 그리고 재본 것 중 하나는 0 이어서 지웠다.

---

## 2. Loop engineering — 에이전트 한 개의 사이클

### 정의

**언제 멈추고 언제 다시 도는가.** observe → reason → act → **verify** 의 verify 와 그 되먹임.

### 플랫폼이 이미 주는 것 — 우리가 안 쓰고 있다

| 무엇 | 다음 턴이 시작되는 조건 | 멈추는 조건 |
|---|---|---|
| **`/goal`** | 직전 턴이 끝나면 | **작은 모델이 조건 충족을 판정** |
| `/loop` | 시간 간격 경과 | 사용자가 멈추거나 모델이 끝났다고 판단 |
| Stop hook | 직전 턴이 끝나면 | 사용자 스크립트나 프롬프트가 결정 |

`/goal` 은 **세션 스코프 prompt-based Stop hook 의 래퍼**다. 매 턴 후 조건과 대화를 small fast model 에 보내 yes/no 와 이유를 받는다. 조건은 4,000자까지, `or stop after 20 turns` 같은 턴 절을 넣어 상한을 건다. 평가자는 **도구를 부르지 않으므로 대화에 드러난 것만 판정한다** — 그래서 조건은 *"`npm test` 가 0 으로 끝난다"* 처럼 에이전트 자신의 출력이 증명할 수 있는 형태여야 한다.

에이전트 frontmatter 의 **`maxTurns`** 는 이 층의 유일한 **하드 상한**이다.

### 기존 방법 — Superpowers 가 이미 두껍다

| 스킬 | 줄 | 무엇 |
|---|---|---|
| `test-driven-development` | 320 | 실패하는 테스트를 먼저 |
| `systematic-debugging` | 283 | 고치기 전에 원인 |
| `verification-before-completion` | 120 | 완료 선언 전에 증거 |
| `executing-plans` | 64 | 체크포인트마다 검토 |

합 787줄. **우리가 얹을 자리는 그 위가 아니다.**

### 우리 현황

**없다.** `CLAUDE.md` §4 가 *"Define success criteria. Loop until verified"* 를 말하지만 멈춤 조건이 없고, `/goal` 도 `maxTurns` 도 쓰지 않는다.

R6 초안(턴·세션·실험 세 척도, 525 tok)을 썼다가 **철회했다.**

### 측정

| 무엇 | raw | harness | 판정 |
|---|---|---|---|
| 검증 명령을 스스로 돌렸나 | **3 / 3** | **3 / 3** | **변별력 없음** |

첫 시도가 반드시 실패하는 과제를 주고 검증 명령을 언급하지 않았는데도 양팔 다 돌렸다. **검증을 돌리는 행동은 규칙이 사는 것이 아니라 모델이 원래 하는 것이다.**

**그리고 조사가 그 결론을 강화한다** — `/goal` 이 이미 "조건이 충족될 때까지 턴을 반복하고, 판정은 별도 모델이 한다" 를 플랫폼 기능으로 제공한다. 우리가 글로 쓰려던 것의 상당 부분이 이미 기계로 있다. **글을 더 쓰기 전에 있는 기계를 쓰는지부터 봐야 한다.**

---

## 3. Graph engineering — 위상

### 정의

**시스템 자체의 구조.** 어떤 노드가 존재하고(에이전트 루프 · 결정론적 함수 · 라우터 · 조인 · **사람 체크포인트** · 도구 호출), 어떤 전이가 허용되며, 런타임 작업 그래프가 어떻게 형성·변형되나. 엣지는 **통신과 위임**이고, 위상 자체가 *프로그래밍·버전 관리 가능한 산출물*로 다뤄진다.

**데이터를 구조화하는 지식그래프와 다른 것이다** (그건 §4).

### 같은 이름의 두 번째 용법

[Eigent](https://www.eigent.ai/blog/graph-engineering-ai-agents) 는 같은 단어를 **"피드백 루프들을 서로 감시·제약·교정하는 네트워크로 엮는 기술"** 로 쓴다 (2026년 7월 중순부터 확산). 단일 루프가 규모에서 깨지는 네 가지를 든다 — Goodhart 법칙, 자기 목표를 의심하지 못함, 루프 간 충돌, 측정 자체의 노후화. 처방은 **짝 지표와 반대 지표 · 상위 루프가 소유하는 기준값 · 케이던스 분리 · 동결 노드**(held-out 테스트셋·안전 제약)· **앵커**(외부 고정 기준).

**두 용법은 싸우지 않는다.** 하나는 *누가 누구에게 일을 넘기나*(위상), 다른 하나는 *어떤 루프가 어떤 루프를 감시하나*(제어). 우리에게는 후자가 더 가깝다 — 우리는 벤치(측정 루프)·훅(가드 루프)·원장(개선 루프)을 갖고 있는데 **셋이 서로를 감시하지 않는다.**

### 설정 지점 — Claude Code 는 네 가지를 준다

| 방식 | 무엇을 주나 | 언제 |
|---|---|---|
| **Subagents** | 한 세션 안의 위임 워커. 자기 컨텍스트에서 일하고 요약만 돌려준다 | 곁가지 작업이 메인 대화를 검색결과·로그로 채울 때 |
| **Agent view** | 백그라운드 세션들을 한 화면에서 디스패치·감시 (research preview) | 독립 과제 여럿을 넘겨두고 필요할 때만 개입 |
| **Agent teams** | 공유 task list + 에이전트 간 메시징, 리드가 관리 (실험적, 기본 비활성) | Claude 가 쪼개고 배정하고 동기화까지 하길 원할 때 |
| **Dynamic workflows** | 스크립트가 다수 서브에이전트를 돌리고 결과를 교차 검증 | 한 턴으로 조율하기엔 큰 일, 또는 여러 각도의 검증이 필요할 때 |

보조: **worktree**(파일 충돌 격리) · **cross-session messaging** · `/batch`(큰 변경을 5–30개 worktree 격리 서브에이전트로).

에이전트 frontmatter 가 위상의 노드 속성을 정한다 — `model`(`haiku`·`sonnet`·`opus`·`fable`·`inherit`) · `effort`(`low`~`max`) · `maxTurns` · `tools`/`disallowedTools` · `skills` · `memory` · `background` · `isolation`(`worktree`). **`hooks`·`mcpServers`·`permissionMode` 는 플러그인 에이전트에서 보안상 거부된다.**

### 기존 방법 — 위상 패턴과 티어링

업계에서 반복 언급되는 위상 다섯: **fan-out · pipeline · debate · supervisor · swarm**. 그리고 비용 패턴은 **model tiering** — 요청을 복잡도 티어로 나눠 가장 싼 모델에 태우고, 오케스트레이터만 상위 모델을 쓴다. 보고되는 절감은 **40–60%** 다 ([Requesty](https://www.requesty.ai/blog/multi-agent-orchestration-patterns-that-work-in-production) · [Beam](https://beam.ai/agentic-insights/multi-agent-orchestration-patterns-production) · [MindStudio](https://www.mindstudio.ai/blog/ai-model-orchestration-smart-model-cheaper-sub-agents)).

**그 숫자를 그대로 믿지 않는다.** 우리 규율은 *에이전트 세션을 표본으로 쓰는 A/B 는 20% 미만의 효과를 주장하지 않는다* 이고, 40–60% 주장에는 **재작업률**이 빠져 있다 — 싼 모델이 놓친 것을 비싼 모델이 다시 하면 총비용은 오른다.

`harness-100` 은 위상을 산문으로 쓴 예다 — 의존 DAG, 병렬 표시, `_workspace/NN_role.md` 핸드오프. 다만 **frontmatter 에 `model` 도 `effort` 도 없어 강제되는 것이 없다.**

### 우리 현황

**컨슈머용 sub-agent 를 하나도 배포하지 않는다.** 네 가지 실행 방식 중 아무것도 쓰지 않는다. 저장소 자체용 `harness-reviewer` 하나뿐이다.

**에이전트는 공짜가 아니다** — description 이 스킬과 같이 상시 로드된다. 티어를 내려 아낀 만큼 상시 비용이 붙는다.

### 측정

**안 쟀다.** 관측은 하나 있다 — 한 세션에서 서브에이전트 12개를 띄웠고 경로 치환·개수 세기처럼 상위 모델이 필요 없던 것이 절반이었다. **관측이지 측정이 아니다.**

재려면 **정확도 · 토큰 · 재작업률** 셋을 함께 봐야 한다. 앞의 둘만 보면 업계 숫자와 같은 실수를 한다.

---

## 4. Context 층 — 코드베이스를 어떻게 이해하나

graph 층과 헷갈리기 쉬워 따로 둔다. **여기는 데이터 구조이고, 위상이 아니다.**

### 이 카테고리는 지금 빠르게 붐비는 중이다

`CodeGraph` 는 출시 5개월에 47.4k star, `GitNexus` 는 4→6월에 1.2k → 42k. 최근 몇 주에만 같은 일을 하는 오픈소스 넷이 새로 나왔다 ([Enterprise DNA](https://enterprisedna.co/resources/ai-pulse/ai-pulse-2026-07-23-codebase-knowledge-graph-for-ai-agents-is-now-a-crowded-fast/)).

**수렴한 패턴이 하나 있다**: 구조를 **로컬에서 미리 계산**하고 **MCP 로 서빙**한다 — 클라우드 없이, 임베딩 API 없이, 코드 유출 없이. `CodeGraph` 는 tree-sitter 로 20+ 언어를 파싱해 심볼 관계·콜그래프·의존 엣지를 SQLite 그래프에 넣고, 실제 저장소 7개에서 **토큰 47% · 도구 호출 58% 감소**를 보고한다 ([ToKnow.ai](https://toknow.ai/posts/codegraph-knowledge-graph-ai-coding-agents-fewer-tokens/) · [Ry Walker 비교](https://rywalker.com/research/code-intelligence-tools)). 학술 쪽에는 [CodexGraph](https://arxiv.org/pdf/2408.03910)(코드 그래프 DB 와 LLM 연결)가 있다.

`graphify`(ehr-research 프로젝트 스킬, 702줄)는 같은 계열이되 코드에 한정하지 않는다 — 문서·논문·이미지까지 넣고, 출처를 `EXTRACTED`/`INFERRED`/`AMBIGUOUS` 로 구분하는 감사 추적과 *"모르면 AMBIGUOUS 를 쓰고 절대 엣지를 지어내지 말라"* 를 규칙으로 둔다.

### LSP 는 같은 질문의 다른 답

|  | LSP | 지식그래프 |
|---|---|---|
| 단위 | 심볼 | 코퍼스 |
| 시점 | 즉시 | 비동기 (미리 계산) |
| 상시 비용 | **0** | 인덱스 유지·재빌드 |
| 잘하는 질문 | "이 함수 정의 어디" | "이 결정이 어느 문서·코드에 흩어져 있나" |

**경쟁 관계가 아니다. 같은 자로 재면 둘 다 무의미한 수가 나온다.**

### 우리 현황과 측정

자산은 LSP 둘뿐이고 그건 심볼 층이다. **지식그래프는 시도조차 안 했다.** LSP 는 재봤지만 **결론이 없다** — 토큰 −6.3%, 이 설계로 검출 가능한 최소 효과가 61%.

**남들이 47% 를 보고하는데 우리가 6.3% 를 못 가른다는 것은 우리 자가 짧다는 뜻이지, 효과가 없다는 뜻이 아니다.** 재려면 먼저 *답이 갈리는 질문 유형*을 정해야 한다.

---

## 층을 가르는 이유

| 증상 | 어느 층인가 |
|---|---|
| 시크릿이 명령줄에 들어갔다 | harness — guardrail |
| 같은 실패를 세 번째 고치고 있다 | loop — 멈춤 조건 (`/goal`·`maxTurns`) |
| 개수 세기에 최상위 모델을 썼다 | graph — 노드 속성 (`model`·`effort`) |
| 이 변경이 어디에 닿는지 모르겠다 | context — 코드 이해 |
| 벤치는 초록인데 실제로는 나빠졌다 | graph — 루프끼리 감시하지 않음 (Eigent 의 Goodhart) |

**섞으면 잘못된 자리를 고친다.** 루프가 안 멈추는 것을 가드로 막으면 정상 작업을 막게 되고, 이해 부족을 위상으로 풀면 싼 모델을 더 띄우게 된다.

## 다음을 정하는 기준

1. **어느 층인가** — 층이 안 정해지면 무엇을 잴지도 안 정해진다.
2. **플랫폼에 이미 있나** — `/goal`·`maxTurns`·subagents·workflows. **글을 쓰기 전에 기계를 확인한다.** R6 이 이 확인을 건너뛴 사례다.
3. **하드 레버인가** — `maxTurns`·`model`·`permissions` 는 강제되고 규칙은 안 된다.
4. **재는 방법이 서나** — 잴 수 없는 주장은 규칙으로 올리지 않는다. 그리고 **재작업률 없는 비용 절감 주장은 절감 주장이 아니다.**
5. **상시 비용이 얼마인가** — `make context-budget`. 훅과 LSP 는 0, 스킬·에이전트·rule 은 아니다.

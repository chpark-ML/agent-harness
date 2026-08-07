# ADR-0008: 하네스를 플러그인과 선언적 설치기로 쪼갠다 — 선은 플랫폼이 그었다

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

초판은 파일 복사 설치기 하나였다 ([ADR-0005](0005-installer.md)). 오버레이 트리를 컨슈머의 `.claude/` 에 복사하고 `settings.json` 을 jq 로 병합했다. 동작했지만 값을 셋 치렀다. 업데이트가 컨슈머의 재실행에 달려 있고, 훅 등록이 컨슈머의 `settings.json` 안에서 우리 것과 그들 것으로 섞이며 (마커·strip-then-append 라는 장치가 오직 그것 때문에 존재했다), 버전이라는 개념이 아예 없었다.

Claude Code 플러그인 시스템은 그 셋을 전부 해결한다. 대신 하네스 자산 전부를 나르지는 못한다. 무엇을 나르고 무엇을 못 나르는지는 취향의 문제가 아니라 문서에 적혀 있는 사실이다.

| 자산 | 플러그인이 나르는가 | 근거 |
|---|---|---|
| 훅 | ✅ `hooks/hooks.json` | 컴포넌트. 경로는 `${CLAUDE_PLUGIN_ROOT}` 로 앵커한다 |
| 스킬 · 커맨드 · 에이전트 | ✅ `skills/` · `commands/` · `agents/` | 컴포넌트 |
| 실행파일 | ✅ `bin/` | "Executables added to the Bash tool's `PATH` while the plugin is enabled" |
| 외부 플러그인 의존 | ✅ `dependencies` | [ADR-0009](0009-external-dependencies.md) |
| permissions (allow · ask · deny) | ❌ | 플러그인 `settings.json` 은 "only the `agent` and `subagentStatusLine` keys are supported" |
| `includeCoAuthoredBy` | ❌ | 같은 이유 |
| `CLAUDE.md` | ❌ | "A `CLAUDE.md` file at the plugin root is not loaded as project context" |
| `.claude/rules/**` | ❌ | 컴포넌트 목록에 없다. 문서화된 `~/.claude/rules/` 도 없다 ([ADR-0007](0007-install-levels.md)) |
| 컨슈머 소유 설정 템플릿 | ❌ | 플러그인 파일은 업데이트가 갈아치우는 캐시에 산다. 컨슈머가 고친 값이 살아남을 곳이 아니다 |

못 나르는 넷은 대체 경로도 없다. permissions 를 훅으로 흉내 낼 수는 있으나 그것은 권한 모델을 다시 구현하는 일이고, `CLAUDE.md` 를 스킬로 흉내 내면 상시 지침이 조건부 지침이 된다.

## Decision

하네스를 두 조각으로 배포하고, **어느 쪽에 놓을지는 "플러그인이 이것을 나를 수 있는가" 하나로 판정한다.**

**1. 플러그인** — `harness-core` 와 프로파일들. 가드 훅 6개, 스킬, `/verify` 커맨드, 훅 검증기, 그리고 `bin/harnessctl`. Claude Code 가 직접 로드·업데이트·스코프 관리한다.

**2. `harnessctl init`** — permissions 3티어, `includeCoAuthoredBy`, `CLAUDE.md`, `.claude/rules/harness/**`, 경로 가드 설정 템플릿 2개. 플러그인이 `bin/` 으로 배포하므로 별도 설치가 필요 없다.

`harnessctl` 은 ADR-0005 의 성질 중 여전히 값을 하는 것을 전부 유지한다 — 2-tier (managed / template), 쓰기 전 preflight 전량 통과, 카운터 붙은 타임스탬프 백업, `settings.json` 파싱-재직렬화, 그리고 **manifest 영수증에 의한 대칭 제거**. 없어진 것은 훅 병합 하나뿐이고, 그와 함께 마커·strip-then-append·해당 jq 프로그램이 삭제됐다.

**선언적 페이로드는 `harness-core` 한 곳에만 둔다.** 플러그인 캐시는 플러그인마다 분리되고 `../` 로 넘어갈 수 없으므로, 페이로드를 프로파일마다 흩으면 `harnessctl` 이 남의 캐시를 찾아다녀야 한다. 프로파일 선택은 `harnessctl init --with dev,research` 플래그가 흡수한다. 스킬은 정반대로 각자의 프로파일에 둔다 — 플랫폼이 각 캐시에서 직접 로드하기 때문이다.

`install.sh` 는 두 절반을 순서대로 호출해 한 명령으로 설치를 끝낸다. 세션 재시작은 Claude Code 가 플러그인을 *로드* 하는 데 필요할 뿐 선언적 절반을 *쓰는* 데는 필요 없고, 셸에서 도는 스크립트는 플러그인 디렉터리의 `harnessctl` 을 경로로 직접 부를 수 있다.

**매니페스트에 `version` 을 명시한다** . `version` 을 비우면 git commit SHA 가 버전이 되어 커밋마다 자동으로 갱신되지만, `claude plugin validate --strict` 를 CI 게이트로 쓰려면 명시가 필요하다. 대가는 분명하다 — 변경을 배포하려면 버전을 올려야 한다.

## Consequences

- **컨슈머의 `settings.json` 에 `hooks` 블록이 생기지 않는다.** 설치기가 그 블록을 읽지도 쓰지도 않으며, `scripts/verify-install.sh` 가 설치 전후 `.hooks` 바이트 동일을 단정한다. ADR-0005 가 가장 공들여 만든 장치가 통째로 필요 없어졌다.
- **플러그인 파일은 컨슈머 트리에서 열리지 않는다.** 캐시에 있고, 업데이트가 갈아치운다. 그래서 훅의 차단 메시지가 사용자가 접근할 수 있는 **유일한 인터페이스** 다 — 무엇이 걸렸는지·어떻게 푸는지·`docs/hooks/<name>.md` 링크를 다 담아야 한다는 ADR-0002 의 요구가 권고에서 필수가 됐다.
- **CI 에 job 이 하나 늘었다.** `make verify-plugins` 는 Claude CLI 를 요구하므로 별도 job 으로 돌린다 — CLI 나 레지스트리 문제가 동작 검증 job 까지 끌어내리지 않게 하기 위해서다. 나머지 두 job (ubuntu bash 5 · macOS bash 3.2) 은 jq·git·python3 만으로 돌고, CLI 가 없는 머신에서 `make verify` 는 그 항목만 skip 한다.
- **커밋만으로는 사용자에게 아무것도 가지 않는다.** 새 훅 산출물 묶음에 `version` bump 가 한 항목으로 추가된다 (`CLAUDE.md` §2).
- 설치는 한 명령이지만, 가드가 실제로 동작하려면 세션 재시작이 필요하다 — 플러그인은 세션 시작 시 로드된다. 스크립트가 마지막에 그렇게 말한다.
- **스코프 표면이 둘이 된다.** 플러그인 절반은 `claude plugin install --scope user|project|local`, 선언적 절반은 `harnessctl init --scope user|project`. 둘은 독립이고 짝을 맞추는 것은 사용자 몫이다 (`harnessctl` 에 `local` 은 아직 없다). 반대로 [ADR-0007](0007-install-levels.md) 의 훅 중복 경고는 없어졌다 — `harnessctl init` 을 몇 개 스코프에서 돌리든 훅을 등록하는 주체는 플러그인 하나다.
- **제거도 두 명령이다.** `harnessctl uninstall` 이 영수증을 되돌리고, `claude plugin uninstall ... --prune` 이 플러그인을 지운다. 전자가 후자를 출력한다.

## Alternatives considered

- **플러그인만** — 배포는 가장 깨끗하지만 하네스의 절반이 배송되지 않는다. permissions 3티어도 5원칙 `CLAUDE.md` 도 rules 도 없는 가드 묶음은 하네스가 아니다.
- **설치기만** (초판 유지) — 동작은 하나 업데이트·버전·외부 플러그인 의존이 전부 없고, 훅 등록이 계속 컨슈머의 `settings.json` 을 침범한다. 플랫폼이 제공하는 것을 손으로 다시 만드는 쪽에 남는 선택이다.
- **marketplace 없이 `@skills-dir` 로 스킬 디렉터리만 로드** — 가장 가볍다. 그러나 버전도 팀 배포 경로도 없고, 훅과 `bin/` 은 애초에 실을 수 없어 가드가 통째로 빠진다.
- **선언적 페이로드를 프로파일마다 분산** — 모듈 경계와 모양이 맞지만, 플러그인 캐시가 분리돼 있어 `harnessctl` 이 남의 캐시를 가로질러야 한다. `--with` 플래그가 같은 일을 캐시 경계를 넘지 않고 한다.

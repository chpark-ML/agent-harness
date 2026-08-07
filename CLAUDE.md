# CLAUDE.md — working on agent-harness itself

This repo *is* a Claude Code harness, shipped as plugins plus a declarative installer. The conventions below apply while developing it. The product's own behavioural defaults live in [`plugins/harness-core/declarative/CLAUDE.md`](plugins/harness-core/declarative/CLAUDE.md) — **read that file before any non-trivial task here**; it applies to work in this repo too, and it is the text consumers receive:

1. **Think Before Coding** — state assumptions, surface alternatives, stop when unclear.
2. **Simplicity First** — minimum code that solves the problem, nothing speculative.
3. **Surgical Changes** — every changed line traces to the request.
4. **Goal-Driven Execution** — define the check, run it, then report done.
5. **Surface Harness Gaps** — propose, don't silently patch around.

**Language.** Match the user's prompt language. Docs are Korean prose with English code, paths and command names; scripts and their comments are English.

---

## 1. 무엇을 어디에 두는가

배포 경로가 둘이고, 갈림길은 **플러그인이 그것을 나를 수 있는가** 다 ([ADR-0008](docs/adr/0008-plugin-declarative-split.md)).

| 넣으려는 것 | 위치 |
|---|---|
| 훅 | `plugins/harness-core/hooks/<name>.sh` + `hooks/hooks.json` 등록 |
| 모든 컨슈머가 받을 스킬·커맨드 | `plugins/harness-core/{skills,commands}/` |
| 특정 프로파일만 받을 스킬 | `plugins/harness-<profile>/skills/` |
| 검증 스크립트 | `plugins/harness-core/scripts/` |
| 실행파일 | `plugins/harness-core/bin/` — Bash 도구 PATH 에 자동 등록 |
| permissions · scalar | `plugins/harness-core/declarative/settings-fragment.json` |
| `CLAUDE.md` · rules · 소비자 설정 템플릿 | `plugins/harness-core/declarative/` |
| 외부 플러그인 의존 | 해당 profile 의 `dependencies` |
| 이 저장소에서만 쓰는 것 | `scripts/` · `.claude/` (배포 안 됨) |

**플러그인이 못 나르는 것은 셋뿐이고 전부 확인된 사실이다**: 플러그인 `settings.json` 은 `agent`·`subagentStatusLine` 만 지원하고, 플러그인 루트의 `CLAUDE.md` 는 컨텍스트로 안 읽히며, `rules` 는 컴포넌트 목록에 없다. 그 셋만 `declarative/` 로 가고 `harnessctl` 이 쓴다.

**선언적 페이로드는 `harness-core` 한 곳에만 둔다.** 프로파일별로 흩으면 harnessctl 이 남의 플러그인 캐시를 찾아야 하는데, 캐시는 플러그인마다 분리되고 `../` 참조가 금지된다. 프로파일 선택은 `harnessctl init --with <name>` 플래그로 처리한다. 스킬은 반대다 — 플랫폼이 각 플러그인 캐시에서 직접 로드하므로 자기 프로파일에 두면 된다.

## 2. 새 훅은 산출물 한 묶음이다

하나라도 빠지면 미완성이다. [`harness-reviewer`](.claude/agents/harness-reviewer.md) 에이전트가 감사한다.

1. `plugins/harness-core/hooks/<name>.sh`
2. `plugins/harness-core/scripts/verify-<name>.sh` — 8케이스 이상
3. `docs/hooks/<name>.md`
4. `plugins/harness-core/hooks/hooks.json` 의 등록 (`${CLAUDE_PLUGIN_ROOT}` 앵커)
5. `docs/agent-layer.md` 갱신
6. `plugins/harness-core/.claude-plugin/plugin.json` 의 `version` bump

네 곳의 `<name>` 이 같아야 감사가 기계적으로 돌아간다.

**version bump 는 선택이 아니다.** manifest 에 `version` 이 명시돼 있으므로 커밋만으로는 사용자에게 변경이 가지 않는다 — Claude Code 가 같은 버전 문자열을 보고 캐시를 유지한다. 이 제약을 감수한 이유는 `claude plugin validate --strict` 를 CI 게이트로 쓰기 위해서다 (`version` 미지정은 strict 에서 경고→실패).

## 2b. 새 스킬도 산출물 한 묶음이다

훅에 검증기를 요구하는 것과 같은 이유로, 스킬에는 **트리거 eval** 을 요구한다. description 의 트리거와 negative routing 은 행동에 대한 주장이고, 재지 않은 주장은 주장일 뿐이다.

1. `plugins/harness-<profile>/skills/<name>/SKILL.md` — description 은 **반드시 따옴표로** 감싼다 (§4)
2. `evals/trigger/<name>.json` — 양성 6 · 음성 6. **음성이 더 중요하다**: 이웃 스킬로 가야 할 near-miss 를 넣는다
3. `make bench-trigger` 로 실측하고 결과를 `docs/agent-layer.md` §4b 표에 올린다
4. 해당 플러그인의 `version` bump

**음성 케이스는 "우리 스킬이 조용했나" 가 아니라 "일이 우리가 적어둔 곳으로 갔나" 를 본다.** `bench-trigger` 가 실제로 호출된 스킬 이름을 기록하므로, negative routing 이 지목한 이웃으로 갔는지 확인할 수 있다. 아무 데도 안 갔다면 그건 다른 종류의 결과이고 고치는 방법도 다르다.

**쿼리당 1회는 측정이 아니다** (기본 3회). 그리고 트리거 측정은 계기가 조용히 죽는 방식이 여럿이라, 결론 내기 전에 [§4b 의 함정 표](docs/agent-layer.md) 를 먼저 본다.

## 3. 훅 계약

- **bash 3.2 + jq 만.** Python·Node 확장 금지 ([ADR-0002](docs/adr/0002-hook-contract.md)). 예외는 저장소 전용 `scripts/verify-frontmatter.sh` — 배포되지 않으므로 python3 를 쓴다. macOS 의 `/bin/bash` 가 바닥이다 — `mapfile`, 연관 배열, `${x^^}` 없음. `set -u` 에서 빈 배열은 `"${a[@]+"${a[@]}"}"` 로 전개.
- **stdin 을 파싱하는 훅** 은 `jq` 부재 시 stderr 한 줄 + `exit 0` 으로 자기 비활성화한다. 훅 부재로 작업이 막히지 않는다. `git` 만 호출하고 stdin 을 읽지 않는 훅 (`session-brief`, `check-uncommitted`) 에는 이 가드가 없는 것이 정상이다 — 없는 가드를 찾아 헤매지 않도록 각 훅 문서가 그 사실을 명시한다.
- **차단하는 훅만 exit 2.** 나머지는 무슨 일이 있어도 exit 0. 정보성 훅이 턴을 막으면 그건 버그다.
- 차단 메시지는 *무엇이 걸렸는지* 와 *어떻게 푸는지* 를 둘 다 담고 `docs/hooks/<name>.md` 를 가리킨다. 컨슈머는 훅 파일을 자기 트리에서 열 수 없다 (플러그인 캐시에 있다) — 메시지가 유일한 인터페이스다.
- 헤더 주석에 catches / scope / bypass 를 적는다.

## 4. 검증 의무

**검증 없이 머지된 가드는 가드가 아니라 장식이다** ([ADR-0003](docs/adr/0003-verification-mandate.md)).

```bash
make verify                  # syntax + frontmatter + 훅 + harnessctl + 매니페스트
make verify BASH=/bin/bash   # macOS bash 3.2 바닥 확인 — 머지 전 필수
```

- 검증기는 `plugins/harness-core/scripts/_verify-lib.sh` 의 `run_case` / `expect` / `expect_match` 를 쓴다. 새로 만들지 말 것.
- 케이스는 세 종류를 다 담는다: **no-op** (훅이 끼어들면 안 되는 입력), **block**, **boundary** (막을 것과 닮았지만 통과해야 하는 것). 세 번째가 실제로 값을 한다.
- **스킬·rule·agent 의 frontmatter 는 조용히 비어버린다.** 따옴표 없는 YAML 스칼라에 콜론+공백이 들어가면 파싱이 실패하고 description 이 빈 채로 로드된다 — 트리거도 negative routing 도 없이. `scripts/verify-frontmatter.sh` 가 막는다. description 값은 항상 따옴표로 감쌀 것.
- 설치기를 건드렸으면 `scripts/verify-install.sh` 가 게이트다. 특히 *uninstall 후 settings.json 이 원본과 정준 동일* 하다는 성질 — 이게 깨지면 컨슈머가 잃는다.
- 사고가 있었으면 회귀 케이스를 먼저 추가하고 고친다.
- **벤치마크는 `verify` 와 다르다.** `make verify` 는 공짜이고 CI 가 돌린다. `make bench*` 는 모델 세션을 태우므로 실비가 들고 CI 에서 돌지 않는다 — 관련된 것을 바꿨을 때 손으로 돌리고 수치를 §4b 에 남긴다.

## 5. `docs/agent-layer.md` 가 단일 SOT

하네스의 범위·인벤토리·backlog 를 바꾸는 변경은 **이 파일만** 갱신한다 ([ADR-0004](docs/adr/0004-single-source-of-truth.md)). 같은 내용을 README 나 별도 로드맵에 복제하지 않는다 — 두 벌이 되는 순간 한 벌은 곧 거짓이 된다. 설치되는 index 파일을 만들지 않는 것도 같은 이유다.

## 6. 커밋·PR

- Branch `{feat,fix,chore}-<slug>`, PR title `[<slug>] <description>` 70자 이하.
- **AI 귀속 금지** ([ADR-0006](docs/adr/0006-no-ai-attribution.md)). `Co-Authored-By: Claude` trailer 도 `🤖 Generated with` footer 도 남기지 않는다. 이 저장소는 자기 훅의 보호를 받지 못하므로 (자기 자신에게 설치 불가) 규율로만 지킨다.
- 하네스 자체의 구조 변경과 콘텐츠 추가는 별도 PR 로.
- PR 을 열기 전에 `.claude/harness-gaps.md` 를 읽는다. 같은 항목이 2회차면 PR 본문 `## Notes` 로 올린다 — 이 저장소도 자기 §5 를 따른다.

## 7. 과잉 설계 억제

이 저장소가 컨슈머에게 설교하는 §2 는 이 저장소에도 적용된다. 참조 하네스 중 하나는 "혹시 몰라서" 만든 방어 875줄을 한 커밋으로 지웠고 그건 승리였다. 새 훅·새 규칙·새 모듈은 **실제로 두 번 이상 발생한 문제** 에만 추가한다. 후보는 `docs/agent-layer.md` 의 backlog 에 ⏳ 로 두고, 두 번째 발생을 기다린다.

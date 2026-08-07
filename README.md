<h1 align="center">agent-harness</h1>

<p align="center">
  <strong>연구와 개발을 위한 범용 Claude Code 하네스</strong><br>
  쓸 만한 플러그인을 검토하고 조합해, 한 명령으로 설치되고 한 명령으로 되돌아가는 한 벌로 유지한다.
</p>

<p align="center">
  <a href="https://github.com/chpark-ML/agent-harness/actions/workflows/verify.yml"><img alt="verify" src="https://github.com/chpark-ML/agent-harness/actions/workflows/verify.yml/badge.svg"></a>
  <img alt="checks" src="https://img.shields.io/badge/checks-356-blue">
  <img alt="guards" src="https://img.shields.io/badge/incidents%20stopped-27%2F29-success">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-lightgrey">
</p>

<p align="center">
  <em>주장하지 않고 잰다.</em> 모든 층이 stock Claude Code 와 대조해 숫자가 붙어 있고,<br>
  아무것도 벌지 못한 규칙은 <a href="#어떻게-점검하나--테스트와-결과">그렇다고 적혀 있다</a>.
</p>

---

## 시작하기

먼저 저장소를 받는다.

```bash
git clone https://github.com/chpark-ML/agent-harness ~/agent-harness && cd ~/agent-harness
```

그다음은 무엇을 하는 사람인지에 따라 한 줄이면 된다. 전부 조합 가능하고 나중에 더해도 된다.

#### 개발 — 가장 흔한 조합

```bash
./install.sh --profile dev,python --with-tools
```

가드 6개, [Superpowers](https://github.com/obra/superpowers) 스킬 14개, `pr-create`·`pr-review`, Python 언어 서버까지. TypeScript 면 `python` 대신 `typescript`, 둘 다면 둘 다 쓴다.

#### 연구

```bash
./install.sh --profile research
```

가드 6개, 5문서 노트 규율, `research-notes`·`repro-checklist`. 실험을 돌리고 결과를 기록하는 흐름에 맞춰져 있다.

#### 연구 + 발표

```bash
./install.sh --profile research,slides
```

위에 더해 `results-deck` — 산출물을 발표 서사로 바꾸고, **덱의 모든 수치가 근거로 추적되는지 기계로 검사** 한다. 렌더링은 [`slides-grab`](https://www.npmjs.com/package/slides-grab) 에 넘긴다.

#### 이 저장소에만

```bash
./install.sh --profile dev --scope project
```

머신 전체를 건드리지 않는다. 현재 git 저장소의 `.claude/` 와 `settings.json` 만 바뀌고, 그 저장소를 쓰는 팀 전체가 같은 규약을 받는다.

#### 최소 — 가드만

```bash
./install.sh
```

가드 6개, 권한 3티어, 5원칙 `CLAUDE.md`, 스킬은 `pr-create` 하나. 나머지는 나중에 같은 명령에 프로파일만 더해서 올리면 된다.

설치가 끝나면 **Claude Code 를 재시작**한다. 플러그인은 새 세션에서 로드된다.

### 옵션

| 옵션 | 기본값 | 설명 |
|---|---|---|
| `--profile <list>` | `core` | `core` · `dev` · `research` · `slides` · `python` · `typescript`, 콤마로 조합 |
| `--scope user\|project` | `user` | `user` 는 머신 전체, `project` 는 현재 저장소만 |
| `--with-tools` | 꺼짐 | LSP 가 요구하는 언어 서버를 `npm -g` 로 설치 (전역 변경이라 opt-in) |
| `--ref <tag\|branch>` | — | marketplace 를 특정 리비전에 고정 |
| `BIN_DIR=<dir>` | `~/.local/bin` | `harnessctl` shim 을 놓을 곳 |

설치기가 marketplace 등록 → 플러그인 설치 → `harnessctl init` → 언어 서버 → shim → `doctor` 를 순서대로 진행한다.

### 확인

```bash
harnessctl doctor
```

무엇이 설치됐고 무엇이 빠졌는지 알려준다. `harnessctl` 은 `~/.local/bin` 의 shim 으로 어느 셸에서든 부를 수 있고, `~/.local/bin` 이 PATH 에 없으면 설치기가 **쓰는 셸에 맞는 한 줄** 을 알려준다.

<details>
<summary><b>플러그인 명령으로 직접 하려면</b></summary>

```bash
claude plugin marketplace add chpark-ML/agent-harness
claude plugin install harness-dev@agent-harness --scope user
# 새 세션에서
harnessctl init --scope user --with dev
```

`install.sh` 가 두 번째 단계를 세션 재시작 없이 해내는 방법은 플러그인 디렉터리의 `harnessctl` 을 경로로 직접 부르는 것이다 — PATH 등록만 새 세션이 필요하지, 설치를 끝내는 데는 필요 없다.

</details>

### 되돌리기

```bash
harnessctl uninstall --scope user                          # 설정·규칙·CLAUDE.md
claude plugin uninstall harness-dev@agent-harness --prune  # 플러그인
```

**검증된 성질**: 제거 후 `settings.json` 은 설치 전과 **정준 동일** 하다 (`jq -S` 기준). 설치기는 자기가 쓴 것의 영수증(`harness-manifest.json`)만 되돌리고 그 외에는 손대지 않는다. 프로젝트 소유가 된 템플릿(`CLAUDE.md` 등)은 남기며, 함께 지우려면 `--purge-templates`. 무엇이 지워질지 먼저 보려면 `--dry-run`.

<details>
<summary><b>부수효과 하나</b></summary>

`settings.json` 이 jq 로 재직렬화되므로 들여쓰기가 2칸으로 정규화된다 (키 순서는 보존). 재실행은 멱등이라 아무것도 쓰지 않지만, Claude Code 가 자기 포맷으로 파일을 다시 쓴 뒤에는 (UI 에서 설정을 바꿨을 때 등) 처음 한 번 재정규화가 일어나고 스냅샷이 하나 남는다.

</details>

### 요구 사항

bash 3.2 이상 (stock macOS `/bin/bash` 가 바닥) · jq · git · 플러그인을 지원하는 Claude Code. 전제는 하나 더 있다 — **git 저장소**. 가드 둘과 규약 대부분이 git 과 forge(PR) 를 가정한다.

---

## 이 저장소가 하는 일

**연구와 개발 양쪽에 쓰는 범용 에이전트 하네스를 만든다.** 하는 일은 셋이다.

1. **최신 플러그인·스킬을 검토한다** — 본문을 읽고, 겹치는지 판정하고, 쓸 것과 안 쓸 것을 근거와 함께 남긴다.
2. **조합(composite)을 만든다** — 남의 것으로 되는 일은 다시 만들지 않는다. 우리가 얹는 것은 *이 저장소의 규약* 과, 남들이 안 만든 자리뿐이다.
3. **한 줄로 설치되는 한 벌로 유지한다** — 설치·제거·진단이 명령 하나씩이고, 제거하면 원래대로 돌아간다.

여기에 하나가 더 붙는다. **넣은 것이 실제로 값을 하는지 잰다.** 규칙은 적어두면 지켜지는 것처럼 보이지만, 재보면 절반은 아무것도 벌지 않는다.

---

## 규칙 요약

컨슈머가 받는 규약. 전문은 설치되는 `CLAUDE.md` 와 `.claude/rules/harness/` 에 있다.

### 행동 5원칙

| | |
|---|---|
| **1. Think Before Coding** | 가정을 밝히고, 해석이 갈리면 묻는다. 불명확하면 멈춘다 |
| **2. Simplicity First** | 문제를 푸는 최소 코드. 200줄인데 50줄로 되면 다시 쓴다 |
| **3. Surgical Changes** | 바뀐 줄 전부가 요청으로 추적돼야 한다. 남의 죽은 코드는 말만 하고 둔다 |
| **4. Goal-Driven Execution** | 성공 기준을 정하고 실제로 돌려서 확인한다. "될 것이다" 는 검증이 아니다 |
| **5. Surface Harness Gaps** | 하네스가 틀렸으면 우회하지 말고 드러낸다. **2회 이상 발생** 해야 제안하고, 그 횟수는 원장에 센다 |

### 작업 규약

- **Branch** `{feat,fix,chore}-<slug>` — `/` 금지 (worktree·디렉터리 이름이 된다)
- **Commit** 제목은 동사로 시작하는 한 줄, 본문엔 *what* 이 아니라 *why* (글자 수 상한은 재보니 0을 벌어서 **제거함**)
- **PR** title `[<slug>] <description>`, body 는 Motivation → Changes → Verification → Notes
- **AI 귀속 금지** — `Co-Authored-By: Claude` 도 `🤖 Generated with` 도 남기지 않는다
- `main` 직접 push 금지. 한 줄 수정·임시 탐색은 애초에 PR 단위가 아니다

### 권한 3티어

| 티어 | 무엇 |
|---|---|
| allow | 읽기 전용, 안전한 git (`status`·`diff`·`add`·`commit`·`switch` …) |
| ask | `push` · `rebase` · `merge` — 되돌리기 비싼 것 |
| deny | 되돌릴 수 없는 것, `.env`·`secrets/` 읽기, force push |

---

## 무엇이 들어 있고 어떻게 구조화했나

### 두 조각으로 배포된다

플랫폼이 그은 선을 그대로 따른다 ([ADR-0008](docs/adr/0008-plugin-declarative-split.md)).

| | 플러그인 | `harnessctl` |
|---|---|---|
| **무엇** | 가드 훅 6 · 스킬 · 커맨드 · 검증기 | permissions 3티어 · `CLAUDE.md` · `.claude/rules` |
| **왜 이쪽** | Claude Code 가 직접 로드·업데이트·스코프 관리 | 플러그인 `settings.json` 은 `agent`·`subagentStatusLine` 만 지원하고, 플러그인 루트 `CLAUDE.md` 는 컨텍스트로 안 읽히며, `rules` 는 플러그인 컴포넌트가 아니다 |
| **설치** | `claude plugin install` | `harnessctl init` |
| **위치** | 플러그인 캐시 | 프로젝트 또는 `~/.claude` |

**`harnessctl` 이 두 군데서 보이는 방식이 다르다.** 플러그인의 `bin/` 은 Claude Code **Bash 도구** 의 PATH 에만 올라간다 — 에이전트는 바로 부를 수 있지만 사용자 터미널에서는 안 보인다. 게다가 플러그인 캐시는 버전별 디렉터리라 (`.../harness-core/1.6.0/bin/`) 업데이트마다 경로가 바뀌므로, PATH 에 직접 넣거나 심링크를 걸면 다음 업데이트에 깨진다.

그래서 `install.sh` 가 `~/.local/bin/harnessctl` 에 **shim** 을 쓴다 — 실행 시점에 최신 버전을 찾아 넘기는 3줄짜리 `/bin/sh` 스크립트다. 평범한 실행 파일이라 zsh·bash·fish 에서 똑같이 동작하고, 플러그인을 업데이트해도 따라간다. `~/.local/bin` 이 PATH 에 없으면 설치기가 **쓰는 셸에 맞는 한 줄** 을 알려준다 (`~/.zshrc` · `~/.bashrc` · `fish_add_path`).

### 프로파일 6개

전부 `harness-core` 를 dependency 로 갖고, 조합해서 설치한다.

| 프로파일 | 더해지는 것 | 상시 컨텍스트 |
|---|---|---|
| `harness-core` | 가드 훅 6, `pr-create`, `/verify`, 검증기, `harnessctl` | ~390 tok |
| `harness-dev` | [Superpowers](https://github.com/obra/superpowers) 14스킬 + 코드리뷰 규약 · `pr-review` | ~351 + 688 tok |
| `harness-research` | 5문서 노트 규율 · `research-notes` · `repro-checklist` | ~480 tok |
| `harness-slides` | `results-deck` — 산출물을 발표 서사로, 수치 추적을 기계 검사 | ~300 tok |
| `harness-python` | `pyright-lsp` (manifest 한 장, 파일 없음) | 0 |
| `harness-typescript` | `typescript-lsp` (manifest 한 장, 파일 없음) | 0 |

**두 프로파일의 두께가 다른 것은 미완성이 아니다.** Superpowers 가 개발 워크플로를 폭넓게 덮지만 **연구 전용 스킬은 0개** 라서, `harness-dev` 는 얇고 `harness-research` 는 두껍다.

**훅과 LSP 는 상시 컨텍스트 비용이 0** 이다 — 매 세션 비용을 만드는 것은 스킬 description 뿐이다.

---

## 구조 상세

### 가드 훅 6개

| 훅 | 무엇을 막나 | 차단 |
|---|---|---|
| `secret-scrubber` | 명령줄의 리터럴 시크릿 (API 키·토큰·AWS 키) | ✅ exit 2 |
| `large-file-veto` | 10 MiB 초과 `git add` | ✅ |
| `protected-paths` | 선언된 절대경로 prefix (기본 비활성) | ✅ |
| `ai-attribution-guard` | 커밋·PR 의 AI 귀속 | ✅ |
| `session-brief` | 세션 시작 시 10줄 repo 상태 | ❌ 정보 |
| `check-uncommitted` | default branch 에 작업이 쌓일 때 | ❌ 정보 |

**차단하는 훅만 exit 2.** 정보성 훅이 턴을 막으면 그건 버그다. 차단 메시지는 *무엇이 걸렸는지* 와 *어떻게 푸는지* 를 둘 다 담는다 — 컨슈머는 훅 파일을 자기 트리에서 열 수 없으므로 (플러그인 캐시에 있다) 메시지가 유일한 인터페이스다.

### 스킬 5개

| 스킬 | 프로파일 | 언제 |
|---|---|---|
| `pr-create` | core | 현재 작업을 이 저장소 규약대로 PR 로. PR 열고 멈춤, 머지 안 함 |
| `pr-review` | dev | **이미 열린** PR 을 체크리스트로 훑고 blocking/non-blocking 분리 |
| `research-notes` | research | 5문서 세트(STATUS·experiment_plan·FINDINGS·ARTIFACTS·review_log) 생성·유지 |
| `repro-checklist` | research | 시드·환경·config 3기둥. 인용될 결과를 내기 전에 |
| `results-deck` | slides | 산출물 → 발표 서사. 모든 수치가 근거로 추적되는지 기계 검사 |

각 스킬의 description 은 **negative routing** 을 담는다 — 자기가 안 할 일을 이웃 스킬 이름으로 지목한다. 이게 실제로 작동하는지는 아래에서 쟀다.

### `harnessctl` 이 건드리는 것 — 전부

플러그인은 자기 캐시에만 살고 아래 어디에도 쓰지 않는다.

| # | 무엇 | 규칙 |
|---|---|---|
| 1 | `.claude/rules/harness/**` | **관리 파일** — 덮어쓴다. 고칠 것은 하네스 저장소에서 고친다. `--scope user` 에서는 설치 안 함 |
| 2 | `CLAUDE.md`, `*-paths.txt` | **템플릿** — 없을 때만 복사. 이후 프로젝트 소유 |
| 3 | `settings.json` | 파싱 후 **재직렬화** (통째 교체 아님). 없는 permission 문자열과 `includeCoAuthoredBy: false` 만 |
| 4 | `settings.json.bak-<ts>` | 설정이 실제로 바뀔 때만 남기는 직전 스냅샷 |
| 5 | `.gitignore` | 두 줄 (프로젝트 스코프에서만) |
| 6 | `harness-manifest.json` | 위 전부의 영수증. 제거는 이 영수증만 되돌린다 |

**건드리지 않는 것** — `settings.json` 의 `hooks` 블록 (훅은 플러그인이 등록하며, 검증기가 *설치 전후 `.hooks` 바이트 동일* 을 단정한다) · 선택 스코프 밖의 무엇도 · `settings.local.json` · manifest 에 없는 `.claude/` 아래 전부 · git (커밋·브랜치·config).

---

## 검토한 플러그인 — 무엇을 들이고 무엇을 안 들였나

이름이 아니라 **본문을 읽고** 판정한다. 이름만 보고 내린 판정은 세 번 다 틀렸다 ([ADR-0011](docs/adr/0011-ecosystem-survey.md)).

### 채택

| 이름 | 무엇 | 어떻게 들였나 | 근거 |
|---|---|---|---|
| [`superpowers`](https://github.com/obra/superpowers) | 개발 워크플로 스킬 14 (brainstorming · TDD · systematic-debugging · worktrees …) | `harness-dev` 의 dependency | 개발 워크플로를 폭넓게 덮는다. 우리가 만들 이유가 없다 |
| `pyright-lsp` · `typescript-lsp` | 언어 서버 연결 | 언어 프로파일의 dependency | 상시 컨텍스트 비용 0. 해당 언어 파일이 있을 때만 붙는다 |
| `skill-creator` (공식) | **평가 하네스** — 서브에이전트 3(analyzer·comparator·grader) + 스크립트 7. 짝 실행·mean±stddev 집계·트리거 최적화 | 개발자만 설치, **배포 안 함** | 이름은 작성 도우미지만 본문은 계측기다. 상시 112 tok / 호출 10.9k |
| `karpathy-guidelines` (MIT) | LLM 코딩 함정 4원칙 | **설치 안 함 — 본문을 흡수** | 우리 `CLAUDE.md` §1–4 가 이미 이것이다 (규범 문장 23개 중 20개 일치). 두 벌 로드할 이유가 없다 |
| `task-observer` (CC BY 4.0) | 세션을 관찰해 스킬 개선점을 원장에 남기는 메타 스킬 | **설치 안 함 — 기제만 흡수** | 446줄 중 절반이 우리 §5 와 겹친다. 가져온 것은 *지속되는 원장* 하나 |
| `slides-grab` (npm) | 슬라이드 렌더링 (plan → html → design → export) | 플러그인 아님. `doctor` 가 설치 안내 | 렌더링은 이미 풀린 문제다. `results-deck` 은 그 **입력** 을 만든다 |

### 미채택

| 이름 | 무엇 | 왜 안 들였나 |
|---|---|---|
| `caveman` | 원시인 말투로 출력 토큰 65% 절감 | [ADR-0002](docs/adr/0002-hook-contract.md) 가 *차단 메시지는 무엇이 걸렸고 어떻게 푸는지 둘 다 담는다* 를 훅 계약으로 못박았다. 정면으로 싸운다 |
| `ui-ux-pro-max` | UI/UX 레퍼런스 (84 스타일·192 팔레트·22 스택) | 도메인 프로파일감. 이 저장소는 UI 프로젝트가 아니고 발생 0회 → `harness-frontend` 후보로 backlog |
| `claude-mem` | 라이프사이클 훅 5개로 세션 전체를 캡처→AI 압축→SQLite | **모든 도구 입출력** 을 저장한다. `secret-scrubber` 를 운영하는 저장소에서 무엇이 삼켜지는지 확인 전에는 불가 |
| `omniroute` | 290+ 프로바이더 로컬 AI 게이트웨이 | 플러그인이 아니라 프록시. 프롬프트와 코드가 제3자를 통과한다 — 하네스 결정이 아니라 보안 결정 |
| `handoff` | 세션 간 컨텍스트 인수인계 | `harness-research` 의 5문서 세트가 연구 쪽을 이미 덮는다. 개발 쪽 발생 0회 |

### 우리가 직접 만든 것 — 남이 안 만든 자리만

| 자산 | 왜 우리가 만들어야 했나 |
|---|---|
| 가드 훅 6 | 스킬은 가이드고 훅은 가드다. 사고 방어선은 모델 밖에 있어야 한다 |
| `harnessctl` | 플러그인이 못 나르는 셋(permissions·CLAUDE.md·rules)을 **되돌릴 수 있게** 설치하는 것은 아무도 안 한다 |
| `pr-create` · `pr-review` | Superpowers 의 대응 스킬은 *저장소 규약* 을 모른다. 생애주기 단계로 축을 갈라 공존시켰다 |
| `research-notes` · `repro-checklist` | Superpowers 의 **연구 전용 스킬은 0개** 다 |
| `results-deck` + `check-claims.sh` | `slides-grab` 은 렌더링만 한다. *추적 불가능한 수치가 슬라이드에 오르는 사고* 를 막는 자리는 비어 있었다 |

---

## 어떻게 점검하나 — 테스트와 결과

**측정 설정**: 에이전트 세션을 쓰는 벤치는 전부 `model=opus` · `effort=high` 로 **고정** 한다 (`BENCH_MODEL`·`BENCH_EFFORT` 로 변경, 시작할 때 출력). 설정을 바꾸면 숫자도 달라질 수 있고, 특히 effort 를 올리면 raw 팔이 좋아져 하네스의 효과가 작게 나올 수 있다 — `xhigh` 에서는 재보지 않았다.

두 종류가 있다. **`verify` 는 공짜이고 CI 가 돌린다. `bench` 중 셋은 모델 세션을 태우므로 실비가 들고 손으로 돌린다** — 나머지 둘(`bench`·`bench-claims`)은 훅과 검사기를 직접 구동할 뿐이라 공짜다.

### 1. `make verify` — 의도대로 도는가 (공짜, CI)

```bash
make verify                     # 전부
make verify BASH=/bin/bash      # macOS bash 3.2 바닥 — 머지 전 필수
```

| 대상 | 케이스 |
|---|---|
| 훅 6종 동작 | **198** |
| 설치기 왕복 | **92** assertion |
| 발표 수치 검사기 | **36** |
| frontmatter 파싱 | **11** |
| 플러그인·마켓플레이스 매니페스트 | **7** |
| 벤치마크 건강 (`verify-benches`) | **12** |
| **합계** | **356** |

케이스는 세 종류를 다 담는다 — **no-op**(끼어들면 안 되는 입력) · **block** · **boundary**(막을 것과 닮았지만 통과해야 하는 것). 세 번째가 실제로 값을 한다. 검증 없이 머지된 가드는 가드가 아니라 장식이다.

CI 는 세 곳에서 돈다: ubuntu (bash 5) · macOS (bash 3.2) · 플러그인 매니페스트.

**벤치마크도 감시 대상이다.** `bench-claims` 가 한 번 조용히 썩었다 — 코퍼스를 git 커밋에서 만들었는데 히스토리를 다시 쓰자 그 커밋이 사라졌고, 벤치는 빈 코퍼스로 결과 없이 끝나는데 README 는 마지막 수치를 현재형으로 인용하고 있었다. `verify-benches` 가 이제 그걸 막는다 — 공짜 벤치 둘은 실제로 돌리고, 유료 셋은 입력(코퍼스·eval 세트·픽스처·동의 게이트·커밋 SHA 고정 여부)을 검사한다.

### 2. `make bench*` — 날것 대비 값을 하는가 (유료, 수동)

| 층 | 물은 것 | stock | harness | 판정 |
|---|---|---|---|---|
| **가드** `make bench` (공짜) | 사고를 막나 | 0 / 29 | **27 / 29** | 결정론적 · 정상 작업 오탐 **2/24** |
| **규약** `make bench-convention` | 브랜치 이름 규칙이 행동을 바꾸나 | 0 / 12 | **10 / 12** | **유의** *p* ≈ 0.00007 |
| " | commit 제목 70자 제한은? | 6 / 6 | 6 / 6 | **변별력 없음** |
| " | commit 본문 존재는? | 5 / 6 | 6 / 6 | 유의하지 않음 |
| **스킬 라우팅** `make bench-trigger` | 의도한 스킬로 가나 | — | **59 / 60** | 음성 6/6 은 3회씩 확인 |
| **수치 추적** `make bench-claims` (공짜) | 필터에 구멍이 있나 | — | 143토큰 중 41 플래그 · **신규 모양 0** | 결정론적 |
| **LSP** `make bench-lsp` | 토큰·정확도가 나아지나 | 3/3 clean | 3/3 clean, 토큰 −6.3% | **결론 없음** |

#### 읽는 법 세 가지

**하나. 두 숫자를 함께 본다.** 가드가 27/29 를 막는 대가는 정상 작업 2/24 를 막는 것이다. 전부 차단하는 가드는 차단율 100% 를 찍고 하루 만에 꺼지며, 그때부터 0 이 된다. **8% 가 가격표다.**

**둘. 규약 중에도 아무것도 벌지 않는 것이 있다.** commit 제목 70자 제한은 하네스가 있으나 없으나 6/6 이다 — 모델이 원래 짧게 쓴다. 규칙으로 적혀 있으면 지켜지는 것처럼 보이지만 **그 규칙이 만든 차이는 0** 이다. **그래서 지웠다.** 재봐서 0이 나온 것은 후보가 아니라 결론이다. 규칙 파일에 왜 뺐는지와 다시 넣으려면 먼저 재라는 조건을 주석으로 남겼다.

**넷. 수치 추적 벤치는 백분율을 내지 않는다.** `bash 5` 와 `hooks 6` 은 같은 모양이라 어떤 계수기도 가르지 못한다 — 검사기의 알려진 한계가 채점기에도 그대로 적용된다. 그래서 출력은 비율이 아니라 **목록** 이고, 사람이 읽어서 새 모양이 있으면 필터와 회귀 케이스를 추가한다. 코퍼스는 `evals/prose-corpus.md` 에 **동결** 돼 있다 — 이전 판은 히스토리 커밋을 참조했는데, 히스토리를 다시 쓰자 코퍼스가 비었고 벤치는 조용히 결과 없이 끝났다.

**셋. LSP 는 "효과 없음" 이 아니라 "이 자로는 안 보임" 이다.** off 팔의 변동계수가 26% 라 n=3 으로 검출 가능한 최소 효과가 **61%** 다. 관측된 6.3% 를 보려면 팔당 137회가 필요하다. **에이전트 세션을 표본으로 쓰는 A/B 는 20% 미만의 효과를 주장하지 않는다** 는 규율이 여기서 나왔다.

#### 계측기를 여섯 번 틀렸다

측정보다 이쪽이 값졌을지 모른다. 여섯 번 모두 화면에는 **"0.0 / 실패" 로 똑같이 보였고**, 전부 하네스를 부당하게 나쁘게 보이게 했다 — 읽기 전용 과제라 기제가 발동 못 함 · 타임아웃이 미트리거와 구분 안 됨 · 이미 설치된 스킬은 대역으로 못 잼 · 첫 도구 호출만 봄 · 픽스처에 규칙이 없었음 · 과제가 규칙의 예외 조항에 걸림.

**규칙: 음성 결과를 얻으면 결론 내기 전에 기제가 발동할 조건이 갖춰졌는지부터 확인한다.** 그리고 **쿼리당 1회는 측정이 아니다.**

여섯 건 전부와 방법·표본·한계는 [`docs/agent-layer.md` §4b](docs/agent-layer.md) 에 표로 있다.

#### 아직 못 잰 것

- **PR 단계 규약** (title 형식, description 4절) — 헤드리스 세션은 `git push` 승인 프롬프트에 답할 수 없어 PR 단계에 도달하지 못한다. 이 자체가 발견이다.
- **`CLAUDE.md` 5원칙 자체** — 브랜치 규약은 쟀지만 "Simplicity First" 가 코드를 실제로 단순하게 만드는지는 채점 기준을 세우기 어렵다.

---

## 기여

[`CLAUDE.md`](CLAUDE.md) 가 개발 규약, [`docs/agent-layer.md`](docs/agent-layer.md) 가 범위와 backlog 의 단일 출처다. 요지 넷:

- 새 가드는 **산출물 한 묶음** — 스크립트 · 검증기 · 문서 · `hooks.json` 등록 · SOT 갱신, 이름이 넷 다 같을 것.
- 새 스킬도 마찬가지 — **트리거 eval**(`evals/trigger/<name>.json`, 양성 6 · 음성 6)이 없으면 미완성이다. 재지 않은 negative routing 은 주장일 뿐이다.
- 검증 없이 머지된 가드는 가드가 아니라 장식이다.
- **실제로 두 번 이상 발생한** 문제에만 자산을 추가한다. 횟수는 `.claude/harness-gaps.md` 가 센다.

플러그인 매니페스트에 `version` 이 명시돼 있으므로 **변경을 배포하려면 버전을 올려야 한다.** 커밋만으로는 사용자에게 가지 않는다.

## Credits

`settings.json` 을 안전하게 병합하는 법, 충돌 방지 백업, 대칭 제거, "무엇을 건드리는가" 감사 절은 [`claude-statusline`](https://github.com/chpark-ML/claude-statusline) 에서 가져왔다. 2-tier 설치·훅별 검증 의무·자동 발견 디스패처·ADR 규율, 그리고 5원칙 `CLAUDE.md`·harness gap 루프·PR 규약·"가드만 차단한다" 원칙·연구 노트 5문서 패턴은 공개하지 않는 사내 하네스 두 벌에서 가져와 프로젝트 특화를 걷어낸 것이다.

외부 저작물에서 가져온 것 둘, 출처와 라이선스를 밝힌다.

- **`CLAUDE.md` §1–§4** — MIT 라이선스 [`karpathy-guidelines`](https://github.com/multica-ai/andrej-karpathy-skills) 를 거의 그대로 옮겼다. Andrej Karpathy 의 LLM 코딩 함정 관찰에서 나온 것이다. §5 만 우리 것이다.
- **`CLAUDE.md` §5 의 원장(ledger) 기제** — CC BY 4.0 [`task-observer`](https://github.com/rebelytics/one-skill-to-rule-them-all) 에서 가져왔다. "적는 행위가 곧 집행" 이라는 논지가 그쪽 것이다.

의존으로 들이는 것은 [`superpowers`](https://github.com/obra/superpowers) 와 공식 마켓플레이스의 LSP 플러그인들이고, 각자의 라이선스를 따른다.

## License

MIT. [`LICENSE`](LICENSE) 참조.

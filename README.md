# agent-harness

프로젝트에 상관없이 쓰는 Claude Code 하네스. 가드 훅 · 규약 · 스킬 한 벌을 설치하고, 제거하면 정확히 원래대로 돌린다.

**이 하네스가 스스로 하는 일은 셋이다** — 사고를 막고(가드), 작업 규약을 고정하고(규칙·스킬), 그 둘을 안전하게 설치·제거한다. *일하는 능력 자체* 는 대부분 조합해서 얻는다: `harness-dev` 는 [Superpowers](https://github.com/obra/superpowers) 를 끌어와 brainstorming · TDD · systematic debugging · 계획 수립 · 코드리뷰 요청/수신 · worktree 를 붙이고, 우리는 그 위에 *이 저장소의 규약* 만 얹는다. 남의 것으로 되는 일을 다시 만들지 않는 것이 방침이다 ([ADR-0009](docs/adr/0009-external-dependencies.md)).

그래서 두 프로파일의 두께가 다르다. Superpowers 의 스킬 14개는 개발 워크플로를 폭넓게 덮지만 **연구 전용은 0개** 라서, `harness-dev` 는 얇고 (규약 1 + 스킬 1) `harness-research` 는 두껍다 (규약 1 + 스킬 2 + 템플릿 5). 비대칭은 미완성이 아니라 그 사실의 결과다.

**전제**: git 저장소. 가드 둘과 규약 대부분이 git 과 forge(PR) 를 가정한다. PR 흐름이 없는 개인 저장소에서는 `rules/harness/workflow.md` 의 절반이 무의미하고, 나머지 절반(harness gap 루프, plan 단계 검증)은 그대로 유효하다.

## 두 조각으로 배포된다

플랫폼이 그은 선을 그대로 따른다. 플러그인이 나를 수 있는 것과 없는 것이 명확히 갈리기 때문이다 ([ADR-0008](docs/adr/0008-plugin-declarative-split.md)).

| | 플러그인 | `harnessctl` |
|---|---|---|
| 무엇 | 가드 훅 6개 · 스킬 · 커맨드 · 검증기 | permissions 3티어 · `includeCoAuthoredBy` · `CLAUDE.md` · `.claude/rules` |
| 왜 이쪽 | Claude Code 가 직접 로드·업데이트·스코프 관리 | 플러그인 `settings.json` 은 `agent`·`subagentStatusLine` 만 지원하고, 플러그인 루트의 `CLAUDE.md` 는 컨텍스트로 안 읽히며, `rules` 는 플러그인 컴포넌트가 아니다 |
| 설치 | `claude plugin install` | `harnessctl init` |
| 위치 | 플러그인 캐시 | 프로젝트 또는 `~/.claude` |

`harnessctl` 은 플러그인이 `bin/` 으로 배포하므로 설치하면 Bash 도구 PATH 에 자동으로 올라간다.

## 요구 사항

bash 3.2 이상 (stock macOS `/bin/bash` 가 바닥) · jq · git · 플러그인을 지원하는 Claude Code. `harnessctl doctor` 가 전부 점검한다.

## 설치

```bash
git clone https://github.com/chpark-ML/agent-harness ~/agent-harness
~/agent-harness/install.sh --profile dev,python --with-tools
```

한 번에 끝난다. 스크립트가 marketplace 등록 → 플러그인 설치 → `harnessctl init` (플러그인이 못 나르는 절반) → 언어 서버 설치 → `doctor` 까지 진행한다. 프로파일은 콤마로 조합하고, `--scope project` 면 이 저장소에만, 생략하면 머신 전체(`user`)다. `--with-tools` 는 LSP 가 요구하는 언어 서버를 `npm -g` 로 설치한다 — 전역 변경이라 opt-in 이다.

끝나면 **Claude Code 를 재시작**한다. 플러그인은 새 세션에서 로드되고, 그때부터 가드가 동작하며 `harnessctl` 이 PATH 에 오른다.

손으로 하고 싶다면 같은 일을 두 단계로 나눈 것이 전부다:

```bash
claude plugin marketplace add chpark-ML/agent-harness
claude plugin install harness-dev@agent-harness --scope user
# 새 세션에서
harnessctl init --scope user --with dev
```

`install.sh` 가 두 번째 단계를 세션 재시작 없이 해내는 방법은 플러그인 디렉터리의 `harnessctl` 을 경로로 직접 부르는 것이다 — PATH 등록만 새 세션이 필요하지, 설치를 끝내는 데는 필요 없다.

## 프로파일

전부 `harness-core` 를 dependency 로 갖는다. 조합해서 설치할 수 있다 — `harness-dev` + `harness-python` 이 흔한 조합.

| 프로파일 | 더해지는 것 |
|---|---|
| `harness-core` | 가드 훅 6개, `pr-create` 스킬, `/verify`, 검증기, `harnessctl` |
| `harness-dev` | [Superpowers](https://github.com/obra/superpowers) + 코드리뷰 규약 · `pr-review` |
| `harness-research` | 5문서 노트 규율 · `research-notes` · `repro-checklist` |
| `harness-slides` | `results-deck` — 산출물을 발표 서사로, 모든 수치의 추적을 기계 검사 |
| `harness-python` | `pyright-lsp` |
| `harness-typescript` | `typescript-lsp` |

언어 프로파일은 dependency 만 든 manifest 하나다. 다른 언어가 필요하면 공식 marketplace 의 LSP (`gopls-lsp` · `rust-analyzer-lsp` · `jdtls-lsp` · `clangd-lsp` 등) 를 같은 모양으로 추가하면 된다. **LSP 플러그인은 언어 서버 바이너리를 포함하지 않는다** — `harnessctl doctor` 가 PATH 를 확인하고 설치 명령을 알려준다. `harness-slides` 도 같다: 렌더링은 `slides-grab` (npm) 이 하고 이 프로파일은 그 입력을 만든다.

## 무엇을 받는가

**가드 (차단)** — `secret-scrubber` (명령줄의 리터럴 시크릿), `large-file-veto` (10 MiB 초과 `git add`), `protected-paths` (선언된 절대경로 prefix, 기본 비활성), `ai-attribution-guard` (커밋·PR 의 AI 귀속).

**정보 (차단 안 함)** — `session-brief` (세션 시작 시 10줄 repo 상태), `check-uncommitted` (default branch 에 작업이 쌓일 때만).

**규약** — `CLAUDE.md` 5원칙 (Think Before Coding · Simplicity First · Surgical Changes · Goal-Driven Execution · Surface Harness Gaps), 브랜치·커밋·PR 규약, harness gap 루프, plan 단계 진단 검증.

**권한 3티어** — 읽기 전용·안전한 git 은 allow, `push`/`rebase`/`merge` 는 ask, 되돌릴 수 없는 것과 `.env`·`secrets/` 읽기는 deny.

전체 인벤토리와 설계 근거는 [`docs/agent-layer.md`](docs/agent-layer.md), 결정 이력은 [`docs/adr/`](docs/adr/), 훅별 상세는 [`docs/hooks/`](docs/hooks/).

## harnessctl 이 건드리는 것 — 전부

플러그인은 자기 캐시에만 살고 아래 어디에도 쓰지 않는다. 아래는 `harnessctl init` 이 대상(`--scope project` 면 프로젝트, `--scope user` 면 `~/.claude`) 안에 쓰는 것의 전부다.

1. **관리 파일** — `.claude/rules/harness/**`. 이미 있으면 덮어쓴다. 로컬 수정은 사라지므로, 고칠 것은 하네스 저장소에서 고친다. *`--scope user` 에서는 설치하지 않는다* — 사용자 레벨 `rules` 가 읽힌다는 근거가 없어 무력한 파일이 되기 때문이고, 무엇을 건너뛰었는지 출력한다.
2. **템플릿 파일** — `CLAUDE.md`, `protected-paths.txt`, `allowed-paths.txt`. **없을 때만** 복사한다. 이후로는 프로젝트 소유.
3. **`settings.json`** — 없으면 만들고, 있으면 **파싱 후 재직렬화**한다 (통째로 교체하지 않는다). 넣는 것은 둘뿐: 이미 없는 permission 문자열, 그리고 `includeCoAuthoredBy: false` (**키가 없을 때만**; 값이 있으면 경고만 하고 둔다).
4. **`settings.json.bak-<타임스탬프>`** — 설정이 실제로 바뀔 때만 남기는 직전 스냅샷.
5. **`.gitignore`** — `settings.local.json` 과 `.bak-*` 두 줄 (프로젝트 스코프에서만).
6. **`harness-manifest.json`** — 위 전부의 영수증. 제거는 이 영수증만 되돌린다.

**건드리지 않는 것**

- **`settings.json` 의 `hooks` 블록.** 훅은 플러그인이 등록한다. 검증기가 *설치 전후로 `.hooks` 가 바이트 동일* 함을 단정한다.
- 선택한 스코프 밖의 무엇도. `.claude/settings.local.json`. manifest 에 없는 `.claude/` 아래 모든 것. git — 커밋도, 브랜치도, config 도.
- 이미 값이 있는 설정 키. 우리가 추가한 것만 우리 것이다.

**부수효과** — `settings.json` 이 jq 로 재직렬화되므로 들여쓰기가 2칸으로 정규화된다 (키 순서는 보존). 이후 재실행은 멱등이라 아무것도 쓰지 않지만, Claude Code 가 자기 포맷으로 파일을 다시 쓴 뒤 (설정을 UI 에서 바꿨을 때 등) 처음 한 번은 재정규화가 일어나고 스냅샷이 하나 남는다.

**제거**

```bash
harnessctl uninstall --scope user            # 템플릿은 남긴다
claude plugin uninstall harness-dev@agent-harness --prune
```

검증된 성질: 제거 후 `settings.json` 은 설치 전과 **정준 동일**하다 (`jq -S` 기준).

## 무엇을 기대할 수 있나

주장하지 않고 쟀다. 층마다 `make bench*` 로 stock Claude Code 와 대조한다.

| 층 | 결과 |
|---|---|
| **가드** — 사고를 막나 | stock **0 / 29** → harness **27 / 29** · 정상 작업 오탐 **2 / 24** |
| **규약** — 글이 행동을 바꾸나 | 브랜치 이름 stock **0 / 12** → harness **10 / 12** (*p* ≈ 0.00007) |
| **스킬 라우팅** — 의도한 스킬로 가나 | **59 / 60** |
| **발표 수치 추적** — 조작된 숫자를 잡나 | 실제 산문 193토큰 중 오탐 **6 (3.1%)** |
| **LSP** — 토큰이 주나 | **결론 없음.** 이 설계로는 61% 이상만 보인다 |

**두 숫자를 함께 봐야 한다.** 전부 차단하는 가드는 차단율 100%를 찍고 하루 만에 꺼지며, 그때부터 0이 된다. **8%가 가격표다.**

정직하게 적어 둘 것 셋:

- **규약 중에도 아무것도 벌지 않는 것이 있다.** commit 제목 70자 제한은 하네스가 있으나 없으나 6/6 이다 — 모델이 원래 짧게 쓴다.
- **PR 단계 규약은 아직 못 쟀다.** 헤드리스 세션은 `git push` 승인 프롬프트에 답할 수 없어 PR 단계에 도달하지 못한다.
- **측정하다 계기를 여섯 번 틀렸고 전부 하네스를 나쁘게 보이게 했다.** 그 여섯 건과 거기서 나온 규칙은 [`docs/agent-layer.md` §4b](docs/agent-layer.md) 에 표로 남겼다.

방법·표본·한계는 전부 [§4b](docs/agent-layer.md) 에 있다.

## 검증

```bash
make verify                     # 문법 + frontmatter + 훅 + harnessctl + 플러그인 매니페스트
make verify BASH=/bin/bash      # macOS bash 3.2 바닥
```

현재 훅 198 케이스 · claim 검사 33 · harnessctl 92 assertion · frontmatter 11 · 매니페스트 7.

CI 가 세 곳에서 돈다: ubuntu (bash 5) · macOS (bash 3.2) · 플러그인 매니페스트 (Claude CLI 필요, 별도 job). 동작 검증은 CLI 없이도 전부 돈다.

## 기여

[`CLAUDE.md`](CLAUDE.md) 가 개발 규약, [`docs/agent-layer.md`](docs/agent-layer.md) 가 범위와 backlog 의 단일 출처다. 요지 셋:

- 새 가드는 **산출물 한 묶음** — 스크립트 · 검증기 · 문서 · `hooks.json` 등록 · SOT 갱신, 이름이 넷 다 같을 것.
- 검증 없이 머지된 가드는 가드가 아니라 장식이다.
- **실제로 두 번 이상 발생한** 문제에만 자산을 추가한다.

플러그인 매니페스트에 `version` 이 명시돼 있으므로 **변경을 배포하려면 버전을 올려야 한다.** 커밋만으로는 사용자에게 가지 않는다.

## Credits

`settings.json` 을 안전하게 병합하는 법, 충돌 방지 백업, 대칭 제거, "무엇을 건드리는가" 감사 절은 [`claude-statusline`](https://github.com/chpark-ML/claude-statusline) 에서 가져왔다. 2-tier 설치·훅별 검증 의무·자동 발견 디스패처·ADR 규율, 그리고 5원칙 `CLAUDE.md`·harness gap 루프·PR 규약·"가드만 차단한다" 원칙·연구 노트 5문서 패턴은 공개하지 않는 사내 하네스 두 벌에서 가져와 프로젝트 특화를 걷어낸 것이다.

외부 저작물에서 가져온 것 둘, 출처와 라이선스를 밝힌다.

- **`CLAUDE.md` §1–§4** — MIT 라이선스 [`karpathy-guidelines`](https://github.com/multica-ai/andrej-karpathy-skills) 를 거의 그대로 옮겼다. Andrej Karpathy 의 LLM 코딩 함정 관찰에서 나온 것이다. §5 만 우리 것이다.
- **`CLAUDE.md` §5 의 원장(ledger) 기제** — CC BY 4.0 [`task-observer`](https://github.com/rebelytics/one-skill-to-rule-them-all) 에서 가져왔다. "적는 행위가 곧 집행" 이라는 논지가 그쪽 것이다.

의존으로 들이는 것은 [`superpowers`](https://github.com/obra/superpowers) 와 공식 마켓플레이스의 LSP 플러그인들이고, 각자의 라이선스를 따른다.

## License

MIT. [`LICENSE`](LICENSE) 참조.

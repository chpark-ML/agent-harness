# protected-paths

보호 prefix 아래의 **절대 경로** 를 건드리는 tool 호출을, 명시적 carve-out 이 없으면 차단한다.

## 동작

`PreToolUse` 이벤트, matcher `Read|Write|Edit|NotebookEdit|Glob|Grep|Bash` 로 등록된다 ([`hooks.json`](../../plugins/harness-core/hooks/hooks.json) 의 첫 번째 `PreToolUse` 블록 — 이 훅만 단독으로 들어 있다).

1. 보호 prefix 목록을 읽는다. 하나도 없으면 **조용히 exit 0** — 기본 비활성이다.
2. tool 별로 검사 대상 경로를 뽑는다 — `Read`/`Write`/`Edit` 는 `tool_input.file_path` (없으면 `.path`), `NotebookEdit` 는 `notebook_path`, `Glob`/`Grep` 은 `path`, `Bash` 는 command 를 공백·`"`·`'`·`=` 로 쪼갠 뒤 `/` 로 시작하는 토큰 전부. 그 외 tool 은 exit 0.
3. `/` 로 시작하지 않는 경로는 건너뛴다. 보호 prefix 아래에 있으면서 허용 prefix 아래에 없는 경로가 하나라도 있으면 그 경로를 찍고 exit 2. 없으면 exit 0.

`settings.json` 의 permission glob 이 못 메우는 자리를 메운다. permission glob 은 프로젝트 상대이므로, 공유 마운트·타 팀 export·프로덕션 데이터 디렉터리처럼 절대 경로로 닿는 곳은 사정권 밖이다.

**기본값을 두지 않은 것이 설계다.** 범용 하네스는 어느 절대 경로가 중요한지 알 수 없고, 지어낸 기본값을 가진 guard 는 엉뚱한 것을 막거나 무시하는 습관을 가르친다.

`jq` 가 없으면 stderr 에 한 줄 남기고 exit 0 으로 self-disable 한다.

## 설정

설정 파일은 **두 곳** 에서 읽고 합집합으로 쓴다 — 프로젝트의 `${CLAUDE_PROJECT_DIR:-.}/.claude/` 와 사용자 설정 디렉터리 `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/`. 훅이 어느 레벨에 설치돼 있든 같은 동작을 하며, 머신 전체 보호가 어떤 프로젝트의 자체 목록 때문에 사라지지 않는다 — 그러면 아무도 설정하지 않은 프로젝트에서 가드가 가장 약해진다.

| 대상 | 소스 | 형식 | 결합 방식 |
| --- | --- | --- | --- |
| 보호 | `HARNESS_PROTECTED_PATHS` | **콜론 구분** (`PATH` 와 동일) | 파일을 **대체** |
| 보호 | `<user>/protected-paths.txt` ∪ `<project>/.claude/protected-paths.txt` | 한 줄에 하나, `#` 주석 | 서로 **합집합**, env 가 있으면 둘 다 무시됨 |
| 허용 | `HARNESS_ALLOWED_PATHS` | **콜론 구분** | 파일과 **합집합** |
| 허용 | `<user>/allowed-paths.txt` ∪ `<project>/.claude/allowed-paths.txt` | 한 줄에 하나, `#` 주석 | env·서로 모두 합집합 |

보호는 대체, 허용은 합집합이다. 일회성 셸 예외가 프로젝트의 허용 목록을 조용히 날려버리면 안 되고, 반대로 보호가 합집합이면 env 로 보호를 *줄일* 방법이 없어진다.

두 env 변수 모두 콜론 구분이므로 **prefix 에 공백이 들어가도 된다** — `HARNESS_PROTECTED_PATHS='/my data:/mnt/shared'` 는 두 prefix 로 올바르게 읽힌다.

> **주의 — 옛 공백 구분 문법.** `HARNESS_PROTECTED_PATHS` 는 이전에 공백 구분이었다. 옛 문법 `'/a /b'` 는 이제 `/a /b` 라는 **한 개의** prefix 로 읽히므로 `/a` 도 `/b` 도 보호되지 않는다. 가드가 설정 문법 때문에 조용히 가드를 멈추는 것은 허용할 수 없는 실패 방향이라, 훅이 **값에 공백은 있고 콜론은 없을 때 stderr 로 한 줄 경고한다** — `HARNESS_PROTECTED_PATHS is colon-separated, so '/a /b' is being read as ONE prefix. If you meant several, write '/a:/b'.` 콜론으로 올바르게 나뉜 값은 그 안에 진짜 공백이 들어 있어도 경고하지 않는다.

두 `.txt` 는 훅과 달리 플러그인이 아니라 `harnessctl init` 이 설치하는 **template** 이다 — 원본은 [`plugins/harness-core/declarative/templates/`](../../plugins/harness-core/declarative/templates/) 에 있고, 한 번 복사된 뒤로는 consumer 소유다. `harnessctl` 이 manifest 에 template 으로 기록하므로 재설치가 덮어쓰지 않고, `harnessctl uninstall` 도 `--purge-templates` 없이는 남겨 둔다. 설치 위치는 scope 를 따른다 — `--scope project` 는 `.claude/` 아래, `--scope user` 는 사용자 설정 디렉터리 바로 아래. 배포되는 내용은 주석뿐이라 설치 직후 훅은 비활성 상태다.

**프로젝트 디렉터리는 암묵적으로 허용되지 않는다.** 프로젝트가 보호 prefix 안에 있으면 `.claude/allowed-paths.txt` 에 명시할 것. 암묵 예외는 guard 를 요청한 바로 그 자리에서 guard 를 꺼버린다.

## 통과하는 것

- **`/database`** — `/data` 가 보호되어 있어도 통과한다. 매칭이 `"$pre"` 또는 `"$pre"/*` 리터럴 비교이지 문자열 시작 비교가 아니기 때문이다 (`/mnt/shared-old` 도 마찬가지). 여기를 "고치면" 이름만 비슷한 무관한 디렉터리가 전부 막힌다.
- **상대 경로** (`data/local.csv`) 와 **절대 경로가 없는 Bash 명령** (`npm test && git status`) — 절대 경로만 본다.
- **주석·빈 줄뿐인 설정 파일** — 선언이 0개면 비활성과 같다.
- **목록에 없는 tool** (`Task` 등) — matcher 밖이고 스크립트도 `*)` 에서 exit 0.
- **carve-out 아래 경로** — `/data` 보호 + `/data/project-x` 허용이면 `/data/project-x/out.json` 은 통과하고 형제인 `/data/project-y` 는 차단된다.

## 우회

세 가지, 차단 메시지에 그대로 적혀 있다.

- 이 프로젝트가 상시로 닿아야 하면 → `.claude/allowed-paths.txt` 에 경로 추가
- 이 셸 한정 일회성이면 → `HARNESS_ALLOWED_PATHS=/p1:/p2 <command>`
- 애초에 보호 대상이 아니면 → `.claude/protected-paths.txt` 수정

## 한계

사고를 막는 guard 이지 적대적 우회를 막는 장치가 아니다.

- **경로 정규화가 없고, 벌어지는 틈은 느슨한 쪽이다.** `/tmp/../data/secret.csv` 는 실제로 `/data` 에 닿지만 문자열이 보호 prefix 로 시작하지 않아 **통과** 한다. `//data/x` 처럼 슬래시가 겹쳐도 마찬가지다. 반대 방향인 `/data/../etc/passwd` 는 `/data` 를 벗어나는데도 prefix 가 매칭되어 차단되는데, 이쪽은 안전한 실패다. 두 방향 모두 verifier 에 케이스로 박혀 있어 조용히 바뀌지 않는다.
- **상대 경로는 아예 검사되지 않는다.** `cd` 이후의 `../data/secret` 은 절대 경로로 보이지 않으므로 통과한다. 진짜로 지켜야 하는 경로는 `settings.json` 의 `deny` 규칙이 backstop 이고, 이 훅은 그 위에 얹는 사고 방지 장치다.
- **prefix 매칭만 한다.** glob·정규식·심볼릭 링크 해석이 없다. 보호 디렉터리를 가리키는 symlink 는 잡히지 않는다.
- **Bash 토크나이저가 거칠다.** 공백·따옴표·`=` 로만 자르므로 `cp a,/data/x .` 처럼 콤마로 붙은 경로는 놓친다. 반대로 `cd /data` 나 `OUT=/mnt/shared/x.log` 는 잡는다.
- **읽기도 차단된다.** `Read`·`Glob`·`Grep` 이 matcher 에 있으므로 조회조차 막힌다. 열람은 허용하고 쓰기만 막는 모드는 없다.

## 검증

[`plugins/harness-core/scripts/verify-protected-paths.sh`](../../plugins/harness-core/scripts/verify-protected-paths.sh) — 53 케이스. 설정만 다른 fixture 프로젝트 네 개(`none`·`commented`·`basic`·`carve`)를 만들어, 각 케이스가 어떤 설정을 검사하는지 이름에서 드러나게 한다.

사용자 레벨 설정은 다섯 케이스가 검사한다: 프로젝트 설정 없이 사용자 목록만으로 차단, 사용자 carve-out 적용, 양쪽 목록이 동시에 유효 (두 방향 각각), 그리고 env 보호 override 가 **두 파일 모두** 를 대체한다는 것.

구분자 경고는 네 케이스가 양방향으로 고정한다 — 공백만 있는 값은 차단 여부와 별개로 경고 문구가 나오고, 콜론으로 나뉜 값은 공백을 포함해도 경고가 **나오지 않음** 을 `expect_absent` 로 단언한다.

경계 7건 중 둘은 위 `## 한계` 의 정규화 없음을 **통과한다고 단정하는** 케이스다 — `/tmp/../data/secret.csv` 는 통과, `/data/../tmp/x` 는 차단. 못 막는다는 사실 자체를 테스트로 박아 두면 동작이 조용히 바뀌지 않고, 한계 절이 코드와 어긋날 수 없다.

```
bash plugins/harness-core/scripts/verify-protected-paths.sh
```

## 관련

- 훅 스크립트: [`plugins/harness-core/hooks/protected-paths.sh`](../../plugins/harness-core/hooks/protected-paths.sh) (consumer 트리에는 설치되지 않는다 — 플러그인 캐시에서 로드된다)
- 등록 위치: [`plugins/harness-core/hooks/hooks.json`](../../plugins/harness-core/hooks/hooks.json)
- 보완 관계인 permission `deny`: [`declarative/settings-fragment.json`](../../plugins/harness-core/declarative/settings-fragment.json) 의 `Read(./.env*)` 등은 프로젝트 상대 glob 이다. 이 훅은 그 glob 이 닿지 못하는 절대 경로 쪽을 맡는다. fragment 는 플러그인이 아니라 `harnessctl init` 이 `settings.json` 에 병합한다.
- 설정 template: [`declarative/templates/protected-paths.txt`](../../plugins/harness-core/declarative/templates/protected-paths.txt), [`declarative/templates/allowed-paths.txt`](../../plugins/harness-core/declarative/templates/allowed-paths.txt)
- Ownership model (managed vs. template, 재설치가 무엇을 덮어쓰는지): [`harnessctl`](../../plugins/harness-core/bin/harnessctl) 상단 주석

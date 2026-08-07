# large-file-veto

임계값을 넘는 파일을 stage 하려는 `git add` 를 차단한다.

## 동작

`PreToolUse` 이벤트, matcher `Bash` 로 등록된다 ([`hooks.json`](../../plugins/harness-core/hooks/hooks.json)).

1. `tool_name` 이 `Bash` 가 아니거나, command 에 `git add` 문자열이 없으면 exit 0.
2. `awk` 로 command 를 statement 구분자(`;` `&` `|` 개행)에서 먼저 쪼갠 뒤, **각 구간의 `git add` 를 하나도 빠짐없이** 뽑아 `read -r -a` 로 토큰화한다. 토큰은 세 갈래로 분류된다 — `-A`/`--all`/`.` 는 전체 열거, `-u`/`--update` 는 수정분 열거, 나머지 비플래그 토큰은 명시 경로 (앞뒤 따옴표 한 겹 제거).
3. 후보 파일을 모은다. 전체 열거는 `git ls-files --others --modified --exclude-standard`, 수정분 열거는 `git ls-files --modified`, 명시 경로가 디렉터리면 `find <dir> -type f -not -path '*/.git/*'` 로 펼친다. 기준 디렉터리는 `CLAUDE_PROJECT_DIR` (없으면 `pwd`).
4. 후보를 중복 제거한 뒤 `stat` 으로 크기를 재고, 임계값 초과 파일이 하나라도 있으면 목록을 stderr 에 찍고 exit 2. 없으면 exit 0.

Stage 이후에 큰 blob 을 걷어내려면 history rewrite 가 필요하다. 그래서 staging 시점에 막는다.

**한 명령 안에 `git add` 가 여러 번 있어도 순서는 무관하다.** 전부 검사하므로 어느 자리에 있든 큰 파일은 걸린다. 매칭은 `(^|[[:space:]])git[[:space:]]+add` 로 단어 경계를 잡아서 `legit add` 같은 문자열은 `git add` 로 오인하지 않는다.

`jq` 가 없으면 stderr 에 한 줄 남기고 exit 0 으로 self-disable 한다.

## 설정

| 변수 | 기본값 | 의미 |
| --- | --- | --- |
| `HARNESS_LARGE_FILE_BYTES` | `10485760` (10 MiB) | 초과 시 차단할 바이트 크기 |
| `CLAUDE_PROJECT_DIR` | `$(pwd)` | 상대 경로 해석과 `git ls-files` 실행의 기준 |

설정 파일은 없다. 임계값은 양방향으로 동작한다 — 올리면 통과하고, `HARNESS_LARGE_FILE_BYTES=1` 로 내리면 작은 파일도 차단된다 (verifier 가 두 방향 모두 확인).

## 통과하는 것

- **`git add` 만 있고 인자가 없는 경우** — 후보가 비어 있다.
- **존재하지 않는 경로** — `[ -f "$abs" ]` 를 통과하지 못하면 조용히 건너뛴다.
- **symlink** — 크기 검사 전에 `[ ! -L ]` 로 걸러진다. 링크를 따라가지 않는다.
- **`git add -A` 인데 큰 파일이 gitignore 된 경우** — `--exclude-standard` 때문에 후보에 들어오지 않는다. `git add` 자체도 그걸 stage 하지 않으므로 일치하는 동작이다.
- **`git add` 가 없는 명령** — `git status && git commit` 은 검사 대상이 아니다.

## 우회

정공법 순서대로: (1) Git LFS 로 추적, (2) 경로를 `.gitignore` 에 추가, (3) 한 명령에 한해 임계값 상향 — `HARNESS_LARGE_FILE_BYTES=<bytes> <command>`.

(3) 은 이 훅에 의도적으로 남긴 escape hatch 다. secret-scrubber 와 달리 "큰 파일" 은 사이트마다 정당한 예외가 있고, 되돌릴 수 없는 유출이 아니라 저장소 비대화 문제이기 때문이다.

## 한계

- **`-A` 는 함께 온 pathspec 을 무시한다.** `git add -A small.txt` 는 `small.txt` 만 스테이징하지만 훅은 워크트리 전체를 열거해 무관한 큰 파일로 차단한다. `-A` 를 보면 `enumerate_all` 을 켜고 명시 경로를 참고하지 않기 때문이다.
셸을 온전히 파싱하는 파서는 훅 자체보다 커진다. 아래는 모두 그 대가로 받아들인 것이다.

- **`git -C <dir> add` 는 감지되지 않는다.** 형제 훅 [ai-attribution-guard](ai-attribution-guard.md) 는 `git -C ... commit` 을 처리하는데, 이 차이는 원칙에 따른 것이지 누락이 아니다. 그쪽은 **명령 텍스트** 를 검사하므로 어디서 실행되든 의미가 같지만, 이 훅은 모든 인자를 디스크상의 디렉터리에 **해석** 한다. 여기서 `-C` 를 존중하려면 크기 조회까지 같은 기준으로 옮겨야 하고, 절반만 존중하면 엉뚱한 파일의 크기를 재게 된다.
- **공백이 든 따옴표 경로는 공백에서 쪼개진다** — `read -r -a` 가 IFS 로 자른다.
- **이미 추적 중인 같은 크기 파일도 차단된다** — 신규 여부를 보지 않고 크기만 본다.
- **`git add --dry-run <big>` 도 차단된다.** `--dry-run` 은 무시 플래그 목록에 있어 경로만 남고, 실제로 stage 하지 않는 명령인데도 exit 2 가 된다.
- **명시 경로 형태는 `.gitignore` 를 참조하지 않는다.** `git add big.bin` 은 `big.bin` 이 gitignore 되어 있어도 차단되므로, 차단 메시지가 권하는 (2) 번 fix 가 이 형태에서는 훅을 풀어주지 않는다.

## 검증

[`plugins/harness-core/scripts/verify-large-file-veto.sh`](../../plugins/harness-core/scripts/verify-large-file-veto.sh) — 40 케이스 (no-op 6, 임계값 미만 2, 초과 차단 6, **순서 회귀 5**, 임계값 양방향 2, 차단 메시지 4). 실제 `git init` 저장소와 `dd` 로 만든 11 MiB 파일을 fixture 로 쓴다 — `git ls-files` 를 실제로 호출하는 코드 경로이기 때문이다.

순서 회귀 5건이 "어느 자리에 있든 걸린다" 를 고정한다: 두 `git add` 중 **첫 번째** 에 큰 파일, **두 번째** 에 큰 파일, `;` 로 나뉜 경우, 둘 다 작은 경우, 그리고 `legit add` 오인 방지. 앞의 네 건은 이전 구현이 마지막 `git add` 만 검사해 `git add big.bin && git add ok.txt` 를 통과시키던 버그의 회귀 테스트다.

```
bash plugins/harness-core/scripts/verify-large-file-veto.sh
```

## 관련

- 훅 스크립트: [`plugins/harness-core/hooks/large-file-veto.sh`](../../plugins/harness-core/hooks/large-file-veto.sh) (consumer 트리에는 설치되지 않는다 — 플러그인 캐시에서 로드된다)
- 등록 위치: [`plugins/harness-core/hooks/hooks.json`](../../plugins/harness-core/hooks/hooks.json)
- [`declarative/settings-fragment.json`](../../plugins/harness-core/declarative/settings-fragment.json) 의 permission `allow` 에 `Bash(git add:*)` 가 있으므로, `git add` 에 대한 유일한 제동 장치가 이 훅이다.
- 같은 `Bash` matcher 를 공유하는 형제 훅: [secret-scrubber](secret-scrubber.md), [ai-attribution-guard](ai-attribution-guard.md)

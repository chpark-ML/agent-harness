<!--
prose-corpus.md — held-out prose for scripts/bench-claims.sh. DO NOT EDIT.

The claim checker's own verifier cannot show that its filter list is complete:
the cases and the regexes were written in the same sitting, so every "shape that
is never a claim" in that file is one the author had already thought of. This
corpus is the independent half — real technical prose, dense in numbers, written
without any knowledge of those regexes.

It is frozen on purpose. The first version of this benchmark rebuilt the corpus
from a git commit that predated the checker, and when the repository's history
was rewritten the benchmark silently produced an empty corpus and kept exiting
without a result. A fixture that depends on history is a fixture that history
can delete. This file is the fixture.

Provenance: the fourteen documents below (docs/hooks/*.md and ADR-0001..0008) as
of 2026-08-07. Thirteen predate check-claims.sh entirely. secret-scrubber.md
gained one paragraph about the checker afterwards, which is the single place
where independence is weaker than the rest.

Regenerating it would defeat the point. If the checker changes and the numbers
move, that is the signal — not a reason to refresh the corpus.
-->


<!-- ===== docs/hooks/ai-attribution-guard.md ===== -->

# ai-attribution-guard

AI 저작 표시가 git history 와 GitHub 에 남는 것을 막는다.

## 동작

`PreToolUse` 이벤트, matcher `Bash` 로 등록된다 ([`hooks.json`](../../plugins/harness-core/hooks/hooks.json)).

1. `tool_name` 이 `Bash` 가 아니거나 command 가 비면 exit 0.
2. command 를 소문자로 접은 사본(`$lc`)을 만들고, **메시지를 작성하는 명령인지** 부터 본다. 아니면 exit 0. 게이트 정규식:

   ```
   git( +(-c +[^ ]+|--[a-z][^ ]*|-[a-z]+))* +(commit|tag)|gh +(pr|issue) +(create|edit|comment)|gh +release +(create|edit)
   ```

   `git` 과 subcommand 사이의 global option 을 허용하는 부분이 핵심이다. 예전의 단순한 `git +commit` 매칭은 `git -C <repo> commit ...` 을 그대로 통과시켰다. `$lc` 는 소문자라 `-C` 가 `-c` 로 도착하므로 `-c +[^ ]+` 하나가 `-C <path>` 와 `-c <name>=<value>` 를 함께 커버한다. `git tag` 가 범위에 든 것은 annotated tag 가 메시지를 담기 때문이고, `comment`·`release` 는 `create` 와 마찬가지로 GitHub 에 산문을 게시하기 때문이다. 게이트를 넓게 잡는 쪽은 무해하다 — 귀속 표시가 없는 명령은 게이트를 통과해도 exit 0 이다.
3. 세 가지 형태를 순서대로 검사하고, 매치되면 무엇이 걸렸는지 이름을 붙여 stderr 에 찍고 exit 2.

`settings.json` 의 `includeCoAuthoredBy: false` 는 Claude Code 내장 trailer 부착을 끈다. 이 훅은 남은 경로 — 모델이 직접 손으로 써 넣은 메시지 — 를 맡는다. **명령 자체** 에 반응하므로 `--no-verify` 로 commit-msg 훅을 건너뛰어도 그대로 적용된다.

`jq` 가 없으면 stderr 에 한 줄 남기고 exit 0 으로 self-disable 한다.

## 패턴

| 형태 | 검사 대상 | 정규식 / 문자열 |
| --- | --- | --- |
| Co-author trailer | 소문자 사본 | `co-authored-by:.*(claude\|noreply@anthropic)` |
| Generated-with footer | 소문자 사본 | `generated with .{0,20}claude` |
| 로봇 이모지 | **원문 그대로** | `🤖` |

앞 둘은 소문자 사본을 보므로 대소문자를 가리지 않는다 (`CO-AUTHORED-BY: CLAUDE` 도 차단). 세 번째만 원문 `$cmd` 를 보는데, 이모지에는 대소문자 개념이 없어 접을 이유가 없기 때문이다.

trailer 규칙이 `anthropic` 단독이 아니라 `noreply@anthropic` 을 찾는 것이 핵심이다. `@anthropic.com` 주소를 쓰는 사람 동료는 진짜 공동 저자이고 그 trailer 는 살아남아야 한다. 봇 주소만 정확히 겨냥한다.

## 통과하는 것

정당한 언급은 귀속이 아니다. 아래는 모두 의도적으로 통과한다.

- **`CLAUDE.md` 파일명** — `git commit -m "Update CLAUDE.md language policy"`.
- **`.claude/` 디렉터리 경로** — `git commit -m "Move rules under .claude/rules/harness"`.
- **`anthropic` SDK·API 백엔드 언급** — `git commit -m "Pin anthropic to 0.40 for the tool_use fix"`.
- **사람 co-author trailer** — `Co-Authored-By: Jane Doe <jane@example.com>`. 막는 것은 AI 귀속이지 공동 저작 표기 자체가 아니다.
- **Anthropic 소속 사람 동료의 trailer** — `Co-Authored-By: Jane <jane@anthropic.com>` 은 통과한다. 차단되는 것은 봇 주소 `noreply@anthropic.com` 쪽이다.
- **메시지를 쓰지 않는 명령** — `grep -rn "Co-Authored-By: Claude" .` 는 게이트를 통과하지 못하고, `git tag -l` 은 게이트에 들어와도 검사할 산문이 없어 exit 0. 이 훅으로 차단된 trailer 를 *찾는* 작업이 막히면 안 되므로 앞쪽은 필요한 성질이다.
- **평범한 commit** — `git commit -m "Add retry to the upload path"`.

## 우회

**없다.** 이건 임계값이 아니라 정책이고, 환경변수 escape hatch 를 두면 그 변수가 곧 표준 절차가 된다. 오탐이면 (아래 한계 참고) 문구를 바꿔 재시도하고, 패턴 자체가 틀렸다면 하네스 저장소에서 고친다.

**고칠 사본이 애초에 consumer 트리에 없다.** 훅은 플러그인으로 배포되어 플러그인 캐시에 있고 Claude Code 가 거기서 로드한다 — `docs/hooks/` 의 여섯 훅 모두 마찬가지다. 그래서 차단 메시지를 받고 "이 훅이 정확히 뭘 보는지" 확인하려 해도 자기 저장소에서는 열 파일이 없다. 스크립트를 읽으려면 [agent-harness](https://github.com/chpark-ML/agent-harness) 저장소의 `plugins/harness-core/hooks/` 를 보거나 `/plugin` 으로 설치된 플러그인을 조회할 것. 고치는 자리도 같은 곳이다.

## 한계

아래 두 오탐은 알면서 남긴 것이다. 스크립트 헤더에도 적혀 있다.

- **관계없는 🤖 도 차단된다.** `git commit -m "fix the 🤖 emoji rendering bug"` 처럼 이모지 자체가 주제여도 exit 2 다. 문맥 판정이 없다. 그럼에도 남긴 이유는 이 규칙이 **"Claude" 라는 단어 없이 쓰인 generated-with footer 를 잡는 유일한 규칙** 이기 때문이다. 없애면 그 형태가 통째로 빠져나간다.
- **`generated with … claude` 산문이 오탐된다.** `git commit -m "note that fixtures were generated with the claude api"` 는 귀속이 아니지만 차단된다.

나머지 gap:

- **이름이 Claude 인 사람은 여전히 차단된다.** `Co-Authored-By: Claude Dupont <claude.dupont@example.com>` 은 exit 2 다. 주소 기준 오탐은 고쳐졌지만 이름 기준은 남아 있고, 고칠 방법이 없다 — trailer 값에서 `claude` 를 찾는 이상 실명과 모델명을 구분할 수 없다. verifier 에 **차단된다고 단정하는 known-limitation 케이스** 로 박혀 있으므로, 이 동작이 바뀌면 테스트가 알려 준다.
- **게이트 밖 명령.** `git merge -m`, `git notes add -m`, `git revert` 는 메시지를 담지만 검사되지 않는다. 현재 커버는 `git commit`·`git tag`, `gh pr|issue create|edit|comment`, `gh release create|edit` 까지다.
- **stdin·파일 경유 메시지는 원리적으로 못 본다.** `git commit -F msg.txt` 는 내용이 command 문자열에 없으므로 이 훅으로는 잡을 수 없다. 에디터로 여는 `git commit` (`-m` 없이) 도 같다.

## 검증

[`plugins/harness-core/scripts/verify-ai-attribution-guard.sh`](../../plugins/harness-core/scripts/verify-ai-attribution-guard.sh) — 33 케이스. "게이트 우회 시도" 4건(`git -C`, `git -c`, `git --no-pager`, 대문자 trailer)은 게이트 정규식을 지금 모양으로 만든 실제 사례다.

trailer 경계는 세 방향으로 고정되어 있다 — `@anthropic.com` 사람 동료는 통과, 봇 주소 `noreply@anthropic` 는 "Claude" 라는 단어 없이도 차단, 그리고 이름이 Claude 인 사람은 **차단된다고 단정** 한다. 마지막 것은 고칠 수 없는 오탐을 테스트로 박아 둔 것이라 위 `## 한계` 가 코드와 어긋날 수 없다.

```
bash plugins/harness-core/scripts/verify-ai-attribution-guard.sh
```

## 관련

- 훅 스크립트: [`plugins/harness-core/hooks/ai-attribution-guard.sh`](../../plugins/harness-core/hooks/ai-attribution-guard.sh) (consumer 트리에는 설치되지 않는다 — 플러그인 캐시에서 로드된다)
- 등록 위치: [`plugins/harness-core/hooks/hooks.json`](../../plugins/harness-core/hooks/hooks.json)
- 짝이 되는 scalar `includeCoAuthoredBy: false`: [`declarative/settings-fragment.json`](../../plugins/harness-core/declarative/settings-fragment.json) — 훅과 달리 플러그인이 아니라 `harnessctl init` 이 `settings.json` 에 병합한다. 둘은 같은 정책의 두 경로다 — scalar 가 내장 부착을 끄고, 훅이 손으로 쓴 것을 막는다.
- 정책 원문 R2: [`declarative/rules/core/workflow.md`](../../plugins/harness-core/declarative/rules/core/workflow.md)
- 같은 `Bash` matcher 를 공유하는 형제 훅: [secret-scrubber](secret-scrubber.md), [large-file-veto](large-file-veto.md)

<!-- ===== docs/hooks/check-uncommitted.md ===== -->

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

<!-- ===== docs/hooks/large-file-veto.md ===== -->

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

<!-- ===== docs/hooks/protected-paths.md ===== -->

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

<!-- ===== docs/hooks/secret-scrubber.md ===== -->

# secret-scrubber

리터럴 secret 을 실어 나르는 Bash 명령을 차단한다.

## 동작

`PreToolUse` 이벤트, matcher `Bash` 로 등록된다 ([`hooks.json`](../../plugins/harness-core/hooks/hooks.json) 의 두 번째 `PreToolUse` 블록. 같은 블록에서 secret-scrubber → large-file-veto → ai-attribution-guard 순으로 실행).

1. `tool_name` 이 `Bash` 가 아니거나 `tool_input.command` 가 비면 즉시 exit 0.
2. `PATTERNS` 배열을 선언 순서대로 `grep -qE`. **첫 매치에서 승부가 난다** — 배열 순서가 곧 우선순위이고, 차단 메시지에 실리는 label 도 첫 매치의 것이다.
3. 매치 시 exit 2, 매치 없으면 exit 0. Exit 2 의 stderr 는 모델에게 피드백으로 돌아가므로, 메시지는 탐지된 종류와 fix 를 둘 다 담는다.

**파일 내용은 스캔하지 않는다.** Bash 명령만 본다. Fixture·문서·테스트는 키 모양 문자열을 정당하게 포함하고, 오탐하는 guard 는 결국 꺼지기 때문이다 (스크립트 헤더).

`jq` 가 없으면 stderr 에 한 줄 남기고 exit 0 으로 self-disable 한다.

## 패턴

| 종류 | 정규식 |
| --- | --- |
| Anthropic API key | `sk-ant-api03-[A-Za-z0-9_-]{40,}` |
| OpenAI scoped key (proj/svcacct/admin) | `sk-(proj\|svcacct\|admin)-[A-Za-z0-9_-]{40,}` |
| OpenAI legacy API key | `sk-[A-Za-z0-9]{40,}` |
| GitHub personal access token | `ghp_[A-Za-z0-9]{36,}` |
| GitHub token (oauth/user/server/refresh) | `gh[ousr]_[A-Za-z0-9]{36,}` |
| GitHub fine-grained token | `github_pat_[A-Za-z0-9_]{40,}` |
| Slack token | `xox[abprs]-[A-Za-z0-9-]{20,}` |
| AWS access key ID | `AKIA[0-9A-Z]{16}` |
| AWS temporary access key | `ASIA[0-9A-Z]{16}` |
| Google API key | `AIza[0-9A-Za-z_-]{35}` |
| PEM private key block | `-----BEGIN[A-Z ]*PRIVATE KEY-----` |

여기에 vendor 무관한 env-style 할당 규칙이 하나 더 있다:

```
(API_KEY|APIKEY|SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE_KEY|ACCESS_KEY)=["']?[A-Za-z0-9+/=._-]{12,}
```

이름 부분이 anchor 되어 있지 않아 substring 으로 걸린다 — `MYSQL_PASSWORD=`, `DEPLOY_PRIVATE_KEY=`, `APP_SECRET=` 모두 매칭된다. 값은 12자 이상인 리터럴이어야 한다.

**두 OpenAI 항목의 문자 클래스가 다른 것은 실수가 아니다.** scoped 계열(`sk-proj-`·`sk-svcacct-`·`sk-admin-`)은 실제로 `_`·`-` 를 포함하지만 legacy `sk-` 는 순수 base62 다. 형식이 다르므로 클래스도 다르다 — 아래 `## 통과하는 것` 에 이걸 "통일" 했을 때 무슨 일이 벌어졌는지 적어 두었다.

## 통과하는 것

- **`API_KEY=$REAL_KEY <command>`** 와 **`TOKEN=$(cat ~/.token) ...`** — 리터럴 `$` 가 값 문자 클래스 밖이라 매칭되지 않는다. 차단 메시지가 권장하는 fix 가 그 자체로 통과해야 하므로 이건 설계다. 여기를 "고치면" 권장 fix 가 막힌다.
- **12자 미만 값** (`DEBUG_TOKEN=ab12`) 과 **이름이 목록 밖인 긴 값** (`OUTPUT_PATH=/very/long/path/to/output.json`).
- **`sk-` 를 언급만 하는 산문** — 키 모양이 아니면 걸리지 않는다.
- **`sk-` 로 시작하는 긴 kebab-case 식별자** — `git switch -c sk-refactor-the-whole-data-loading-layer-for-real` 은 통과한다. legacy `sk-` 클래스에 `-` 가 없기 때문이다. 한때 "scoped 쪽과 클래스가 다른 건 오타 같다" 는 판단으로 legacy 를 `[A-Za-z0-9_-]` 로 넓혔더니 이런 브랜치 이름이 전부 키로 오인돼 차단됐다. 넓혀서 얻는 것은 없었다 — 밑줄이 든 legacy 키 형식은 존재하지 않는다. 두 케이스가 allow 로 박혀 있으니 다시 "정리" 하지 말 것.
- **Bash 이외의 tool** — `Read`/`Write` 는 matcher 자체에 없다.

## 우회

**없다.** 환경변수 escape hatch 를 의도적으로 두지 않았다. 리터럴이 셸에 닿은 시점에 그 값은 이미 history·process table·로그에 남아 있고 사후의 실질적 복구는 rotation 뿐이며, 끄는 스위치를 주면 그 스위치가 곧 기본 사용법이 된다. 절차는 하나다 — 값을 rotate 한 뒤 셸 변수·secret manager 경유로 명령을 재발행.

## 한계

- **공백으로 구분된 비밀은 잡지 못한다.** 규칙이 `이름=값` 형태만 본다. `aws configure set aws_secret_access_key <값>` 은 장기 자격증명을 심는 정석적인 방법이면서 환경변수를 거치지 않는 유일한 형태인데, 통과한다. 플래그 형태(`--api-key <값>`)도 마찬가지다. 값 부분을 이름 없이 판정하려면 "긴 base62 문자열" 을 비밀로 취급해야 하고, 그러면 해시·UUID·경로가 전부 걸린다.
- **명백한 플레이스홀더도 차단된다.** `TOKEN=REPLACE_ME_BEFORE_RUN`, `API_KEY=your-key-here`, 그리고 AWS 가 문서에 싣는 예시 키 `AKIAIOSFODNN7EXAMPLE` 까지. 마지막 것이 특히 성가시다 — 헤더가 *fixture 는 키 모양 문자열을 정당하게 담는다* 는 이유로 파일 내용을 검사하지 않는다고 해놓고, 그 fixture 를 셸에서 만드는 것은 막는다. 플레이스홀더 deny-list 를 두면 해결되지만, 그 목록 자체가 유지보수 대상이 되므로 지금은 알려진 마찰로 남긴다.
- **env-style 값 클래스에 `/`·`.` 가 포함되어, 이름이 목록에 걸리기만 하면 secret 아닌 긴 리터럴도 차단된다** (`TOKEN=/very/long/path/to/output.json` → block). 의도적으로 수용한 오탐이다 — 클래스를 좁히면 base64 와 점으로 구분된 토큰이 빠져나간다 (스크립트 헤더).
- 명령이 아니라 파일 쓰기나 MCP tool 로 나가는 유출은 범위 밖이다 (위의 파일 미스캔 결정의 대가).

- **픽스처는 *탐지되게* 가짜여야 한다.** 이 저장소를 public 으로 올릴 때 GitHub push protection 이 우리 Slack 토큰 픽스처를 진짜 시크릿으로 판정해 푸시를 거부했다 (`evals/incidents.sh`, `verify-secret-scrubber.sh`). 우리 정규식은 `xox[abprs]-` 뒤 20자만 보지만 GitHub 은 실제 토큰 구조를 보므로, `xoxb-EXAMPLE-NOT-A-REAL-TOKEN-000000` 처럼 **양쪽 판정이 갈리는** 값을 쓴다 — 우리 것에는 걸리고 스캐너에는 안 걸린다. 시크릿 탐지기를 시험하는 픽스처는 그 자체가 시크릿처럼 보이므로, 새 패턴을 추가할 때마다 이 충돌을 확인해야 한다.

## 검증

[`plugins/harness-core/scripts/verify-secret-scrubber.sh`](../../plugins/harness-core/scripts/verify-secret-scrubber.sh) — 37 케이스.

`sk-` 계열은 이제 양방향으로 고정되어 있다: scoped 세 형식(`proj`·`svcacct`·`admin`)과 legacy base62 는 block, `sk-` 로 시작하는 긴 kebab-case 식별자 두 건은 allow. 넓히는 방향의 block 케이스만 있었을 때 이 회귀가 보이지 않았기 때문에, 반대 방향을 함께 넣은 것이 핵심이다.

```
bash plugins/harness-core/scripts/verify-secret-scrubber.sh
```

## 관련

- 훅 스크립트: [`plugins/harness-core/hooks/secret-scrubber.sh`](../../plugins/harness-core/hooks/secret-scrubber.sh) (consumer 트리에는 설치되지 않는다 — 플러그인 캐시에서 로드된다)
- 등록 위치: [`plugins/harness-core/hooks/hooks.json`](../../plugins/harness-core/hooks/hooks.json)
- 같은 `Bash` matcher 를 공유하는 형제 훅: [large-file-veto](large-file-veto.md), [ai-attribution-guard](ai-attribution-guard.md)
- 보완 관계인 permission `deny`: [`declarative/settings-fragment.json`](../../plugins/harness-core/declarative/settings-fragment.json) 의 `Read(./.env*)`, `Read(./secrets/**)`, `Read(./**/.credentials*)` — 이쪽은 secret 을 *읽는* 경로를, 훅은 secret 을 *타이핑하는* 경로를 막는다. fragment 는 `harnessctl init` 이 병합한다.
- `harnessctl doctor` 는 이 훅에 `AKIA…` 샘플 키를 직접 먹여 차단 여부를 확인한다 — 플러그인이 실제로 로드됐는지 보는 가장 빠른 방법이다.

<!-- ===== docs/hooks/session-brief.md ===== -->

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

<!-- ===== docs/adr/0001-harness-scope.md ===== -->

# ADR-0001: 하네스의 범위는 에이전트 레이어, 구성은 core + 선택 모듈

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

참조한 두 하네스는 서로 다른 실패를 보여줬다. 하나는 에이전트 레이어와 ML 스캐폴딩(Hydra·registry·tracking)이 한 저장소에 섞여 있다가 약 4000줄을 삭제하며 에이전트 레이어만 남겼다. 다른 하나는 규약·훅·스킬이 연구 도메인(EHR·논문·LaTeX)에 깊이 묶여 있어 다른 프로젝트가 그대로 쓸 수 없었다 — 실제로 그 저장소는 "일반화 가능한 조각만 별도 저장소로 단방향 추출한다" 를 스스로 선언해 두고 있다.

동시에 제품·서비스 개발과 연구 작업은 필요한 규칙과 스킬이 다르다. 하나로 합치면 어느 프로젝트에서든 절반은 노이즈가 된다.

## Decision

본 저장소는 **Claude Code 에이전트 레이어만** 다룬다 — 규약, 권한, 훅, 스킬, 그리고 그것을 컨슈머 프로젝트에 넣는 설치기. 애플리케이션 코드·빌드 시스템·언어별 스캐폴딩·백엔드 연동은 컨슈머의 책임이다.

구성은 **항상 설치되는 `core` + 선택 설치되는 모듈** (`dev`, `research`). 모듈은 `install.sh --with <names>` 로 고른다.

편입 기준은 하나다: **다른 도메인·다른 스택의 프로젝트에 그대로 설치해도 말이 되는가.**

본 저장소는 위에 언급한 추출 대상 저장소와 별개다. 연구 전용이 아니라 제품·서비스 개발까지 포함하는 범용 하네스이며, 참조 저장소들과 코드 공유 관계도 없다.

## Consequences

- 도메인 특화 자산(의료 PHI 스크러버, LaTeX 빌드, 문헌 조사 스킬)은 여기 들어오지 않는다. 필요한 프로젝트는 자기 `.claude/` 에 직접 두거나 자기 모듈을 만든다.
- 모듈 경계는 판단을 요구한다. "PR 리뷰 체크리스트" 는 `dev`, "실험 노트 규율" 은 `research`, "AI 귀속 금지" 는 core — 이 판정을 매번 해야 한다.
- 컨슈머는 하나의 병합된 `.claude/` 를 받는다. core 와 모듈이 같은 경로에 파일을 두면 설치가 중단된다(`install.sh` 의 충돌 검사).
- 모듈이 늘어날수록 조합 수가 는다. 검증은 `--with dev,research` 전체 조합 하나와 모듈 교체 왕복만 커버한다 — 모듈들이 파일 경로를 공유하지 않으므로 이것으로 충분하다.

## Alternatives considered

- **단일 통합 `.claude/`** — 단순하지만 제품 프로젝트에 실험 노트 규율이, 연구 프로젝트에 릴리스 규약이 섞인다.
- **core 만, 모듈 없음** — 가장 작지만 두 작업 유형의 실질적 차이를 사용자가 매번 손으로 메워야 한다.
- **Claude Code plugin 으로 패키징** — 처음에는 "컨슈머가 파일을 직접 열어보고 고치기 어렵다" 를 거절 사유로 적었다. **그 사유는 틀렸다.** 컨슈머가 실제로 열어 고치는 것은 `CLAUDE.md` 와 경로 가드 설정뿐이고, 그것들은 애초에 플러그인이 나를 수 없어 어차피 컨슈머 트리에 남는다. 반대로 훅·검증기는 고쳐 쓰라고 배포하는 물건이 아니다 — 고칠 것은 상류에서 고친다 (`CLAUDE.md` §5). 진짜 제약은 읽기 쉬움이 아니라 **플러그인이 무엇을 나를 수 없는가** 였다 ([ADR-0008](0008-plugin-declarative-split.md)).
- **템플릿 저장소 (clone 해서 시작)** — 업데이트 경로가 없다. 하네스는 고쳐서 다시 배포되는 물건이다.

---

> **보정 (2026-08-06, [ADR-0008](0008-plugin-declarative-split.md) 이후).** 범위 결정은 그대로 유효하다 — 하네스는 여전히 에이전트 레이어만 다루고, 여전히 core + 선택 모듈이며, 편입 기준도 그대로다. 바뀐 것은 배포 형태다. 모듈은 플러그인 프로파일(`harness-dev` · `harness-research` · 언어 프로파일)이 됐고, 선택은 `install.sh --with <names>` 가 아니라 `claude plugin install harness-<profile>@agent-harness` 와 `harnessctl init --with <names>` 로 나뉘어 이뤄진다. 위 alternatives 의 플러그인 항목이 든 거절 사유는 관측으로 반증됐고, 실제 경계는 플러그인이 permissions·`CLAUDE.md`·`rules` 를 나를 수 없다는 것이었다. 편입 기준이 **core 를 규율하지 opt-in 프로파일을 규율하지 않는다** 는 점은 [ADR-0009](0009-external-dependencies.md) 가 따로 다룬다.

<!-- ===== docs/adr/0002-hook-contract.md ===== -->

# ADR-0002: 훅은 bash 3.2 + jq 로만 작성하고, 설치기도 jq 를 요구한다

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

훅은 모든 도구 호출마다 실행된다. 런타임 의존이 늘어날수록 하네스는 "설치했는데 안 도는" 상태가 되기 쉽고, 그 상태는 조용하다 — 가드가 안 돌아도 아무 일도 안 일어난 것처럼 보인다.

바닥 환경은 macOS 의 `/bin/bash` 3.2 다 (2007년판, Apple 이 라이선스 때문에 갱신하지 않는다). 참조 하네스의 검증기들은 `mapfile` 을 쓰며 "requires bash 4+" 를 선언하고 있었고, 다른 하네스의 포맷 훅은 macOS 호스트에서 조용히 반쪽만 돌고 있었다.

한편 참조 훅 하나는 stdin 파싱에 `python3` 을 쓰고 있어 자신이 속한 저장소의 bash+jq 규약을 위반한 상태였다.

## Decision

훅은 **bash 3.2 와 jq 로만** 작성한다. Python·Node·perl 금지. `mapfile`, 연관 배열, `${x^^}` 같은 bash 4 문법 금지. `set -u` 에서 빈 배열은 `"${arr[@]+"${arr[@]}"}"` 로 전개한다.

훅은 `jq` 가 없으면 **stderr 한 줄과 함께 exit 0** 으로 자기 비활성화한다. 가드의 부재가 작업의 중단이 되어서는 안 된다.

**설치기는 반대로 jq 를 요구하고, 없으면 아무것도 쓰지 않고 중단한다.** *(ADR-0008 이후: 그 preflight 는 `harnessctl` 에 있다. `install.sh` 는 플러그인을 먼저 깐 뒤 harnessctl 에서 멈추므로, "아무것도 쓰지 않고" 는 선언적 절반에만 해당한다.)* 훅이 jq 를 요구하므로 jq 없는 설치는 전부 자기 비활성화된 가드를 배포하는 것이다. 조용히 그렇게 하느니 설치 실패가 낫다.

`make syntax` 가 배포되는 모든 스크립트를 `bash -n` 으로 파싱하고, CI 가 이를 macOS 의 `/bin/bash` 로도 실행한다 — 테스트가 닿지 않는 에러 경로의 bash 4 문법까지 잡기 위해서다.

## Consequences

- 훅 로직이 장황해진다. 배열 조작·문자열 처리를 3.2 어휘로 써야 하고, `large-file-veto` 의 `git add` 인자 파싱 같은 것은 awk 한 줄을 거쳐 간다.
- jq 없는 환경은 설치 자체가 막힌다. 규약·스킬만 원하는 사용자에게는 과한 요구지만, 그 경우에도 jq 는 한 줄로 설치된다.
- 훅이 자기 비활성화하면 그 사실이 stderr 한 줄로만 보인다. 사용자가 놓칠 수 있다 — 설치기의 preflight 가 이를 앞당겨 막는 이유다.
- 새 훅에 스크립트 언어를 쓰고 싶어지는 순간이 온다. 그때는 이 ADR 을 superseded 로 바꾸는 PR 을 먼저 낸다.

## Alternatives considered

- **Python 훅 허용** — 파싱은 쉬워지지만 인터프리터 버전·가상환경 상태에 의존하게 되고, 그 실패는 조용하다.
- **jq 없을 때 python3 폴백** (참조 설치기의 방식) — 같은 병합 로직 두 벌을 유지해야 하고, 둘이 어긋나면 손상되는 것은 사용자의 `settings.json` 이다. 훅이 이미 jq 를 요구하는 이상 이 폴백이 구하는 시나리오는 "가드 없는 하네스" 뿐이다.
- **bash 4 요구 + Homebrew bash 안내** — 사용자에게 환경 변경을 강요하고, 강요가 통하지 않는 곳(CI 이미지, 동료의 노트북)에서 조용히 깨진다.

<!-- ===== docs/adr/0003-verification-mandate.md ===== -->

# ADR-0003: 모든 가드는 자동 검증기와 함께 배포한다

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

훅은 정상 경로에서 아무 출력도 내지 않는다. 망가진 훅과 조용히 통과시키는 훅은 사용자 입장에서 구별되지 않으며, 그 상태는 몇 달을 갈 수 있다. 정규식 하나를 고치다 통과 조건을 뒤집어도 아무도 모른다.

반대 방향의 실패도 같은 비용이다. 오탐을 내는 가드는 매 턴 환경변수로 꺼지고, 꺼진 가드는 없는 가드다.

설치기는 더하다. 실패하면 사용자의 `settings.json` — 우리가 만들지 않은, 되돌릴 수 없는 데이터 — 가 손상된다.

## Decision

**검증 없이 머지된 가드는 가드가 아니라 장식이다.** 모든 훅은 `plugins/harness-core/scripts/verify-<name>.sh` 와 함께 배포한다.

각 검증기의 요건:

- **8케이스 이상**, 세 종류를 모두 포함: **no-op** (훅이 끼어들면 안 되는 입력), **block** (막아야 하는 입력), **boundary** (막을 것과 닮았지만 통과해야 하는 입력).
- 공용 `_verify-lib.sh` 의 `run_case` / `expect` / `expect_match` 를 쓴다. 훅은 `env -i` 로 격리된 환경, mktemp 작업 디렉터리, 검증기와 같은 인터프리터에서 실행된다.
- 마지막에 `X / Y passed`, 실패 시 non-zero 종료.
- 차단 메시지가 *무엇이 걸렸는지* 와 *어떻게 푸는지* 를 담는지도 검증한다. 메시지는 모델이 읽고 행동하는 인터페이스이므로 동작의 일부다.

`plugins/harness-core/scripts/verify-hooks.sh` 가 `verify-*.sh` 를 자동 발견해 실행한다 — 등록 단계가 없으므로 도는 집합이 존재하는 집합과 어긋날 수 없다.

**설치기도 같은 의무를 진다.** `scripts/verify-install.sh` 가 scratch 컨슈머를 만들어 install → 재설치 → 템플릿/managed tier → 모듈 교체 → uninstall 왕복을 검사한다. 가장 중요한 단정은 *uninstall 후 `settings.json` 이 원본과 정준 동일* 하다는 것이다.

사고가 나면 **회귀 케이스를 먼저 추가하고** 고친다.

## Consequences

- 새 훅의 비용이 두 배가 된다. 이것은 의도된 것이다 — 검증할 수 없는 가드는 애초에 만들지 않는 편이 낫다.
- 세 종류 케이스 요건이 boundary 를 강제한다. Block 케이스만 있는 검증기는 오탐에 대해 아무것도 증명하지 않고, 가드가 실제로 죽는 원인은 오탐이다.
- CI 가 두 환경(ubuntu bash 5, macOS bash 3.2)에서 전체를 돌리므로 머지 시간이 늘어난다.
- 현재 규모: 훅 검증기 6개 / 192 케이스, harnessctl 90 assertion, frontmatter 9. 최신 수치는 [`agent-layer.md` §4](../agent-layer.md) 가 SOT — 여기 적힌 숫자는 결정 시점의 기록이다.

## Alternatives considered

- **수동 검증 절차 문서** — 처음 몇 번은 돌고, 그 뒤로는 안 돈다.
- **훅에 대한 스모크 테스트만** — 망가진 훅은 잡지만 오탐은 못 잡는다. 오탐이 더 흔한 사인이다.
- **설치기는 검증 면제** (참조 하네스는 설치기 검증기를 "비례하지 않는다" 며 삭제했다) — 그 판단은 143줄짜리 단일 복사 설치기에 대한 것이었다. 여기 설치기는 JSON 병합과 대칭 제거를 하므로 실패 시 잃는 것이 다르다.

<!-- ===== docs/adr/0004-single-source-of-truth.md ===== -->

# ADR-0004: `docs/agent-layer.md` 가 단일 SOT 이고, 설치되는 index 파일은 만들지 않는다

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

참조 하네스 하나는 `.claude/README.md` 에 계층 다이어그램과 rule·skill·agent·hook 인벤토리를 유지하고, 그 문서 안에 "무엇이든 추가하면 이 index 를 갱신한다" 는 자기 유지 규칙(§8)까지 두고 있었다. 그럼에도 탐색 시점에 확인된 drift 가 최소 두 건이었다 — index 가 `settings.json` 의 실제 값과 다른 값을 적고 있었고, 훅 목록에서 실제 등록된 훅 하나가 빠져 있었다.

같은 저장소가 별도 로드맵 문서를 두었다가 drift 를 이유로 삭제한 이력도 있다.

교훈은 "규칙을 더 강하게 쓰라" 가 아니다. **손으로 유지하는 인벤토리는 규칙이 있어도 drift 한다**, 그리고 drift 한 index 는 없는 index 보다 나쁘다 — 읽는 쪽이 그것을 믿기 때문이다.

## Decision

**`docs/agent-layer.md` 가 하네스의 범위·인벤토리·backlog 에 대한 유일한 출처다.** 이 셋을 바꾸는 변경은 이 파일만 갱신한다. README 나 별도 로드맵에 같은 내용을 복제하지 않는다.

**컨슈머에 설치되는 index 파일(`.claude/README.md` 류)은 만들지 않는다.** 컨슈머는 파일을 받고, 인벤토리는 하네스 저장소 한 곳에 있다.

**기계로 확인 가능한 것은 문서에 적는 대신 검증한다.**

- 설치되는 파일 목록은 harnessctl 의 계획 코드 한 곳에서 나온다 — 문서에 옮겨 적을 목록이 없다.
- 배포되는 모든 스크립트가 실행 가능한지, 모든 fragment·매니페스트가 유효한 JSON 인지, `hooks.json` 의 모든 등록이 실재하는 파일로 해석되는지는 `scripts/verify-install.sh` 가 CI 에서 확인한다. *(ADR-0008 이후 `templates.txt` 는 없다 — tier 는 harnessctl 의 계획 코드가 선언한다.)*

즉 `agent-layer.md` 에는 **기계가 확인할 수 없는 것** 만 남긴다: 왜 이 하네스가 존재하는지, 무엇이 범위 밖인지, 다음에 무엇을 만들지, 왜 어떤 것을 안 만들기로 했는지.

## Consequences

- `agent-layer.md` 의 §3 인벤토리 수치(훅 6, 스킬 4 등)는 여전히 손으로 유지되고 여전히 drift 할 수 있다. 다만 그것이 틀려도 잃는 것은 요약의 정확도일 뿐, 설치 동작이 아니다.
- 컨슈머가 "이 하네스가 뭘 설치했나" 를 알려면 `.claude/harness-manifest.json` 을 보거나 하네스 저장소를 봐야 한다. manifest 는 기계 생성이므로 언제나 정확하다.
- 새 기여자는 README 가 아니라 `agent-layer.md` 로 안내된다.

## Alternatives considered

- **자기 유지 규칙을 명시한 index 파일** — 참조 하네스가 정확히 이것을 했고 drift 했다.
- **index 자동 생성 (스크립트로 트리에서 만들어 커밋)** — drift 는 막지만, 생성된 파일이 트리를 다시 서술할 뿐이라 트리를 직접 보는 것보다 나은 점이 없다.
- **README 를 SOT 로** — README 는 컨슈머용 quick-start 다. 청중이 다르면 문서도 다르다.

<!-- ===== docs/adr/0005-installer.md ===== -->

# ADR-0005: 설치기는 오버레이 트리 · 2-tier · 마커 병합 · manifest 로 구성한다

- **Status**: Accepted — 3번(마커 기반 훅 병합)은 [ADR-0008](0008-plugin-declarative-split.md) 로 대체됨
- **Date**: 2026-08-06

## Context

설치기는 컨슈머의 `.claude/settings.json` 을 건드린다. 그 파일에는 우리가 만들지 않은 것 — 모델 설정, 플러그인, 사용자 자신의 훅과 권한 — 이 들어 있고, 그것을 잃으면 되돌릴 방법이 없다.

참조 자산 두 개가 각각 절반씩 답을 갖고 있었다. 하나는 `settings.json` 을 통째로 덮어쓰지 않고 jq 로 파싱-재직렬화하며 매 쓰기 전 타임스탬프 백업을 남기고, 설치와 제거가 같은 함수를 반대 방향으로 호출한다. 다른 하나는 파일을 두 tier(덮어쓰기 / 최초 1회)로 나누고, 손으로 유지하는 for 루프 목록으로 복사한다.

둘 다 다루지 않는 문제가 하나 있다: 전자는 `settings.json` 의 **단일 키** 하나만 병합한다. 여기서는 배열 안의 훅 등록 여러 개를 컨슈머의 등록과 섞어야 하고, 나중에 우리 것만 골라내야 한다.

## Decision

네 가지를 채택한다.

**1. 오버레이 트리가 곧 파일 목록.** `<overlay>/files/` 아래를 그대로 컨슈머 경로에 복사한다. `install.sh` 는 `find` 로 훑으므로 목록을 유지하지 않는다 — 새 파일을 넣으면 설치되고, 등록을 잊을 수 없다.

> *ADR-0008 이후*: 이 성질은 사라지지 않고 **자리를 옮겼다.** 훅·스킬·커맨드·검증기는 플러그인 컴포넌트가 됐고, 플랫폼이 규약 경로에서 직접 발견하므로 목록이 여전히 필요 없다. 남은 선언적 페이로드는 7개 파일뿐이라 `harnessctl` 이 트리를 훑는 대신 명시적으로 계획을 세운다 — 모듈 rule 만 `rules/<module>/*.md` 로 글롭한다. 목록 유지 부담이 없다는 결론은 같고, 수단만 다르다.

**2. 2-tier.** *managed* 는 재설치 시 최신으로 덮어쓴다. *template* 은 최초 1회만 복사하고 이후 컨슈머 소유다 (`CLAUDE.md`, 경로 가드 설정 파일). 각 오버레이의 `templates.txt` 가 선언한다.

> *ADR-0008 이후*: 그대로 유효하다. tier 선언만 `templates.txt` 에서 `harnessctl` 의 계획 코드(`add` / `addt`)로 옮겼다.

**3. 마커 기반 훅 병합.** *(→ [ADR-0008](0008-plugin-declarative-split.md) 로 **대체됨**. 훅은 이제 플러그인이 `hooks/hooks.json` 에서 `${CLAUDE_PLUGIN_ROOT}` 로 등록하고, 설치기는 `settings.json` 의 `hooks` 블록을 읽지도 쓰지도 않는다. 마커도, strip-then-append 도, 그 둘을 위해 있던 jq 프로그램도 삭제됐다. 아래 본문은 기록으로 남긴다.)* 모든 하네스 훅은 `.claude/hooks/harness/` 아래에 설치되고, 등록 command 문자열에 그 경로 조각이 들어간다. 병합은 **strip-then-append** — 각 이벤트에서 마커를 포함한 등록만 제거한 뒤 fragment 의 것을 붙인다. 그래서 재설치가 멱등이고, 제거가 컨슈머의 훅을 건드리지 않으며, 손으로 편집된 `settings.json` 도 중복이 쌓이지 않고 수렴한다.

**4. `.claude/harness-manifest.json` 이 그 외 전부의 영수증.** 실제로 추가한 permission 문자열, 설정한 스칼라 키, 우리가 만든 JSON 컨테이너의 경로, `.gitignore` 에 붙인 줄, 설치한 파일 목록, 선택된 모듈. 제거는 이 영수증만 되돌린다.

> *ADR-0008 이후*: 항목 구성은 그대로다. 달라진 것은 "그 외" 의 범위가 줄었다는 것 — 훅이 병합 대상에서 빠지면서 `settings.json` 에서 설치기가 손대는 것은 permissions 3티어와 스칼라 하나(`includeCoAuthoredBy`)뿐이고, 영수증도 그만큼만 기록한다.

파생되는 성질 둘:

- **모든 설치는 먼저 이전 설치분을 되돌린 뒤 다시 적용한다.** 추가분은 언제나 원본 상태 기준으로 계산되므로 재설치가 누적되지 않는다.
- **모듈을 빼면 그 파일이 지워진다.** manifest 가 이전 목록을 알고 있으므로 차집합이 그대로 제거 대상이다. 별도의 부분 제거 명령이 필요 없다.

그 밖에 참조 설치기에서 그대로 가져온 것: 쓰기 전 preflight 전량 통과 (fail-before-mutate), 초 단위 충돌을 피하는 카운터 붙은 타임스탬프 백업, `curl | bash` 를 막는 `BASH_SOURCE` 가드, 설치 직후 스모크 테스트, README 의 "무엇을 건드리는가" 감사 절.

## Consequences

- `settings.json` 이 jq 로 재직렬화되므로 **포맷이 바뀐다** (들여쓰기 2칸, 키 순서는 보존). 첫 설치의 diff 에 포맷 변경이 섞인다. README 에 명시한다.
- ~~우리 훅은 컨슈머의 기존 그룹에 합쳐지지 않고 같은 matcher 의 **별도 그룹** 으로 추가된다.~~ → ADR-0008 이후: **설치기는 `hooks` 를 건드리지 않는다.** 컨슈머의 훅 블록은 설치 전후로 바이트 동일하며, `scripts/verify-install.sh` 가 그것을 단정한다 ("the consumer's `.hooks` block is byte-identical after install"). 소유권 경계를 지키기 위한 장치가 필요 없어졌다 — 경계 자체가 없다.
- 컨슈머가 원래 갖고 있던 권한 문자열은 우리가 같은 문자열을 "추가" 하지 않으므로 제거 시에도 남는다.
- manifest 를 지우면 대칭 제거가 불가능해진다. `install.sh --uninstall` 은 manifest 없이는 중단한다.
- 관리 대상 경로에 하네스 소유가 아닌 파일이 있으면 설치가 **아무것도 쓰지 않고 중단** 한다.
- 제거 후에도 `settings.json.bak-*` 스냅샷은 남는다. 의도된 안전망이며 제거기가 경로를 출력한다.
- *(ADR-0008 이후 추가)* 제거가 두 명령이 됐다. `harnessctl uninstall` 은 영수증만 되돌리고 플러그인은 그대로 두므로, 제거기가 `claude plugin uninstall ... --prune` 을 함께 출력한다.

## Alternatives considered

- **`settings.json` 전체를 우리 파일로 교체** (참조 하네스 하나의 방식) — 가장 단순하지만 컨슈머의 설정을 지운다.
- **훅 등록에 별도 마킹 키 추가** (`"_harness": true` 같은) — Claude Code 스키마에 없는 키를 넣게 되고, 사용자가 편집하다 지우면 소유권을 잃는다. 경로 마커는 훅이 동작하려면 반드시 유지되어야 하는 정보라 지워질 수 없다.
- **install.sh 안의 명시적 파일 배열** (참조 설치기의 방식) — 검토 시 목록이 눈에 보이는 장점이 있으나, 파일 추가 시 등록 누락이라는 실패 모드가 생긴다. 트리에서 파생하면 그 실패 모드 자체가 없어진다.
- **모듈별 부분 제거 명령** — `--with` 가 이미 차집합으로 처리하므로 중복이다.

<!-- ===== docs/adr/0006-no-ai-attribution.md ===== -->

# ADR-0006: 커밋·PR 에 AI 귀속을 남기지 않는다

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

Claude Code 는 기본적으로 커밋에 `Co-Authored-By: Claude <noreply@anthropic.com>` trailer 를 붙이고, PR 본문에 `🤖 Generated with [Claude Code]` footer 를 넣는다. 두 동작의 스위치가 다르다 — 전자는 `settings.json` 의 `includeCoAuthoredBy`, 후자는 모델이 본문을 작성하는 시점의 판단이다.

참조 하네스 두 곳의 방침이 정반대였다. 하나는 `includeCoAuthoredBy: true` 로 두고 워크플로 규약에서 trailer 를 *의무화* 했고, 다른 하나는 `false` 로 끄고 PreToolUse 훅으로 명령 단계에서 차단했다. 후자를 쓰는 사용자가 본 저장소의 사용자다.

방침이 갈리는 항목이므로, 기록해 두지 않으면 다음에 참조 하네스를 다시 볼 때 "저쪽은 true 던데" 로 되돌려질 수 있다.

## Decision

**커밋 메시지·PR·이슈 어디에도 AI 를 author 나 co-author 로 남기지 않는다.**

세 겹으로 건다.

1. `plugins/harness-core/declarative/settings-fragment.json` 의 `includeCoAuthoredBy: false` — 내장 부착을 끈다. 컨슈머가 이미 이 키를 갖고 있으면 값을 바꾸지 않고 경고만 낸다 (설치기가 남의 명시적 설정을 뒤집지 않는다).
2. `ai-attribution-guard` 훅 — 커밋·PR·이슈를 작성하는 Bash 명령에서 trailer·footer·로봇 이모지를 차단한다. 명령 단계에서 걸리므로 `--no-verify` 로도 우회되지 않는다.
3. `rules/harness/workflow.md` R2 — 규약으로 명시. 가드가 없는 경로(예: 하네스 저장소 자신)에서는 이것만 남는다.

정당한 참조는 귀속이 아니므로 그대로 둔다: `CLAUDE.md` 라는 파일명, `.claude/` 디렉터리, `anthropic` API 백엔드, 산문 속 모델 이름. 사람 co-author trailer 도 물론 통과한다.

## Consequences

- 참조 하네스 하나와 정반대다. 그 저장소를 다시 참고할 때 이 divergence 를 발견하면 본 ADR 을 근거로 유지한다.
- 본 저장소는 자기 자신에게 설치할 수 없으므로(ADR-0001) 여기서는 훅의 보호를 받지 못한다. `CLAUDE.md` §6 의 규율로만 지킨다.
- `includeCoAuthoredBy` 를 이미 `true` 로 둔 컨슈머는 설치 후에도 `true` 로 남는다. 설치기가 경고를 내지만 자동으로 바꾸지 않는다 — 그 값이 명시적 선택일 수 있기 때문이다.
- 훅이 오탐을 낼 수 있는 지점이 하나 있다: 커밋 메시지 안에서 이 정책 자체를 인용하는 경우("drop the Co-Authored-By: Claude trailer"). 실제로 걸리면 문구를 바꿔 쓰면 된다 — 정책 문구를 커밋 제목에 넣을 이유가 거의 없다.

## Alternatives considered

- **`includeCoAuthoredBy: false` 만** — 내장 trailer 는 막지만 모델이 직접 쓴 footer 는 못 막는다. 실제로 새는 경로는 후자다.
- **commit-msg 단계 스트리퍼** — `--no-verify` 로 우회되고, git hook 설치 상태가 환경마다 비대칭이다. 보조망으로는 유효하나 주 방어선이 될 수 없다.
- **규약만, 가드 없음** — 기본 동작이 반대 방향이라 규약만으로는 반복해서 샌다.

<!-- ===== docs/adr/0007-install-levels.md ===== -->

# ADR-0007: 설치 레벨은 둘이고, 청중으로 나눈다

- **Status**: Accepted
- **Date**: 2026-08-06

## Context

초판은 프로젝트 레벨 설치만 지원했다. 참조 하네스 둘이 모두 프로젝트 레벨이었고, 팀 공유에는 커밋된 파일이 필요하다는 것이 근거였다. 그러나 그 근거는 자산의 *일부* 에만 해당한다.

가드에는 정반대의 논리가 붙는다. `secret-scrubber` 의 존재 이유는 키가 절대 새지 않게 하는 것인데, 프로젝트마다 설치하는 구조에서는 **설치를 잊은 저장소가 정확히 사고가 나는 저장소** 다. 5분 보려고 clone 한 남의 repo, 급하게 만든 스크래치 디렉터리 — 하네스를 설치할 리 없고, 경솔한 명령이 나오기 쉬운 곳도 거기다. 커버리지에 구멍이 있는 가드는 구멍의 크기만큼이 아니라 *그 구멍이 어디에 나는지* 만큼 약하다.

관측된 사실 하나 더: 본 저장소를 만든 사용자의 `~/.claude/settings.json` 에는 훅이 0개, `CLAUDE.md` 없음, permissions 는 `defaultMode` 하나뿐이었다. 사용자 레벨이 비어 있는 것이 기본 상태다.

문서에서 확인한 제약:

- **훅 등록은 레이어 간 병합된다** ("Hook entries merge across settings levels rather than replacing each other"), 동일 핸들러는 1회만 실행. 다만 두 레벨은 서로 다른 command 문자열을 등록하므로 (`$CLAUDE_PROJECT_DIR/...` vs 절대경로) 동일 핸들러로 취급되지 않고 **두 번 실행된다**. *(→ [ADR-0008](0008-plugin-declarative-split.md) 이후 이 조건이 성립하지 않는다. 설치기가 훅을 등록하지 않으므로 두 레벨이 서로 다른 command 문자열을 만들 일 자체가 없다.)*
- **Permissions 도 스코프 간 병합된다.**
- **`${CLAUDE_PROJECT_DIR}` 는 문서화**돼 있으나, 훅 안에서 사용자 설정 디렉터리를 가리키는 변수는 문서에 없다.
- **Path-scoped rules 파일은 프로젝트 레벨에만 문서화**돼 있다. `~/.claude/rules/` 에 대한 언급이 없다.

## Decision

설치 레벨은 둘이고, **편의가 아니라 청중으로** 나눈다.

| | 프로젝트 (기본) | `--user` |
|---|---|---|
| 위치 | `<project>/` + `<project>/.claude/` | `~/.claude/` (또는 `$CLAUDE_CONFIG_DIR`) |
| 청중 | 이 저장소를 clone 하는 **팀** | 이 머신에서 일하는 **나** |
| 커밋됨 | 예 | 아니오 |
| 적용 범위 | 그 프로젝트 | 5분짜리 clone 을 포함한 모든 프로젝트 |

**권장 기본값은 `--user` 다.** 가드·스킬·커맨드·원칙은 머신 전체에 한 번 걸고, 프로젝트 설치는 *팀이 같은 규약을 받아야 할 때* 와 *프로젝트 고유의 rules·설정이 필요할 때* 만 추가한다.

파생되는 세 가지:

1. **`.claude/` 접두사를 벗긴다.** 사용자 설정 디렉터리가 곧 그 `.claude` 다. `map_rel` 이 오버레이 경로를 레벨에 맞게 옮기므로 두 레벨이 한 코드 경로를 공유한다.
2. **`--user` 는 `rules/` 를 설치하지 않는다.** 사용자 레벨에서 읽힌다는 근거가 없으므로, 넣으면 *동작하는 것처럼 보이는 무력한 파일* 이 된다. 설치기가 무엇을 건너뛰었는지 출력하고 프로젝트 설치를 안내한다. 사용자 레벨의 상시 지침은 `~/.claude/CLAUDE.md` 다.
3. **양쪽에 설치돼 있으면 경고한다.** 훅이 두 번 돈다 — 차단 결과는 같지만 정보성 훅의 출력이 겹친다. 자동으로 한쪽을 끄지 않는 이유는 어느 쪽을 끌지가 사용자의 판단이기 때문이다.

소유권 마커도 바뀐다: `.claude/hooks/harness/` → **`/hooks/harness/`**. `CLAUDE_CONFIG_DIR` 이 설정되면 사용자 설정 디렉터리 이름이 `.claude` 가 아니고, 사라질 수 있는 마커는 마커가 아니다.

### 갱신 ([ADR-0008](0008-plugin-declarative-split.md) 이후)

레벨을 **청중으로 나눈다** 는 결정과 위 표는 그대로 유효하다. 구현과 파생 항목 셋이 바뀐다.

- **`--user` 플래그가 `harnessctl init --scope user|project` 가 됐다.** 그리고 스코프 표면이 하나에서 둘로 늘었다 — 플러그인 절반은 플러그인 시스템 자신의 `claude plugin install --scope user|project|local` 이 정하고, 선언적 절반은 `harnessctl` 의 `--scope` 가 정한다. 둘은 독립이며, 짝을 맞추는 것은 사용자 몫이다. `harnessctl --scope local` 은 아직 없다 (backlog).
- **1번 (`map_rel`) 은 없어졌다.** 오버레이를 레벨에 맞게 재사상하는 함수 대신, `harnessctl` 이 스코프에 따라 `TARGET`·`SETTINGS`·`MANIFEST`·`CONFIG_DIR` 을 한 번 정하고 계획을 그 위에서 세운다. `--scope user` 는 `.gitignore` 를 만들지 않고 `.git` 도 요구하지 않는다.
- **2번 (rules 는 프로젝트 전용) 은 그대로 성립하고, 이제 `harnessctl` 을 규율한다.** 문서화된 `~/.claude/rules/` 가 없다는 사실은 변하지 않았고, 플러그인 쪽으로도 길이 열리지 않았다 — `rules` 는 플러그인 컴포넌트가 아니다. 그래서 rule 은 프로젝트 스코프의 `harnessctl` 만 배송할 수 있고, 사용자 스코프에서는 건너뛴 사실을 출력한다. `verify-install.sh` 가 두 성질을 다 단정한다.
- **3번 (양쪽 설치 시 경고) 은 폐기됐다.** 훅을 등록하는 주체가 플러그인 하나뿐이므로, `harnessctl init` 을 몇 개 스코프에서 돌리든 훅은 한 번만 등록된다. 두 스코프를 동시에 초기화하는 것은 이제 상호작용 없는 정상 동작이고, 각 스코프가 자기 manifest 를 갖는다.
- **소유권 마커 `/hooks/harness/` 도 폐기됐다.** 마커의 용도는 `settings.json` 안에서 우리 훅 등록을 골라내는 것이었는데, 골라낼 등록이 없다. 설치기의 소유권 근거는 이제 manifest 하나뿐이다.

## Consequences

- 사용자 레벨 설치는 `.git` 을 요구하지 않고 `.gitignore` 를 만들지 않는다.
- ~~훅 등록에 실제 경로가 박힌다 (`$HOME/.claude/...`, 커스텀 config dir 면 절대경로). 문서화된 대안이 없다.~~ → ADR-0008 이후: 훅 등록이 사라졌으므로 이 문제도 사라졌다. 플러그인은 `${CLAUDE_PLUGIN_ROOT}` 라는 문서화된 앵커를 쓰고, 경로는 어느 스코프에 설치하든 플러그인 캐시를 가리킨다.
- `protected-paths` 훅은 이제 사용자 설정과 프로젝트 설정을 **합집합** 으로 읽는다. 머신 전체 보호가 프로젝트의 자체 목록 때문에 사라지면, 아무도 설정하지 않은 프로젝트에서 가드가 가장 약해진다.
- `--user` 설치는 **팀에 공유되지 않는다.** 팀 규약이 필요하면 프로젝트 설치가 여전히 답이다. ~~그 경우 훅 중복 경고를 보게 된다.~~ → ADR-0008 이후: 경고 없이 두 스코프를 그냥 함께 쓴다.
- 검증 부담이 늘었다. `scripts/verify-install.sh` 가 `CLAUDE_CONFIG_DIR` 로 scratch 디렉터리를 잡아 사용자 레벨 왕복까지 검사한다 — 실제 `~/.claude` 를 건드리지 않으므로 CI 와 개발자 머신에서 그대로 돌릴 수 있다.

## Alternatives considered

- **프로젝트 레벨만** (초판) — 팀 공유는 되지만 가드에 구멍이 남고, 그 구멍이 하필 사고가 나는 곳이다.
- **사용자 레벨만** — 가드는 완전해지지만 팀에 아무것도 전달되지 않고, path-scoped rules 를 쓸 수 없다.
- **양쪽 설치 시 프로젝트 쪽 훅을 자동 생략** — 중복은 없어지지만, 나중에 사용자 레벨을 제거하면 프로젝트가 조용히 무방비가 된다. 경고 후 사용자가 정하게 둔다. *(ADR-0008 이후 문제 자체가 없어져 이 대안도 무의미해졌다.)*
- **`~/.claude/rules/` 에도 설치하고 동작하길 기대** — 근거 없는 파일을 놓는 것이고, 무력한 규칙 파일은 없는 것보다 나쁘다.

<!-- ===== docs/adr/0008-plugin-declarative-split.md ===== -->

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

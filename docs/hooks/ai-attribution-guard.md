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

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

---
name: research-notes
description: "Use to create or maintain the five-document research-note set (STATUS, experiment_plan, FINDINGS, ARTIFACTS, review_log) for a research project — bootstrapping the set in a new project directory, or recording a result into the right file afterward. 한국어 트리거: '연구 노트 세팅', '실험 기록 어디에 남겨', 'STATUS 갱신해줘', '이 결과 기록해줘', 'FINDINGS 정리', '체크포인트 남겨줘'. 재현 가능한 *실행* 셋업(seed·환경·config)은 이 스킬 말고 repro-checklist, PR 생성은 pr-create 로."
---

# research-notes

`.claude/rules/harness/research/notes.md` 의 다섯 문서를 **생성** 하고, 이후 결과가 나올 때마다 **어느 파일이 갱신되는지 라우팅** 한다.

두 경로가 있다 — 처음이면 § A (bootstrap), 이미 있으면 § B (maintenance).

---

## A. Bootstrap — 다섯 문서 생성

### A1. 대상 디렉터리 확정

사용자가 경로를 말하지 않았으면 추론한 뒤 **확인받고 진행**한다. 본 규약은 위치를 강제하지 않으므로 (`docs/`, `notes/`, `projects/<name>/` 무엇이든), 잘못 찍으면 두 번째 note 집합이 생겨 R1 의 단일 진입점이 깨진다.

기존 집합이 이미 있는지 먼저 본다:

```bash
find . -name STATUS.md -not -path '*/.git/*'    # 이미 있으면 그 디렉터리가 대상이다
```

### A2. 무엇이 이미 있는지 점검 — **절대 덮어쓰지 않는다**

```bash
ls -1 <target-dir>/{STATUS,experiment_plan,FINDINGS,ARTIFACTS,review_log}.md 2>/dev/null
```

존재하는 파일은 건드리지 않는다. 내용이 비어 있어도 마찬가지 — 사용자가 쓰다 만 것일 수 있다.

### A3. 없는 것만 템플릿에서 복사

템플릿은 이 스킬 디렉터리의 [`templates/`](templates/) 에 있다.

```bash
cp .claude/skills/research-notes/templates/<NAME>.md <target-dir>/<NAME>.md
```

### A4. 치환

복사한 파일마다 두 플레이스홀더를 채운다.

- `<PROJECT>` → 프로젝트 이름 (디렉터리명 또는 사용자가 준 이름)
- `<YYYY-MM-DD>` → `date +%F` 의 출력

각 템플릿 끝의 `<!-- EXAMPLE ... -->` 블록은 **그대로 둔다.** 형식을 보여주는 것이 목적이고, 실제 항목이 처음 들어갈 때 그때 지운다.

### A5. 보고

생성한 파일과 **이미 있어서 건드리지 않은** 파일을 구분해 보고한다. 후자를 빠뜨리면 사용자가 덮어써졌다고 오해한다.

---

## B. Maintenance — 결과가 나왔을 때 어디에 쓰는가

사용자가 결과·판단·리뷰를 보고하면 아래 라우팅을 적용한다. **여러 행이 동시에 해당될 수 있다.**

| 사용자가 보고한 것 | 갱신할 파일 |
|---|---|
| 실험·실행을 돌렸다 (결과가 무엇이든) | `experiment_plan.md` 새 항목 — **항상**. + `STATUS.md` |
| 어딘가에 인용될 수 있는 수치가 나왔다 | + `ARTIFACTS.md` 행 |
| **믿는 바가 바뀌었다** (확립되거나 뒤집혔다) | + `FINDINGS.md` |
| 리뷰·체크포인트를 돌았다 | `review_log.md` 새 dated entry |

규칙 셋:

1. **원장 항목은 항상 쓴다.** 실패한 실행·아무것도 안 나온 실행도 기록 대상이다 — 같은 걸 다시 돌리는 걸 막는 게 원장의 절반이다. 새 항목은 반드시 파일 **끝** 에.
2. **`FINDINGS.md` 는 믿음이 바뀔 때만.** 실행할 때마다 갱신하는 문서가 아니다. 기존 결론이 뒤집히면 표에서 내리되 번복 절에 남긴다 — `notes.md` R3.
3. **`STATUS.md` 는 다시 쓴다.** 제목의 날짜도 함께 고친다. 이전 내용을 아래로 밀어 쌓지 않는다.

### 원장 항목을 쓸 때

`Setup` 은 재실행 가능한 수준까지 — 명령 원문·설정·코드 리비전·입력 식별자. 무엇을 남겨야 하는지는 [`repro-checklist` 스킬](../repro-checklist/SKILL.md) 이 정의한다. `Result` 에는 사실만 쓰고 해석은 `FINDINGS.md` 로 보낸다.

### `ARTIFACTS.md` 행을 쓸 때

출력 위치가 세션 scratchpad·임시 디렉터리면 **행을 쓰기 전에 영속 경로로 옮긴다.** 그 경로가 사라지는 순간 주장만 남고 근거가 없어진다.

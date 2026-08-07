---
name: results-deck
description: "Use when development or research results in this repository need to become a presentation — turns the repo's own artifacts (FINDINGS, ARTIFACTS, experiment_plan, a changeset, a release) into a deck outline in which every number is traceable to the run that produced it, then hands rendering to slides-grab. Use it for the development side too — a release readout, a stakeholder or sprint review, a demo — any time a changelog, PR list, or benchmark output has to become something people sit through. Reach for it even when the user never says 'slides' or 'deck': a readout, a write-up, or 자료 built from work already in the repo is this skill. 한국어 트리거: '결과 발표자료 만들어줘', '실험 결과 슬라이드로', '이번 작업 발표용으로 정리', '데모/리뷰 자료 만들어줘', '연구 결과 정리해서 보여줘', '릴리스 정리해서 보고 자료로', '스테이크홀더 리뷰용으로 정리해줘'. 슬라이드의 *렌더링·디자인·편집·PDF 변환* 은 이 스킬 말고 slides-grab 의 스킬들로 (slides-grab-plan/html/design/export), 노트 자체를 만들고 유지하는 것은 research-notes 로."
---

# results-deck

산출물을 **서사** 로 바꾼다. 렌더링은 하지 않는다 — 그건 `slides-grab` 이 훨씬 잘 하고, 이 스킬의 출력은 그쪽 입력이다.

이 스킬이 존재하는 이유는 하나다. **결과 발표는 추적 불가능한 수치가 인용되는 자리다.** 노트에는 "이 표가 어느 run 에서 나왔는지" 가 적혀 있어도, 슬라이드로 옮겨지는 순간 숫자만 남고 근거는 떨어져 나간다. 그리고 그 숫자는 발표를 들은 사람이 인용하고 의사결정에 쓴다.

## Step 0 — 무엇을 발표하는가

둘 중 하나다. 섞지 않는다.

- **연구 결과** — 출처는 `FINDINGS.md`(무엇을 믿게 됐나), `experiment_plan.md`(어떻게 알아냈나), `ARTIFACTS.md`(어디서 나왔나). 노트 세트가 없으면 `research-notes` 를 먼저 돌린다.
- **개발 결과** — 출처는 변경 이력, PR 본문, 릴리스 노트, 벤치마크 출력.

## Step 1 — 근거부터 모은다

**슬라이드를 쓰기 전에 수치를 모은다.** 순서가 반대면 서사에 맞는 숫자를 찾게 되고, 그건 결론을 정해놓고 근거를 고르는 것이다.

`ARTIFACTS.md` 가 있으면 그것이 인용 가능한 수치의 목록이다. 없으면 이 발표에서 쓸 수치를 먼저 표로 만든다 — claim · 만든 명령 · 출력 위치 · 날짜. 이 표에 없는 숫자는 슬라이드에 올리지 않는다.

## Step 2 — 서사

한 장에 한 주장. 결과 발표의 기본 골격:

```
1  무엇이 문제였나        (왜 이 작업을 했나 — 청중이 아는 언어로)
2  무엇을 했나            (접근, 한 장)
3  무엇을 알아냈나        (핵심 결과 — 수치가 여기 모인다)
4  얼마나 믿을 수 있나    (표본, 변동, 통제, 재현 방법)
5  무엇이 아직 아닌가     (한계와 뒤집힌 결과)
6  다음                   (구체적 행동 하나)
```

4번과 5번을 빼지 않는다. **뒤집힌 결과가 없는 발표는 뒤집힌 것을 지운 발표로 읽힌다** — `FINDINGS.md` 가 번복을 보존하는 것과 같은 이유다. 음성 결과도 결과다.

## Step 3 — 추적 검사

초안이 나오면 기계로 검사한다. 사람이 눈으로 대조하는 것과 다르다.

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/check-claims.sh" <deck.md> [ARTIFACTS.md]
```

덱의 모든 숫자가 근거 파일에 있는지 본다. 걸린 숫자는 둘 중 하나다 — 아무도 재현할 수 없는 수치이거나, 근거 표에 행이 빠진 것이다. **먼저 어느 쪽인지 판단한다**: 행이 빠진 것이면 근거 표에 행을 더하고, 재현할 수 없는 수치면 슬라이드에서 뺀다.

연도·날짜·버전·목록 번호·슬라이드 참조·`ADR-0008` 꼴 식별자·링크 주소·인라인 코드·HTML 주석은 검사기가 알아서 뺀다. 그래도 남는 예외 — `bash 5` 처럼 단어 뒤의 맨 숫자 — 만 그 줄에 `<!-- no-claim -->` 를 단다. **`<!-- no-claim -->` 를 근거 없는 수치를 통과시키는 데 쓰지 않는다.** 그 순간 검사는 장식이 된다.

**검사를 통과하지 못한 초안을 렌더링으로 넘기지 않는다.**

## Step 4 — 렌더링으로 넘긴다

`slides-grab` 이 설치돼 있으면 그쪽 스킬에 개요를 넘긴다 (`slides-grab-plan` → `slides-grab-html` → `slides-grab-export`). 없으면 `harnessctl doctor` 가 설치 명령을 알려준다. 이 스킬은 여기서 끝난다 — 디자인·레이아웃·PDF 는 다시 만들지 않는다.

## 하지 않는 것

- 슬라이드를 직접 렌더링하거나 디자인하기.
- 근거 표에 없는 수치를 "대략" 으로 올리기.
- 한계 절 생략하기. 분량이 부족하면 다른 장을 줄인다.

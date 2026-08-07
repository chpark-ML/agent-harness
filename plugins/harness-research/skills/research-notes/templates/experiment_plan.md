# <PROJECT> — experiment plan (ledger)

> **시간순 원장.** 새 항목은 **끝에 추가**하고, 이전 항목은 고치지 않는다. 틀린 것으로 밝혀졌으면
> 새 항목에서 그렇게 적는다 — 원장의 가치는 *그때 무엇을 알고 있었는가* 를 보존하는 데 있다.
>
> 현재 상태는 [`STATUS.md`](STATUS.md), 지금 무엇을 믿는가의 단면은 [`FINDINGS.md`](FINDINGS.md).
> `Result` 에는 사실만 적고 해석은 `FINDINGS.md` 로 보낸다.

---

## 1. <제목> (<YYYY-MM-DD>)

**Intent.** <무엇을 확인하려 했는가. 무엇이 나오면 확증이고 무엇이 나오면 반증인가.>

**Setup.** <명령 원문·설정·코드 리비전·입력. 이 항목만 보고 재실행 가능해야 한다.>

**Result.** <나온 것. 수치는 출처와 함께 — `ARTIFACTS.md` 에 행이 있는가.>

<!-- EXAMPLE — 삭제할 것. 채워진 모습:

## 0. Baseline 재현 (2026-01-15)

**Intent.** 공개된 기준선 수치를 우리 환경에서 재현. |Δ| ≤ 2 면 환경 정합으로 간주하고
이후 비교의 출발점으로 쓴다. 넘으면 환경 차이부터 규명 (비교 자체가 성립 안 함).

**Setup.** `scripts/run_baseline.sh --seed 0 --config configs/base.yaml`, 코드 `a1b2c3d` (clean),
seed 0/1/2 3 회. 입력 `data/v3/` (sha256 `4f9a…`). 출력 `runs/2026-01-15-baseline/`.

**Result.** 70.9 (3 seed 평균, 범위 70.4–71.3) vs 보고치 71.2. |Δ| = 0.3, 임계 안.
seed 간 범위가 0.9 로 예상보다 커서 이후 단일 seed 비교는 하지 않기로.
-->

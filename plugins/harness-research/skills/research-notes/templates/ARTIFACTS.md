# <PROJECT> — artifacts

> **주장 → 산출물 추적 지도.** 한 행이 하나의 주장이다.
> **이 표를 통해 추적되지 않는 수치는 아직 결과가 아니다** — 문서·발표·PR 에 수치를 쓰기 전에 행이 먼저 있어야 한다.
> 마지막 갱신 <YYYY-MM-DD>.

**출력 위치 규칙.** 세션 scratchpad·임시 디렉터리는 위치가 아니다. 세션이 끝나면 주장만 남고 근거가 사라진다.
로그는 산출물과 같은 단위로 취급한다 — 메트릭만 옮기고 로그를 두고 오면 수치는 남고 provenance 가 사라진다.

| 주장 | 만든 run / command | 출력 위치 | 날짜 |
|---|---|---|---|
| | | | |

<!-- EXAMPLE — 삭제할 것. 채워진 모습:

| 주장 | 만든 run / command | 출력 위치 | 날짜 |
|---|---|---|---|
| "기준선 재현 70.9 (범위 70.4–71.3)" | `scripts/run_baseline.sh --seed {0,1,2} --config configs/base.yaml` @ `a1b2c3d` | `/srv/runs/2026-01-15-baseline/{metrics.json,run.log}` | 2026-01-15 |
| "B 의 wall time 2.1×" | `scripts/bench.py --profile --repeat 5` @ `d4e5f6a` | `/srv/runs/2026-01-20-bench-b/` | 2026-01-20 |
-->

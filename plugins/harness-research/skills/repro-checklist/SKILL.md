---
name: repro-checklist
description: "Use before starting a run whose result might be quoted, when validating an experimental setup, or when re-running an earlier result and the numbers do not match. Three pillars — seed, environment, config — plus what to record with each run so it can be re-run later. Applies to any experiment-shaped work: a benchmark, a load test, an A/B analysis, a training run. 한국어 트리거: '재현성 점검', '이 실험 다시 돌릴 수 있나', '시드 고정', '실험 환경 기록', '재현이 안 돼', '설정 어디에 저장'. 노트 구조·결과를 어느 문서에 남기는가는 이 스킬 말고 research-notes 로."
---

# repro-checklist

Reproducibility cannot be added *after* a run. What was missed is usually only discovered by running again, and by then there is no way to confirm what the original result even was. So this check happens **before** the run.

Three pillars — **seed · environment · config**. With any one of them empty, "I ran the same thing and got something different" cannot be diagnosed.

**Which runs this applies to.** The discipline below targets *runs whose results might be quoted* — anything that becomes a number in a document, a talk or a PR, or a baseline for later comparison. It does not apply to repeated runs during exploration. That distinction matters because of items like §2's "fail fast on a dirty tree": correct for a run that will be quoted, and an obstruction during exploration where dirty is the normal state — and a discipline that obstructs is a discipline that gets ignored. **The moment exploration is promoted to a citation** — when you decide to write this number down somewhere — is when this checklist applies.

## 1. Seed — enumerate *every* source of randomness and pin it

Setting one global seed is not the end of it. Listed in order of how easily each is missed.

- **Data order, shuffling, sampling** — splits, shuffles, bootstrap, subsampling. Each often has its own RNG.
- **Parallel workers** — without deriving a seed per worker, the random numbers consumed vary with scheduling. Give them all the same seed and every worker draws the identical sequence. Both are wrong; the answer is a deterministic derivation such as `base_seed + worker_index`.
- **Aggregation order** — parallel reduces, iteration over unordered collections and floating-point summation move results independently of any seed. If a pinned seed still drifts slightly, start here.
- **Hash seeding** — when the runtime randomises hashing per process, set and dict iteration order changes every run. If that order leaks into a result anywhere, no amount of seed pinning reproduces it.
- **Defaults derived from time, PID or hostname** — plenty of libraries initialise from these when no seed is given. "It is the default, so it is fine" is a synonym for irreproducible.
- **ID generation** — UUIDs and random suffixes are a source of randomness too, once they reach output paths or sort keys.

**Turn on determinism options where they exist, and record what they cost.** Many runtimes offer a deterministic mode that gives up speed. Whether it was on changes how the result is read, so it belongs in the run record.

## 2. Environment — everything wrapped around the run

- **Exact dependency versions** — the lockfile is the source of truth. Without one, save a freeze taken at run time into the run directory. "The range in requirements" is not a version.
- **Code revision** — commit hash **and whether the tree was dirty**. A result from a dirty tree is not reproducible. Failing fast is cheaper than warning.
- **Runtime versions** — interpreter, compiler, container image tag (digest where possible).
- **Hardware and parallelism** — CPU model, core count, accelerator model, driver version, thread count. Only the hardware facts that change results need keeping, but *when you do not know which ones do*, keeping them is cheaper.
- **Locale and timezone** — they change sort order and date parsing. They differ silently, and this is the item people notice last.
- **Input data identifiers and hashes** — a path is not enough. If the content at that path is updated, the same command produces a different result.

## 3. Config — save the resolved configuration next to the output

**A config file plus "I remember the overrides" is not a config.** What must be saved is the *resolved* configuration: files, environment variables, CLI arguments and defaults, merged.

- **Include the defaults.** Anything unspecified follows a library default, and defaults change between versions. When they do, there is no way left to work out why the old result will not come back.
- **Save the command verbatim** (`argv` as it was) alongside it. It looks redundant next to the resolved config, but only the command records what a human intended.
- **Environment variables: only the keys used.** A full env dump is a route for leaking secrets.
- **Put it in the same directory as the output.** Anywhere else and within days nobody can tell which config produced which output.

## 4. What to keep with each run

A run directory holding all of the below can be re-run. Whatever is missing is what cannot be.

- resolved config and the verbatim command
- environment capture (the items in §2, in a machine-readable form)
- input identifiers and hashes
- the seeds used, including the derivation rule
- **logs** — an artefact of the same rank as metrics. Keeping the metrics file and discarding the logs leaves the number and loses the path it came from
- hashes of the outputs
- **the definition of "the same"** — bit equality in deterministic mode, otherwise a per-metric tolerance. Decide it *before* the run. Decided afterwards, it gets fitted to the difference you observed.

Where records live and which note document they attach to is the [`research-notes` skill](../research-notes/SKILL.md) — a number that will be quoted needs a row in its `ARTIFACTS.md`.

## 5. When attempting a reproduction

1. Return the code to the recorded revision. (If it was dirty, this already failed — record that and stop.)
2. Restore dependencies from the lockfile or freeze output.
3. Compare input hashes. On a mismatch, nothing after this point is meaningful.
4. Run with the same seeds and the same parallelism. **Different parallelism can differ even with identical seeds.**
5. Judge against the tolerance decided in advance.
6. On a mismatch, **keep both results.** Do not overwrite one with the other — the difference is itself data.

## 6. Declaring something irreproducible

If any of the following holds, the number is irreproducible and has to be regenerated before it is quoted.

- It came from a dirty working tree.
- Dependencies were installed as "latest" with no lockfile.
- The command was edited by hand and exists nowhere.
- The input sits at a path that is updated in place, with no hash.
- The seed was pinned but parallelism and worker count were not recorded.
- The output exists and the config that produced it is elsewhere, or gone.
- The artefacts exist only in a session temp directory.
- Nothing defines what counts as "the same" — with no criterion, neither success nor failure can be declared.

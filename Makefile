# agent-harness — development targets. Consumers never see this file.
#
# BASH selects the interpreter every check runs under. It is a variable
# because the bash 3.2 floor is a real constraint: `make verify BASH=/bin/bash`
# on macOS is the check that keeps a bash-4-ism from shipping.

BASH ?= bash

# The base a pre-PR version-bump check measures against. The CI job overrides
# it with the pull request's own base SHA.
BASE ?= main

TRIGGER_RUNS ?= 3
CONV_TRIALS  ?= 6

# Always-on context the harness costs a consumer, worst case (project scope,
# every profile). Measured at 8558 in CI (an earlier tree read 8389 in CI and 8808 on macOS — the estimator varies); the gap is deliberate headroom, not spare
# room to fill. Raising this number is a decision to make explicitly and say why
# — see scripts/context-budget.sh.
CONTEXT_CEILING ?= 9000

.PHONY: help verify verify-all syntax frontmatter doc-refs doc-commands version-bump version-bump-range context-budget context-budget-strict verify-context-budget verify-inventory verify-hooks verify-install verify-plugins bench bench-lsp bench-claims bench-trigger bench-convention bench-tier verify-benches

help:
	@echo "make verify           syntax + frontmatter + doc-refs + hooks + harnessctl + plugins"
	@echo "make syntax           parse every shipped script"
	@echo "make frontmatter      YAML frontmatter of every skill, agent, rule, command"
	@echo "make doc-refs         links, anchors and paths that documents point at"
	@echo "make doc-commands     the harness commands documents tell you to run exist"
	@echo "make context-budget   always-on token cost against the ceiling (partial without the CLI)"
	@echo "make context-budget-strict  the same, but a partial measurement fails"
	@echo "make verify-context-budget  the budget gate's own failure paths"
	@echo "make verify-inventory  hook, permission and assertion counts against the artifacts"
	@echo "make version-bump     the version-bump gate's own failure paths"
	@echo "make version-bump-range  a plugin change in BASE..HEAD moved that plugin's version"
	@echo "make verify-all       verify, then confirm the published check total matches"
	@echo "make verify-hooks     hook behaviour only"
	@echo "make verify-install   harnessctl round-trip only"
	@echo "make verify-plugins   claude plugin validate (skipped when the CLI is absent)"
	@echo "make bench            measure the guard layer against a held-out corpus"
	@echo "make bench-lsp        does the Python LSP reduce tokens? (costs money)"
	@echo "make bench-trigger    do the skill descriptions actually fire? (costs money)"
	@echo "make bench-convention do the written rules change behaviour? (costs money)"
	@echo "make bench-claims     the claim checker against held-out prose"
	@echo "make bench-tier       is a cheaper model tier actually cheaper? (costs money)"
	@echo "make verify-benches   the benchmarks still run, without spending anything"
	@echo ""
	@echo "make verify BASH=/bin/bash    run everything under macOS bash 3.2"

verify: syntax frontmatter doc-refs doc-commands version-bump context-budget verify-context-budget verify-inventory verify-hooks verify-install verify-plugins verify-benches

# Parsing every script catches bash-4 syntax on a branch no test happens to
# reach — which is most of harnessctl's error paths.
syntax:
	@fail=0; \
	for f in install.sh scripts/*.sh evals/*.sh plugins/*/bin/* \
	         plugins/*/scripts/*.sh plugins/*/hooks/*.sh; do \
	  if $(BASH) -n "$$f"; then echo "  ok    $$f"; else echo "  FAIL  $$f"; fail=1; fi; \
	done; \
	exit $$fail

# Which second languages a skill description must carry is a property of the
# deployment, not of the harness — a contributor writing for a Japanese team
# should not need a Korean marker to pass CI. This repository serves Korean
# prompts today, so it declares that and the check applies to its own skills.
# Whether those triggers earn what they cost is being measured; see §4b.
# The declaration lives in `.claude/trigger-langs`, not here. It used to be a
# variable on this line, and Windows `make.exe` re-encodes recipe text through
# the ANSI codepage on the way into the child environment — `한국어` arrived as
# mojibake and five skills that carry the marker were failed for missing it. The
# script reads the file itself, so nothing re-encodes it. HARNESS_TRIGGER_LANGS
# still overrides for a single run when set from a shell.

# A skill whose frontmatter fails to parse loads with empty metadata and
# silently stops being routable. Needs nothing but python3, so it runs in
# every environment.
#
# The value is quoted: unquoted, a two-word list word-splits and the second
# word runs as a command, which fails the whole verify chain with a `command
# not found` that names a language.
# Selftest first, as doc-refs does: this checker once passed 11 / 11 and then
# exited 1 while printing the result, because stdout could not encode an
# em-dash. A verifier that dies on its own output reports nothing.
frontmatter:
	@$(BASH) scripts/verify-frontmatter.sh --selftest
	@$(BASH) scripts/verify-frontmatter.sh

# A dead link or a mistyped path in an instruction file is not an error — the
# step just never runs, and nothing says so. Selftest first: this checker's own
# risk is false positives, and a doc linter that cries wolf gets switched off.
doc-refs:
	@$(BASH) scripts/verify-doc-refs.sh --selftest
	@$(BASH) scripts/verify-doc-refs.sh

# A referenced file existing is not the same as a referenced command working.
# The narrow half: every subcommand and long flag a fenced block tells you to
# run, checked against the parser that accepts it.
doc-commands:
	@$(BASH) scripts/verify-doc-commands.sh --selftest
	@$(BASH) scripts/verify-doc-commands.sh

# The plugin cache is keyed on the version string, so a component change that
# ships without a bump reaches nobody — CLAUDE.md §2 states that and then leaves
# it to discipline, which this repository cannot delegate to its own hooks
# because it cannot install onto itself.
#
# `verify` runs the SELFTEST only, deliberately. The live check reads a commit
# range, so wiring it into `verify` would make a green run depend on which
# branch you are standing on — and the ledger already carries one afternoon lost
# to measuring a reproduction on the wrong branch. The range check has its own
# target below and a pull_request-gated CI job; `make verify` stays a property
# of the tree.
version-bump:
	@$(BASH) scripts/verify-version-bump.sh --selftest

# The live check. `make version-bump-range BASE=<ref>` before opening a PR, or
# let the CI job do it.
version-bump-range:
	@$(BASH) scripts/verify-version-bump.sh $(BASE) HEAD

# Every skill and rule is a per-session tax on the consumer, forever. The old
# cost table counted skills only and was wrong by 3.6x, which is how "62 more
# harnesses" once sounded survivable. A number nobody sums is a number nobody
# owns.
context-budget:
	@$(BASH) scripts/context-budget.sh --ceiling $(CONTEXT_CEILING)

# The gate. Needs the Claude CLI *and* the plugins installed, so it runs in the
# one CI job that has both. Without --require-plugins the ceiling passes on the
# declarative half alone, which is how the published worst case drifted to three
# different values across four documents without anything noticing.
context-budget-strict:
	@$(BASH) scripts/context-budget.sh --ceiling $(CONTEXT_CEILING) --require-plugins

# CI only ever runs the strict path where it succeeds. These cases cover the
# exits that make it a gate — partial, stale, and the deliberately non-fatal
# published-number mismatch — none of which any CI job reaches.
verify-context-budget:
	@$(BASH) scripts/verify-context-budget.sh

# The inventory figures — hooks, permission tiers, installer assertions — have
# to be the ones the artifacts actually carry. verify-check-total already does
# this for the published check count; everything else was swept by hand, and a
# hand sweep is wrong exactly where the hand missed.
verify-inventory:
	@$(BASH) scripts/verify-inventory.sh --selftest
	@$(BASH) scripts/verify-inventory.sh

# The published total is a claim about this suite, and for four releases it was
# maintained by editing three documents by hand. It cannot live inside `verify`
# — it has to read what verify printed — so it wraps it. CI runs this one.
# No pipe, and that is deliberate: `set -o pipefail` is not POSIX, and GNU make
# runs recipes under /bin/sh, which is dash on Ubuntu. The first version used a
# pipe and died in CI in three seconds while passing on macOS, where /bin/sh is
# bash. Capture, print, then check.
verify-all:
	@log=$$(mktemp); st=$$(mktemp); \
	  trap 'rm -f "$$log" "$$st"' EXIT INT TERM; \
	  { $(MAKE) verify BASH=$(BASH) 2>&1; echo $$? > $$st; } | tee $$log; \
	  $(BASH) scripts/verify-check-total.sh $$log; tot=$$?; \
	  [ "$$(cat $$st)" -eq 0 ] && [ $$tot -eq 0 ]

verify-benches:
	@$(BASH) scripts/verify-benches.sh

verify-hooks:
	@$(BASH) plugins/harness-core/scripts/verify-hooks.sh
	@for v in plugins/*/scripts/verify-*.sh; do \
	  case "$$v" in *harness-core*) continue ;; esac; \
	  echo; echo "================================================================"; \
	  echo "  $$(basename $$v)"; echo "================================================================"; \
	  $(BASH) "$$v" || exit 1; \
	done

verify-install:
	@$(BASH) scripts/verify-install.sh

# The only check that needs the Claude CLI. It is additive — everything above
# runs without it — so a machine or CI image without the CLI still gets full
# behavioural coverage.
verify-plugins:
	@if command -v claude >/dev/null 2>&1; then \
	  claude plugin validate . --strict || exit 1; \
	  for p in plugins/*/; do claude plugin validate "$$p" --strict || exit 1; done; \
	else \
	  echo "  skip  claude CLI not on PATH — plugin manifests unvalidated"; \
	fi

# A measurement, not a test. The corpus is held out from the verifiers, so a
# score below 100% is expected and the misses are the report. Deliberately not
# part of `verify`: a benchmark that gates CI becomes a test, and then it gets
# written to pass instead of written to inform.
bench:
	@$(BASH) scripts/bench-guards.sh

# Spends real money on agent runs. Never wired into verify.
bench-trigger:
	@for f in evals/trigger/*.json; do \
	  python3 scripts/bench-trigger.py $$f --runs $(TRIGGER_RUNS) || exit 1; \
	done

bench-convention:
	@$(BASH) scripts/bench-convention.sh harness $(CONV_TRIALS)
	@$(BASH) scripts/bench-convention.sh raw $(CONV_TRIALS)

bench-claims:
	@$(BASH) scripts/bench-claims.sh

bench-lsp:
	@$(BASH) scripts/bench-lsp.sh

# Costs real model sessions, like the other paid benches. It had no target at
# all — 131 lines reachable only by typing the script path, invisible to help,
# which is how an instrument rots unnoticed.
bench-tier:
	@$(BASH) scripts/bench-tier.sh

# agent-harness — development targets. Consumers never see this file.
#
# BASH selects the interpreter every check runs under. It is a variable
# because the bash 3.2 floor is a real constraint: `make verify BASH=/bin/bash`
# on macOS is the check that keeps a bash-4-ism from shipping.

BASH ?= bash

TRIGGER_RUNS ?= 3
CONV_TRIALS  ?= 6

.PHONY: help verify syntax frontmatter doc-refs verify-hooks verify-install verify-plugins bench bench-lsp bench-claims bench-trigger bench-convention verify-benches

help:
	@echo "make verify           syntax + frontmatter + doc-refs + hooks + harnessctl + plugins"
	@echo "make syntax           parse every shipped script"
	@echo "make frontmatter      YAML frontmatter of every skill, agent, rule, command"
	@echo "make doc-refs         links, anchors and paths that documents point at"
	@echo "make verify-hooks     hook behaviour only"
	@echo "make verify-install   harnessctl round-trip only"
	@echo "make verify-plugins   claude plugin validate (skipped when the CLI is absent)"
	@echo "make bench            measure the guard layer against a held-out corpus"
	@echo "make bench-lsp        does the Python LSP reduce tokens? (costs money)"
	@echo "make bench-trigger    do the skill descriptions actually fire? (costs money)"
	@echo "make bench-convention do the written rules change behaviour? (costs money)"
	@echo "make bench-claims     the claim checker against held-out prose"
	@echo ""
	@echo "make verify BASH=/bin/bash    run everything under macOS bash 3.2"

verify: syntax frontmatter doc-refs verify-hooks verify-install verify-plugins verify-benches

# Parsing every script catches bash-4 syntax on a branch no test happens to
# reach — which is most of harnessctl's error paths.
syntax:
	@fail=0; \
	for f in install.sh scripts/*.sh plugins/harness-core/bin/harnessctl \
	         plugins/*/scripts/*.sh plugins/harness-core/hooks/*.sh; do \
	  if $(BASH) -n "$$f"; then echo "  ok    $$f"; else echo "  FAIL  $$f"; fail=1; fi; \
	done; \
	exit $$fail

# A skill whose frontmatter fails to parse loads with empty metadata and
# silently stops being routable. Needs nothing but python3, so it runs in
# every environment.
frontmatter:
	@$(BASH) scripts/verify-frontmatter.sh

# A dead link or a mistyped path in an instruction file is not an error — the
# step just never runs, and nothing says so. Selftest first: this checker's own
# risk is false positives, and a doc linter that cries wolf gets switched off.
doc-refs:
	@$(BASH) scripts/verify-doc-refs.sh --selftest
	@$(BASH) scripts/verify-doc-refs.sh

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

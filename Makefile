# BASH, NAMED EXPLICITLY. `make` runs recipes under `/bin/sh`, which is bash on macOS and dash on
# the Ubuntu runner — and dash has no `pipefail`, so this suite passed locally and died on CI with
# `set: Illegal option -o pipefail` before running a single test. The failure was loud, which is the
# only reason it cost minutes rather than a day; the same shape with a quiet failure is the one this
# framework exists to catch.
SHELL := /bin/bash

# THE SUITE FOR THIS REPOSITORY IS EVERY SCRIPT'S OWN SELF-TEST, PLUS THE TWO CHECKS THAT READ THE
# DOCUMENTS. There is nothing to compile here; the framework's correctness is entirely in whether
# each gate can still be shown to fail, which is what --self-test asserts.
#
# A SCRIPT WITH NO --self-test IS A FAILURE, NOT A SKIP. That is the same rule the README states for
# consumers ("a gate that cannot be shown to fail is not a gate"), and it has to bite here first.
.PHONY: ci
ci:
	@set -euo pipefail; \
	rc=0; \
	for s in framework/.workflow/bin/*.sh; do \
	  if ! grep -q -- '--self-test' "$$s"; then \
	    echo "FAIL: $$(basename $$s) ships no --self-test — it cannot be shown to fail"; rc=1; continue; \
	  fi; \
	  printf '%-26s ' "$$(basename $$s)"; \
	  if bash "$$s" --self-test >/tmp/adf-ci.out 2>&1; then echo OK; else echo FAIL; sed 's/^/    /' /tmp/adf-ci.out | head -6; rc=1; fi; \
	done; \
	printf '%-26s ' "check-prompts(framework)"; \
	if bash framework/.workflow/bin/check-prompts.sh framework/.claude/commands >/dev/null 2>&1; then echo OK; else echo FAIL; rc=1; fi; \
	printf '%-26s ' "check-readme(framework)"; \
	if bash framework/.workflow/bin/check-readme.sh README.md framework >/dev/null 2>&1; then echo OK; else echo FAIL; rc=1; fi; \
	printf '%-26s ' "check-dogfood"; \
	if bash framework/.workflow/bin/check-dogfood.sh >/dev/null 2>&1; then echo OK; else echo FAIL; bash framework/.workflow/bin/check-dogfood.sh 2>&1 | sed 's/^/    /' | head -6; rc=1; fi; \
	exit $$rc

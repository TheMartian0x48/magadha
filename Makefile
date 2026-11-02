.DEFAULT_GOAL := help

ODINFMT := $(or $(shell command -v odinfmt),$(HOME)/.local/share/nvim/mason/bin/odinfmt)
SOURCES := $(filter-out test/%,$(wildcard *.odin)) $(wildcard test/*.odin)

.PHONY: help fmt fmt-check test clean

help: ## Show this help
	@grep -E '^[a-z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

fmt: ## Format every Odin file in place with odinfmt (the formatter ols uses in nvim)
	@for file in $(SOURCES); do $(ODINFMT) $$file -w || exit 1; done

fmt-check: ## Fail if any Odin file is not formatted, without changing files
	@status=0; for file in $(SOURCES); do \
		$(ODINFMT) $$file | diff -q $$file - > /dev/null || { echo "not formatted: $$file"; status=1; }; \
	done; exit $$status

test: ## Run the tests in test/
	odin test test

clean: ## Remove built binaries
	rm -rf test/test.bin

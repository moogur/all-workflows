# Makefile для локальной разработки all-workflows.
# Цели повторяют проверки CI (.github/workflows/ci.yml), чтобы прогонять их
# локально теми же командами. Инструменты: actionlint, shellcheck, yamllint, bats, jq.

SHELL := /bin/bash

# Имена инструментов можно переопределить: `make test BATS=/path/to/bats`.
ACTIONLINT ?= actionlint
SHELLCHECK ?= shellcheck
YAMLLINT   ?= yamllint
BATS       ?= bats

# Bash-скрипты, которые проверяются строго (без исключений).
SH_FILES := .github/actions/*/*.sh scripts/*.sh .husky/commit-msg tests/helpers.bash

# Игноры actionlint:
#  - 'is potentially untrusted' — github.head_ref в kanboard.yml (см. docs/security.md);
#  - 'job_workflow_sha' — валидное поле, отсутствует в схеме actionlint (см. docs/testing.md).
ACTIONLINT_IGNORES := -ignore 'is potentially untrusted' -ignore 'job_workflow_sha'
# Для inline-скриптов workflow'ов shellcheck внутри actionlint — только ошибки
# (в docker-командах есть намеренный word-splitting).
export SHELLCHECK_OPTS := --severity=error

.DEFAULT_GOAL := help
.PHONY: help check lint test actionlint shellcheck yamllint

help: ## Показать список команд
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

check: lint test ## Всё, что гоняет CI (статика + тесты)

lint: actionlint shellcheck yamllint ## Все статические проверки

actionlint: ## Статанализ workflow'ов (actionlint + shellcheck inline-скриптов)
	$(ACTIONLINT) $(ACTIONLINT_IGNORES)

shellcheck: ## Проверка bash-скриптов (экшены, kanboard, хук, хелперы)
	$(SHELLCHECK) $(SH_FILES)

yamllint: ## Проверка YAML (.github)
	$(YAMLLINT) -c .yamllint.yml .github

test: ## Юнит-тесты (bats)
	$(BATS) tests/

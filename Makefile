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
SH_FILES := lib/*.sh .github/actions/*/*.sh scripts/*.sh .husky/commit-msg tests/*.bash

# Игнор actionlint: 'job_workflow_sha' — валидное поле, отсутствует в схеме
# actionlint (см. docs/testing.md).
ACTIONLINT_IGNORES := -ignore 'job_workflow_sha'
# Для inline-скриптов workflow'ов shellcheck внутри actionlint — только ошибки
# (в docker-командах есть намеренный word-splitting). Только для цели actionlint:
# отдельные скрипты (цель shellcheck) проверяются строго, как в CI.
ACTIONLINT_SHELLCHECK_OPTS := --severity=error

.DEFAULT_GOAL := help
.PHONY: help check lint test actionlint shellcheck yamllint

help: ## Показать список команд
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

check: lint test ## Всё, что гоняет CI (статика + тесты)

lint: actionlint shellcheck yamllint ## Все статические проверки

actionlint: ## Статанализ workflow'ов (actionlint + shellcheck inline-скриптов)
	SHELLCHECK_OPTS='$(ACTIONLINT_SHELLCHECK_OPTS)' $(ACTIONLINT) $(ACTIONLINT_IGNORES)

# -x: скрипты подключают lib/*.sh динамическим путём, без него shellcheck не следует
# за source и сообщает SC1091 (путь подсказывают строки `# shellcheck source=` в файлах).
shellcheck: ## Проверка bash-скриптов (lib, экшены, kanboard, хук, хелперы)
	$(SHELLCHECK) -x $(SH_FILES)

yamllint: ## Проверка YAML (.github)
	$(YAMLLINT) -c .yamllint.yml .github

test: ## Юнит-тесты (bats)
	$(BATS) tests/

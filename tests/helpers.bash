#!/usr/bin/env bash
# Общие хелперы для bats-тестов.

# Абсолютный путь к корню репозитория.
repo_root() {
  cd "$BATS_TEST_DIRNAME/.." && pwd
}

# Возвращает значение ключа из файла $GITHUB_OUTPUT (последнее совпадение).
# Использование: output_value version
output_value() {
  local key="$1"
  grep "^${key}=" "$GITHUB_OUTPUT" | tail -n1 | cut -d= -f2-
}

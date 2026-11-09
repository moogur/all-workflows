#!/usr/bin/env bats
# Тесты для .github/actions/node-test-runner/detect.sh: какой раннер тестов найден
# в package.json и с какими аргументами он пишет JSON-отчёт.

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/node-test-runner/detect.sh"
  TMP="$(mktemp -d)"
  export GITHUB_OUTPUT="$TMP/output"
  : > "$GITHUB_OUTPUT"
}

teardown() {
  rm -rf "$TMP"
}

# Записывает package.json и запускает скрипт в каталоге $TMP.
detect_with() {
  printf '%s' "$1" > "$TMP/package.json"
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" RUNNER_TEMP="/runner/tmp" bash -c "cd '$TMP' && bash '$SCRIPT'"
}

@test "jest в devDependencies: формат jest и флаги jest" {
  detect_with '{"devDependencies": {"jest": "^29.0.0"}}'
  [ "$status" -eq 0 ]
  [ "$(output_value format)" = "jest" ]
  [ "$(output_value args)" = "--json --outputFile=/runner/tmp/test-report.json" ]
  [ "$(output_value report)" = "/runner/tmp/test-report.json" ]
}

@test "jest в dependencies тоже находится" {
  detect_with '{"dependencies": {"jest": "^29.0.0"}}'
  [ "$(output_value format)" = "jest" ]
  [ "$(output_value args)" = "--json --outputFile=/runner/tmp/test-report.json" ]
}

@test "vitest: формат jest, консольный вывод и аннотации сохранены, отчёт пишет json-репортер" {
  detect_with '{"devDependencies": {"vitest": "^2.0.0"}}'
  [ "$status" -eq 0 ]
  [ "$(output_value format)" = "jest" ]
  [ "$(output_value args)" = "--reporter=default --reporter=github-actions --reporter=json --outputFile.json=/runner/tmp/test-report.json" ]
}

@test "vitest в dependencies тоже находится" {
  detect_with '{"dependencies": {"vitest": "^2.0.0"}}'
  [[ "$(output_value args)" == "--reporter=default --reporter=github-actions --reporter=json "* ]]
}

@test "и vitest, и jest: побеждает vitest" {
  detect_with '{"devDependencies": {"jest": "^29.0.0", "vitest": "^2.0.0"}}'
  [[ "$(output_value args)" == "--reporter=default --reporter=github-actions --reporter=json "* ]]
}

@test "ни jest, ни vitest: format и args пусты, шаг не падает" {
  detect_with '{"devDependencies": {"mocha": "^10.0.0"}}'
  [ "$status" -eq 0 ]
  [ -z "$(output_value format)" ]
  [ -z "$(output_value args)" ]
}

@test "package.json без зависимостей: format и args пусты" {
  detect_with '{"name": "x"}'
  [ "$status" -eq 0 ]
  [ -z "$(output_value format)" ]
  [ -z "$(output_value args)" ]
}

@test "пакет с похожим именем (ts-jest, @vitest/ui) раннером не считается" {
  detect_with '{"devDependencies": {"ts-jest": "^29.0.0", "@vitest/ui": "^2.0.0"}}'
  [ -z "$(output_value format)" ]
}

@test "без package.json — ошибка" {
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" RUNNER_TEMP="/runner/tmp" bash -c "cd '$TMP' && bash '$SCRIPT'"
  [ "$status" -ne 0 ]
}

@test "без RUNNER_TEMP — ошибка" {
  printf '{}' > "$TMP/package.json"
  run env -u RUNNER_TEMP GITHUB_OUTPUT="$GITHUB_OUTPUT" bash -c "cd '$TMP' && bash '$SCRIPT'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"RUNNER_TEMP is required"* ]]
}

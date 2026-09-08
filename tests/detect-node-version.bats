#!/usr/bin/env bats
# Тесты для .github/actions/detect-node-version/detect.sh

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/detect-node-version/detect.sh"
  TMP="$(mktemp -d)"
  export GITHUB_OUTPUT="$TMP/output"
  : > "$GITHUB_OUTPUT"
}

teardown() {
  rm -rf "$TMP"
}

# Записывает package.json и запускает скрипт в каталоге $TMP.
detect_with() {
  printf '%s\n' "$1" > "$TMP/package.json"
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" bash -c "cd '$TMP' && bash '$SCRIPT'"
}

@test "точная версия из engines.node" {
  detect_with '{ "engines": { "node": "18.16.0" } }'
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "18.16.0" ]
}

@test "диапазон версии (>=)" {
  detect_with '{ "engines": { "node": ">=20.0.0" } }'
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = ">=20.0.0" ]
}

@test "caret-диапазон (^)" {
  detect_with '{ "engines": { "node": "^18.0.0" } }'
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "^18.0.0" ]
}

@test "engines с дополнительными полями (npm)" {
  detect_with '{ "engines": { "node": "20.11.1", "npm": ">=9" } }'
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "20.11.1" ]
}

@test "версия не зависит от других ключей package.json" {
  detect_with '{ "name": "x", "version": "9.9.9", "engines": { "node": "16.20.0" } }'
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "16.20.0" ]
}

@test "отсутствие engines.node — ошибка с сообщением" {
  # Раньше jq -r отдавал строку 'null', и setup-node падал невнятным
  # «Unable to find Node version null».
  detect_with '{ "name": "x" }'
  [ "$status" -ne 0 ]
  [[ "$output" == *"engines.node is not set"* ]]
}

@test "пустой engines.node — ошибка с сообщением" {
  detect_with '{ "engines": { "node": "" } }'
  [ "$status" -ne 0 ]
  [[ "$output" == *"engines.node is not set"* ]]
}

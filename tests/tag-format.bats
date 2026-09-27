#!/usr/bin/env bats
# Тесты для .github/actions/tag-format/format.sh: сам скрипт (env -> $GITHUB_OUTPUT).
# Классификация формата версии (дата/semver/ошибки) — в tests/lib-version.bats.

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/tag-format/format.sh"
  TMP="$(mktemp -d)"
  export GITHUB_OUTPUT="$TMP/output"
  : > "$GITHUB_OUTPUT"
}

teardown() {
  rm -rf "$TMP"
}

@test "дата: format=date уходит в GITHUB_OUTPUT" {
  run env VERSION=14.03.2026 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value format)" = "date" ]
}

@test "semver: format=semver уходит в GITHUB_OUTPUT" {
  run env VERSION=v1.2.3 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value format)" = "semver" ]
}

@test "версия неизвестного формата завершается с ошибкой и сообщением" {
  run env VERSION=master GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"neither a date"* ]]
}

@test "без обязательного входа VERSION завершается с ошибкой" {
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

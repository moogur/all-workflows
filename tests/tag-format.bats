#!/usr/bin/env bats
# Тесты для .github/actions/tag-format/format.sh

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

# ---------- дата ----------

@test "дата dd.mm.yyyy" {
  run env VERSION=14.03.2026 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value format)" = "date" ]
}

@test "метка авто-сборки со временем" {
  run env VERSION=14.03.2026-0930-auto GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value format)" = "date" ]
}

@test "старая метка авто-сборки без времени" {
  run env VERSION=14.03.2026-auto GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value format)" = "date" ]
}

# ---------- semver ----------

@test "semver vX.Y.Z" {
  run env VERSION=v1.2.3 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value format)" = "semver" ]
}

@test "semver с нулями в разрядах" {
  run env VERSION=v1.0.0 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value format)" = "semver" ]
}

@test "semver с многозначными разрядами" {
  run env VERSION=v10.29.106 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value format)" = "semver" ]
}

# ---------- ошибки ----------

@test "semver без префикса v отклоняется" {
  # Раньше docker-tags сам добавлял v; теперь это ошибка на входе.
  run env VERSION=1.2.3 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"neither a date"* ]]
}

@test "предрелизный тег отклоняется" {
  run env VERSION=v1.2.3-rc.1 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"neither a date"* ]]
}

@test "неполная версия отклоняется" {
  run env VERSION=v1.2 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"neither a date"* ]]
}

@test "дата не в формате dd.mm.yyyy отклоняется" {
  run env VERSION=2026-03-14 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"neither a date"* ]]
}

@test "произвольная строка отклоняется" {
  run env VERSION=master GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"neither a date"* ]]
}

@test "без обязательного входа version завершается с ошибкой" {
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

#!/usr/bin/env bats
# Тесты для .github/actions/docker-tags/tags.sh
# Формат версии (FORMAT) здесь приходит готовым, как от action tag-format —
# сама классификация версии проверяется в tests/tag-format.bats.

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/docker-tags/tags.sh"
  IMAGE="docker.pkg.github.com/user/repo/repo"
  TMP="$(mktemp -d)"
  export GITHUB_OUTPUT="$TMP/output"
  : > "$GITHUB_OUTPUT"
}

teardown() {
  rm -rf "$TMP"
}

# ---------- дата ----------

@test "дата: версия как есть и latest" {
  run env IMAGE="$IMAGE" VERSION=14.03.2026 FORMAT=date GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value tags)" = "$IMAGE:14.03.2026 $IMAGE:latest" ]
}

@test "дата: метка авто-сборки со временем" {
  run env IMAGE="$IMAGE" VERSION=14.03.2026-0930-auto FORMAT=date GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value tags)" = "$IMAGE:14.03.2026-0930-auto $IMAGE:latest" ]
}

# ---------- semver ----------

@test "semver: лестница vX.Y.Z, vX.Y, vX, latest" {
  run env IMAGE="$IMAGE" VERSION=v1.2.3 FORMAT=semver GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value tags)" = "$IMAGE:v1.2.3 $IMAGE:v1.2 $IMAGE:v1 $IMAGE:latest" ]
}

@test "semver: нули в разрядах сохраняются" {
  run env IMAGE="$IMAGE" VERSION=v1.0.0 FORMAT=semver GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value tags)" = "$IMAGE:v1.0.0 $IMAGE:v1.0 $IMAGE:v1 $IMAGE:latest" ]
}

@test "semver: многозначные разряды" {
  run env IMAGE="$IMAGE" VERSION=v10.29.106 FORMAT=semver GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value tags)" = "$IMAGE:v10.29.106 $IMAGE:v10.29 $IMAGE:v10 $IMAGE:latest" ]
}

# ---------- ошибки ----------

@test "неизвестный FORMAT отклоняется" {
  # Внутренний контракт с tag-format: сюда попадать не должно, но скрипт не молчит.
  run env IMAGE="$IMAGE" VERSION=v1.2.3 FORMAT=bogus GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown FORMAT"* ]]
}

@test "без FORMAT завершается с ошибкой" {
  run env IMAGE="$IMAGE" VERSION=v1.2.3 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "без IMAGE завершается с ошибкой" {
  run env VERSION=v1.2.3 FORMAT=semver GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "без VERSION завершается с ошибкой" {
  run env IMAGE="$IMAGE" FORMAT=semver GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

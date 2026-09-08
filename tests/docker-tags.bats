#!/usr/bin/env bats
# Тесты для .github/actions/docker-tags/tags.sh

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

# ---------- format_mode=date ----------

@test "date: версия как есть и latest" {
  run env IMAGE="$IMAGE" VERSION=14.03.2026 FORMAT_MODE=date GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value tags)" = "$IMAGE:14.03.2026 $IMAGE:latest" ]
}

@test "date: метка авто-деплоя не разбирается как версия" {
  run env IMAGE="$IMAGE" VERSION=14.03.2026-auto FORMAT_MODE=date GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value tags)" = "$IMAGE:14.03.2026-auto $IMAGE:latest" ]
}

@test "format_mode по умолчанию — date" {
  run env IMAGE="$IMAGE" VERSION=v1.2.3 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value tags)" = "$IMAGE:v1.2.3 $IMAGE:latest" ]
}

# ---------- format_mode=semver ----------

@test "semver: лестница vX.Y.Z, vX.Y, vX, latest" {
  run env IMAGE="$IMAGE" VERSION=v1.2.3 FORMAT_MODE=semver GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value tags)" = "$IMAGE:v1.2.3 $IMAGE:v1.2 $IMAGE:v1 $IMAGE:latest" ]
}

@test "semver: тег без префикса v получает префикс в тегах образа" {
  run env IMAGE="$IMAGE" VERSION=1.2.3 FORMAT_MODE=semver GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value tags)" = "$IMAGE:v1.2.3 $IMAGE:v1.2 $IMAGE:v1 $IMAGE:latest" ]
}

@test "semver: нули в разрядах сохраняются" {
  run env IMAGE="$IMAGE" VERSION=v1.0.0 FORMAT_MODE=semver GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value tags)" = "$IMAGE:v1.0.0 $IMAGE:v1.0 $IMAGE:v1 $IMAGE:latest" ]
}

@test "semver: многозначные разряды" {
  run env IMAGE="$IMAGE" VERSION=v10.29.106 FORMAT_MODE=semver GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value tags)" = "$IMAGE:v10.29.106 $IMAGE:v10.29 $IMAGE:v10 $IMAGE:latest" ]
}

# ---------- ошибки ----------

@test "semver: тег-дата отклоняется" {
  run env IMAGE="$IMAGE" VERSION=14.03.2026-auto FORMAT_MODE=semver GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not a semver tag"* ]]
}

@test "semver: предрелизный тег отклоняется" {
  run env IMAGE="$IMAGE" VERSION=v1.2.3-rc.1 FORMAT_MODE=semver GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not a semver tag"* ]]
}

@test "semver: неполная версия отклоняется" {
  run env IMAGE="$IMAGE" VERSION=v1.2 FORMAT_MODE=semver GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not a semver tag"* ]]
}

@test "неизвестный format_mode завершается с ошибкой и сообщением" {
  run env IMAGE="$IMAGE" VERSION=v1.2.3 FORMAT_MODE=bogus GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown format_mode"* ]]
}

@test "без обязательных входов завершается с ошибкой" {
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

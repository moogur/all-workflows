#!/usr/bin/env bats
# Тесты для .github/actions/app-version/resolve.sh

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/app-version/resolve.sh"
  TMP="$(mktemp -d)"
  export GITHUB_OUTPUT="$TMP/output"
  : > "$GITHUB_OUTPUT"
}

teardown() {
  rm -rf "$TMP"
}

# Создаёт временный git-репозиторий с переданными тегами (по тегу на коммит).
make_repo() {
  local repo="$TMP/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t
  git -C "$repo" config user.name t
  local tag
  for tag in "$@"; do
    git -C "$repo" commit -q --allow-empty -m "$tag"
    git -C "$repo" tag "$tag"
  done
  echo "$repo"
}

# ---------- mode=ref ----------

@test "ref: снимает префикс v по умолчанию" {
  run env MODE=ref PREFIX=v GITHUB_REF=refs/tags/v1.2.3 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "1.2.3" ]
}

@test "ref: пустой префикс оставляет тег как есть" {
  run env MODE=ref PREFIX='' GITHUB_REF=refs/tags/v1.2.3 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "v1.2.3" ]
}

@test "ref: префикс по умолчанию (PREFIX не задан) — v" {
  run env MODE=ref GITHUB_REF=refs/tags/v9.9.9 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "9.9.9" ]
}

@test "ref: тег без префикса при prefix=v остаётся без изменений" {
  run env MODE=ref PREFIX=v GITHUB_REF=refs/tags/1.2.3 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "1.2.3" ]
}

@test "ref: произвольный префикс release-" {
  run env MODE=ref PREFIX=release- GITHUB_REF=refs/tags/release-2.0 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "2.0" ]
}

@test "ref: предрелизный тег с суффиксом" {
  run env MODE=ref PREFIX=v GITHUB_REF=refs/tags/v1.2.3-rc.1 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "1.2.3-rc.1" ]
}

# ---------- mode=git ----------

@test "git: берёт последний тег и снимает префикс" {
  repo=$(make_repo v2.0.0)
  run env MODE=git PREFIX=v GITHUB_OUTPUT="$GITHUB_OUTPUT" bash -c "cd '$repo' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "2.0.0" ]
}

@test "git: при нескольких тегах берёт самый свежий" {
  repo=$(make_repo v1.0.0 v1.1.0 v2.3.4)
  run env MODE=git PREFIX=v GITHUB_OUTPUT="$GITHUB_OUTPUT" bash -c "cd '$repo' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "2.3.4" ]
}

@test "mode по умолчанию — git" {
  repo=$(make_repo v3.1.0)
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" bash -c "cd '$repo' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "3.1.0" ]
}

@test "git: пустой префикс оставляет тег как есть" {
  repo=$(make_repo v4.0.0)
  run env MODE=git PREFIX='' GITHUB_OUTPUT="$GITHUB_OUTPUT" bash -c "cd '$repo' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "v4.0.0" ]
}

# ---------- ошибки ----------

@test "неизвестный mode завершается с ошибкой и сообщением" {
  run env MODE=bogus GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown mode"* ]]
}

@test "git: без тегов завершается с ошибкой" {
  repo="$TMP/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t
  git -C "$repo" config user.name t
  git -C "$repo" commit -q --allow-empty -m init
  run env MODE=git GITHUB_OUTPUT="$GITHUB_OUTPUT" bash -c "cd '$repo' && bash '$SCRIPT'"
  [ "$status" -ne 0 ]
}

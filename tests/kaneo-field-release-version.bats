#!/usr/bin/env bats
# Тесты функции поля scripts/kaneo/fields/release_version.sh: версия последнего тега
# дописывается в список через запятую.

setup() {
  load helpers
  ROOT="$(repo_root)"
  FIELD="$ROOT/scripts/kaneo/fields/release_version.sh"
  TMP="$(mktemp -d)"
  REPO="$TMP/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t
  git -C "$REPO" config user.name t
}

teardown() {
  rm -rf "$TMP"
}

tag() {
  local name="$1" date="$2"
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" git -C "$REPO" commit -q --allow-empty -m "$name"
  GIT_COMMITTER_DATE="$date" git -C "$REPO" tag -a "$name" -m "$name"
}

# field <текущее значение> — вызывает функцию поля в репозитории с контекстом через env.
field() {
  run env KANEO_FIELD_VALUE="$1" bash -c "cd '$REPO' && source '$FIELD' && kaneo_field_release_version"
}

# ---------- kaneo_field_release_version ----------

@test "пустое поле -> версия последнего тега без префикса v" {
  tag v1.1.0 2024-01-02T10:00:00
  field ''
  [ "$status" -eq 0 ]
  [ "$output" = "1.1.0" ]
}

@test "в поле другая версия -> дописывается через запятую" {
  tag v1.1.0 2024-01-02T10:00:00
  field '1.0.0'
  [ "$output" = "1.0.0, 1.1.0" ]
}

@test "версия уже в списке -> значение без изменений, код 0" {
  tag v1.1.0 2024-01-02T10:00:00
  field '1.0.0, 1.1.0'
  [ "$status" -eq 0 ]
  [ "$output" = "1.0.0, 1.1.0" ]
}

@test "совпадение по целому элементу: 1.2 в поле не мешает дописать 1.2.3" {
  tag v1.2.3 2024-01-02T10:00:00
  field '1.2'
  [ "$output" = "1.2, 1.2.3" ]
}

@test "совпадение по целому элементу: 1.2.3 в поле не считается версией 1.2" {
  tag v1.2 2024-01-02T10:00:00
  field '1.2.3'
  [ "$output" = "1.2.3, 1.2" ]
}

@test "пробелы вокруг элементов не мешают найти версию" {
  tag v1.1.0 2024-01-02T10:00:00
  field '1.0.0 ,   1.1.0  '
  [ "$output" = '1.0.0 ,   1.1.0  ' ]
}

@test "берётся последний тег по дате создания, а не по имени" {
  tag v9.0.0 2024-01-01T10:00:00
  tag v1.0.0 2024-02-01T10:00:00
  field ''
  [ "$output" = "1.0.0" ]
}

@test "датный тег остаётся без изменений" {
  tag 14.03.2026 2026-03-14T10:00:00
  field ''
  [ "$output" = "14.03.2026" ]
}

@test "нет тегов -> код 1, сообщение в stderr, stdout пуст" {
  run env KANEO_FIELD_VALUE='1.0.0' bash -c "cd '$REPO' && source '$FIELD' && kaneo_field_release_version 2>'$TMP/err'"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  grep -q "нет тегов" "$TMP/err"
}

@test "kaneo_merge_versions: версия уже в списке -> код 1, вывода нет" {
  run bash -c "source '$FIELD'; kaneo_merge_versions '1.0.0, 1.1.0' 1.1.0"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

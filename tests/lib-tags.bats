#!/usr/bin/env bats
# Тесты для lib/tags.sh: последний тег и N последних тегов по дате создания
# (--sort=-creatordate, никогда по имени).

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/lib/tags.sh"
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

# tag <имя> <дата> — аннотированный тег на пустом коммите; дата создания — из GIT_COMMITTER_DATE.
tag() {
  local name="$1" date="$2"
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git -C "$REPO" commit -q --allow-empty -m "$name"
  GIT_COMMITTER_DATE="$date" git -C "$REPO" tag -a "$name" -m "$name"
}

sh() {
  run bash -c "source '$LIB'; $*"
}

# ---------- tags_latest_n ----------

@test "latest_n: одна дата — среди дат «максимум» не побеждает по имени" {
  tag 26.05.2023 2023-05-26T10:00:00
  tag 14.03.2026 2026-03-14T10:00:00
  sh "tags_latest_n 1 '$REPO'"
  [ "$status" -eq 0 ]
  [ "$output" = "14.03.2026" ]
}

@test "latest_n 2: два последних тега, от самого свежего" {
  tag v1.0.0 2024-01-01T10:00:00
  tag v1.1.0 2024-01-02T10:00:00
  tag v1.2.0 2024-01-03T10:00:00
  sh "tags_latest_n 2 '$REPO'"
  [ "$output" = $'v1.2.0\nv1.1.0' ]
}

@test "latest_n: n больше числа тегов отдаёт все теги, не падает" {
  tag v1.0.0 2024-01-01T10:00:00
  sh "tags_latest_n 5 '$REPO'"
  [ "$status" -eq 0 ]
  [ "$output" = "v1.0.0" ]
}

@test "latest_n: без тегов отдаёт пустую строку, не падает" {
  git -C "$REPO" commit -q --allow-empty -m init
  sh "tags_latest_n 1 '$REPO'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "latest_n: репозиторий по умолчанию — текущая директория" {
  tag v1.0.0 2024-01-01T10:00:00
  run bash -c "cd '$REPO' && source '$LIB' && tags_latest_n 1"
  [ "$output" = "v1.0.0" ]
}

# ---------- tags_previous ----------

@test "previous: сосед по дате создания, а не максимум по имени" {
  tag 26.05.2023 2023-05-26T10:00:00
  tag 14.03.2026 2026-03-14T10:00:00
  sh "tags_previous 14.03.2026 '$REPO'"
  [ "$output" = "26.05.2023" ]
}

@test "previous: у самого старого тега предыдущего нет" {
  tag v1.0.0 2024-01-01T10:00:00
  tag v1.1.0 2024-01-02T10:00:00
  sh "tags_previous v1.0.0 '$REPO'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "previous: несуществующий тег отдаёт пустую строку" {
  tag v1.0.0 2024-01-01T10:00:00
  sh "tags_previous v9.9.9 '$REPO'"
  [ -z "$output" ]
}

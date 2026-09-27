#!/usr/bin/env bats
# Тесты для scripts/kanboard_task_id.sh: откуда kanboard.yml берёт task_id/версию.
# Сам разбор ("второе слово", последний тег, ...) — в tests/lib-commit.bats и
# tests/lib-tags.bats.

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/scripts/kanboard_task_id.sh"
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

commit() {
  local message="$1" date="${2:-2024-01-01T00:00:00}"
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git -C "$REPO" commit -q --allow-empty -m "$message"
}

tag() {
  local name="$1" date="$2"
  GIT_COMMITTER_DATE="$date" git -C "$REPO" tag -a "$name" -m "$name"
}

sh() {
  run bash -c "source '$LIB'; $*"
}

# ---------- kanboard_task_id_from_last_commit ----------

@test "from_last_commit: task_id из заголовка последнего коммита" {
  commit '[GA-557] feature(frontend): add endpoint'
  sh "kanboard_task_id_from_last_commit '$REPO'"
  [ "$output" = "557" ]
}

# ---------- kanboard_task_id_from_ref ----------

@test "from_ref: task_id из имени ветки" {
  sh "kanboard_task_id_from_ref GA-123-fix-thing"
  [ "$output" = "123" ]
}

# ---------- kanboard_release_version ----------

@test "release_version: снимает префикс v" {
  sh "kanboard_release_version v1.2.3"
  [ "$output" = "1.2.3" ]
}

@test "release_version: датный тег остаётся без изменений" {
  sh "kanboard_release_version 14.03.2026"
  [ "$output" = "14.03.2026" ]
}

# ---------- kanboard_deploy_tags ----------

@test "deploy_tags: два последних тега, от самого свежего" {
  commit init 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit second 2024-01-02T10:00:00
  tag v1.1.0 2024-01-02T10:00:00
  sh "kanboard_deploy_tags '$REPO'"
  [ "$output" = $'v1.1.0\nv1.0.0' ]
}

# ---------- kanboard_deploy_task_ids ----------

@test "deploy_task_ids: диапазон между двумя тегами, без дублей" {
  commit init 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): one' 2024-01-02T10:00:00
  commit '[GA-1] feature(api): fixup' 2024-01-02T11:00:00
  commit '[GA-2] bugfix(api): two' 2024-01-02T12:00:00
  tag v1.1.0 2024-01-02T13:00:00
  sh "kanboard_deploy_task_ids v1.1.0 v1.0.0 '$REPO' | sort"
  [ "$output" = $'1\n2' ]
}

@test "deploy_task_ids: без предыдущего тега берёт всю историю" {
  commit '[GA-9] feature(api): only' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  sh "kanboard_deploy_task_ids v1.0.0 '' '$REPO'"
  [ "$output" = "9" ]
}

@test "deploy_task_ids: коммит не по формату не даёт числового id" {
  commit init 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit 'Update README.md' 2024-01-02T10:00:00
  tag v1.1.0 2024-01-02T11:00:00
  sh "kanboard_deploy_task_ids v1.1.0 v1.0.0 '$REPO'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

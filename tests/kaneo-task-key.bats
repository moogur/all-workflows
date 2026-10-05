#!/usr/bin/env bats
# Тесты scripts/kaneo/task_key.sh: откуда engine.sh берёт номер задачи.
# Сам разбор (номер из текста, последний тег, ...) — в tests/lib-commit.bats и
# tests/lib-tags.bats.

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/scripts/kaneo/task_key.sh"
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

# ---------- kaneo_task_key_from_last_commit ----------

@test "from_last_commit: номер из заголовка последнего коммита" {
  commit '[GA-557] feature(frontend): add endpoint'
  sh "kaneo_task_key_from_last_commit '$REPO'"
  [ "$output" = "GA-557" ]
}

@test "from_last_commit: берётся последний коммит, а не предыдущий" {
  commit '[GA-1] feature(api): old' 2024-01-01T10:00:00
  commit '[GA-2] feature(api): new' 2024-01-02T10:00:00
  sh "kaneo_task_key_from_last_commit '$REPO'"
  [ "$output" = "GA-2" ]
}

@test "from_last_commit: номер в теле коммита не считается" {
  commit $'chore without key\n\n[GA-9] mentioned in body'
  sh "kaneo_task_key_from_last_commit '$REPO'"
  [ -z "$output" ]
}

# ---------- kaneo_task_key_from_ref ----------

@test "from_ref: номер из имени ветки" {
  sh "kaneo_task_key_from_ref GA-123-fix-thing"
  [ "$output" = "GA-123" ]
}

# ---------- kaneo_task_key_by_source ----------

@test "by_source: commit берёт номер из последнего коммита, а не из имени ветки" {
  commit '[GA-7] bugfix(api): x'
  run env GITHUB_REF_NAME=GA-99-other \
    bash -c "cd '$REPO' && source '$LIB' && kaneo_task_key_by_source commit push"
  [ "$output" = "GA-7" ]
}

@test "by_source: branch на pr и merge берёт номер из HEAD_REF" {
  local event
  for event in pr merge; do
    run env HEAD_REF=GA-5-feature GITHUB_REF_NAME=merge-ref \
      bash -c "source '$LIB' && kaneo_task_key_by_source branch $event"
    [ "$output" = "GA-5" ]
  done
}

@test "by_source: branch на push берёт номер из GITHUB_REF_NAME, а не из HEAD_REF" {
  run env HEAD_REF=GA-5-feature GITHUB_REF_NAME=GA-6_branch \
    bash -c "source '$LIB' && kaneo_task_key_by_source branch push"
  [ "$output" = "GA-6" ]
}

@test "by_source: ветка без номера — пусто, код 0" {
  run env GITHUB_REF_NAME=master \
    bash -c "source '$LIB' && kaneo_task_key_by_source branch push"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "by_source: неизвестный источник — пусто, код 0" {
  run env GITHUB_REF_NAME=GA-1-x \
    bash -c "source '$LIB' && kaneo_task_key_by_source other push"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------- недоверенный ввод ----------
# Заголовок коммита и имя ветки задаёт автор: номер не по формату не пропускается,
# и ничего не исполняется (docs/security.md, п. 8).

@test "from_last_commit: подстановка команды в заголовке — номера нет, команда не выполнена" {
  local marker="$TMP/pwned"
  commit "[GA-\$(touch\${IFS}$marker)] feature(api): x"
  sh "kaneo_task_key_from_last_commit '$REPO'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$marker" ]
}

@test "from_last_commit: заголовок '[GA-1;id] ...' не даёт номера" {
  commit '[GA-1;id] feature(api): x'
  sh "kaneo_task_key_from_last_commit '$REPO'"
  [ -z "$output" ]
}

@test "from_ref: имена веток 'GA-\$(id)-x' и 'GA-1;id' не дают номера" {
  sh "kaneo_task_key_from_ref 'GA-\$(id)-x'"
  [ -z "$output" ]
  sh "kaneo_task_key_from_ref 'GA-1;id'"
  [ -z "$output" ]
}

@test "from_ref: подстановка команды в имени ветки не выполняется" {
  local marker="$TMP/pwned"
  sh "kaneo_task_key_from_ref 'GA-\$(touch\${IFS}$marker)-x'"
  [ -z "$output" ]
  [ ! -e "$marker" ]
}

# ---------- kaneo_deploy_tags ----------

@test "deploy_tags: два последних тега, от самого свежего" {
  commit init 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit second 2024-01-02T10:00:00
  tag v1.1.0 2024-01-02T10:00:00
  commit third 2024-01-03T10:00:00
  tag v1.2.0 2024-01-03T10:00:00
  sh "kaneo_deploy_tags '$REPO'"
  [ "$output" = $'v1.2.0\nv1.1.0' ]
}

@test "deploy_tags: без тегов пусто" {
  commit init
  sh "kaneo_deploy_tags '$REPO'"
  [ -z "$output" ]
}

# ---------- kaneo_deploy_task_keys ----------

@test "deploy_task_keys: диапазон между двумя тегами, без дублей" {
  commit init 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): one' 2024-01-02T10:00:00
  commit '[GA-1] feature(api): fixup' 2024-01-02T11:00:00
  commit '[GA-2] bugfix(api): two' 2024-01-02T12:00:00
  tag v1.1.0 2024-01-02T13:00:00
  sh "kaneo_deploy_task_keys v1.1.0 v1.0.0 '$REPO' | sort"
  [ "$output" = $'GA-1\nGA-2' ]
}

@test "deploy_task_keys: коммиты до предыдущего тега не попадают" {
  commit '[GA-1] feature(api): before' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T11:00:00
  commit '[GA-2] feature(api): after' 2024-01-02T10:00:00
  tag v1.1.0 2024-01-02T11:00:00
  sh "kaneo_deploy_task_keys v1.1.0 v1.0.0 '$REPO'"
  [ "$output" = "GA-2" ]
}

@test "deploy_task_keys: без предыдущего тега берёт всю историю" {
  commit '[GA-9] feature(api): only' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  sh "kaneo_deploy_task_keys v1.0.0 '' '$REPO'"
  [ "$output" = "GA-9" ]
}

@test "deploy_task_keys: префиксы разных проектов сохраняются" {
  commit '[IPB-4] feature(api): other project' 2024-01-01T10:00:00
  commit '[GA-4] feature(api): this project' 2024-01-01T11:00:00
  tag v1.0.0 2024-01-01T12:00:00
  sh "kaneo_deploy_task_keys v1.0.0 '' '$REPO' | sort"
  [ "$output" = $'GA-4\nIPB-4' ]
}

@test "deploy_task_keys: коммит не по формату не даёт номера" {
  commit init 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit 'Update README.md' 2024-01-02T10:00:00
  tag v1.1.0 2024-01-02T11:00:00
  sh "kaneo_deploy_task_keys v1.1.0 v1.0.0 '$REPO'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "deploy_task_keys: вредоносный заголовок пропускается, валидные остаются" {
  commit init 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-$(id)] bugfix(api): bad' 2024-01-02T10:00:00
  commit '[GA-5] bugfix(api): good' 2024-01-02T11:00:00
  tag v1.1.0 2024-01-02T12:00:00
  sh "kaneo_deploy_task_keys v1.1.0 v1.0.0 '$REPO'"
  [ "$output" = "GA-5" ]
}

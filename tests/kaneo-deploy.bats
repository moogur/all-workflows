#!/usr/bin/env bats
# Тесты scripts/kaneo_deploy.sh: событие deploy (перенос merged -> deploy и запись версии
# в поле App_version). curl подменяется заглушкой с ответами по маршруту, git — настоящий.

setup() {
  load helpers
  load kaneo_helpers
  ROOT="$(repo_root)"
  TMP="$(mktemp -d)"
  kaneo_stub_setup
  export KANEO_SCRIPT=kaneo_deploy.sh
  export KANEO_STATUS_MERGED=merged KANEO_STATUS_DEPLOY=deployed
  git -C "$WORK" init -q
  git -C "$WORK" config user.email t@t
  git -C "$WORK" config user.name t
}

teardown() {
  rm -rf "$TMP"
}

commit() {
  local message="$1" date="$2"
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git -C "$WORK" commit -q --allow-empty -m "$message"
}

tag() {
  GIT_COMMITTER_DATE="$2" git -C "$WORK" tag -a "$1" -m "$1"
}

# Релиз v1.1.0 с одной задачей GA-1 (предыдущий тег v1.0.0).
release_with_ga1() {
  commit init 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): one' 2024-01-02T10:00:00
  tag v1.1.0 2024-01-02T11:00:00
}

# task <номер> <id> <статус> — задача в проекте pid1 и ответ на перенос в deployed.
task() {
  kaneo_respond "GET /api/task/by-ticket-id/$1" "$(kaneo_task_json "$3" "$2" pid1)"
  kaneo_respond "PUT /api/task/status/$2" "$(kaneo_task_json deployed "$2" pid1)"
}

# fields <id задачи> <значение поля App_version или ''> — поле App_version у проекта pid1
# и его значение у задачи ('' — значения нет вовсе, как в API для незаполненных полей).
fields() {
  kaneo_respond "GET /api/custom-field/project/pid1" \
    '[{"id":"other","name":"Sprint"},{"id":"fid1","name":"App_version"}]'
  if [[ -n "$2" ]]; then
    kaneo_respond "GET /api/custom-field/task/$1" \
      "[{\"fieldId\":\"other\",\"value\":\"s1\"},{\"fieldId\":\"fid1\",\"value\":\"$2\"}]"
  else
    kaneo_respond "GET /api/custom-field/task/$1" '[{"fieldId":"other","value":"s1"}]'
  fi
}

# Ответ на запись значения поля: API возвращает то, что записано.
value_saved() {
  kaneo_respond "PUT /api/custom-field/value" \
    "{\"id\":\"v1\",\"taskId\":\"$1\",\"fieldId\":\"fid1\",\"value\":\"$2\"}"
}

report() {
  cat "$WORK/message.tmpl"
}

sent_values() {
  jq -r 'select(has("fieldId")) | .value' "$BODIES"
}

# ---------- kaneo_merge_versions ----------

@test "merge_versions: пустое поле -> версия как есть" {
  kaneo_run "kaneo_merge_versions '' 1.1.0"
  [ "$status" -eq 0 ]
  [ "$output" = "1.1.0" ]
}

@test "merge_versions: другая версия в поле -> дописывается через запятую" {
  kaneo_run "kaneo_merge_versions 1.0.0 1.1.0"
  [ "$status" -eq 0 ]
  [ "$output" = "1.0.0, 1.1.0" ]
}

@test "merge_versions: версия уже в списке -> код 1, вывода нет" {
  kaneo_run "kaneo_merge_versions '1.0.0, 1.1.0' 1.1.0"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "merge_versions: совпадение по целому элементу, а не по подстроке" {
  kaneo_run "kaneo_merge_versions '1.1.0.1' 1.1.0"
  [ "$output" = "1.1.0.1, 1.1.0" ]
  kaneo_run "kaneo_merge_versions '1.1' 1.1.0"
  [ "$output" = "1.1, 1.1.0" ]
}

@test "merge_versions: пробелы вокруг элементов не мешают найти версию" {
  kaneo_run "kaneo_merge_versions '1.0.0 ,   1.1.0  ' 1.1.0"
  [ "$status" -eq 1 ]
}

# ---------- kaneo_on_deploy: перенос и версия ----------

@test "deploy: задача в merged -> deployed, версия без префикса v записана в App_version" {
  release_with_ga1
  task GA-1 t1 merged
  fields t1 ''
  value_saved t1 1.1.0
  kaneo_run kaneo_on_deploy
  [ "$status" -eq 0 ]
  grep -qx "PUT /api/task/status/t1" "$CALLS"
  jq -e 'select(has("status")) | . == {status: "deployed"}' "$BODIES" >/dev/null
  [ "$(sent_values)" = "1.1.0" ]
  [[ "$(report)" == *"The task GA-1 has been successfully moved to the 'DEPLOY' column"* ]]
  [[ "$(report)" == *"For the task GA-1, a version has been added"* ]]
}

@test "deploy: версия дописывается к уже стоящей" {
  release_with_ga1
  task GA-1 t1 merged
  fields t1 1.0.0
  value_saved t1 "1.0.0, 1.1.0"
  kaneo_run kaneo_on_deploy
  [ "$(sent_values)" = "1.0.0, 1.1.0" ]
  [[ "$(report)" == *"a version has been added"* ]]
}

@test "deploy: версия уже стоит — запись не отправляется" {
  release_with_ga1
  task GA-1 t1 merged
  fields t1 "1.0.0, 1.1.0"
  kaneo_run kaneo_on_deploy
  [ "$status" -eq 0 ]
  ! grep -qx "PUT /api/custom-field/value" "$CALLS"
}

@test "deploy: поле со значением null считается пустым" {
  release_with_ga1
  task GA-1 t1 merged
  fields t1 ''
  kaneo_respond "GET /api/custom-field/task/t1" '[{"fieldId":"fid1","value":null}]'
  value_saved t1 1.1.0
  kaneo_run kaneo_on_deploy
  [ "$(sent_values)" = "1.1.0" ]
}

@test "deploy: задача не в merged — статус не трогаем (SKIPPED), версия всё равно записывается" {
  release_with_ga1
  task GA-1 t1 in-progress
  fields t1 ''
  value_saved t1 1.1.0
  kaneo_run kaneo_on_deploy
  ! grep -qx "PUT /api/task/status/t1" "$CALLS"
  [[ "$(report)" == *"SKIPPED"* ]]
  [ "$(sent_values)" = "1.1.0" ]
}

@test "deploy: в проекте нет поля App_version — строка в лог, запись не отправляется" {
  release_with_ga1
  task GA-1 t1 merged
  kaneo_respond "GET /api/custom-field/project/pid1" '[{"id":"other","name":"Sprint"}]'
  kaneo_run kaneo_on_deploy
  [ "$status" -eq 0 ]
  [[ "$output" == *"нет поля App_version"* ]]
  grep -qx "PUT /api/task/status/t1" "$CALLS"
  ! grep -qx "PUT /api/custom-field/value" "$CALLS"
  ! grep -qx "GET /api/custom-field/task/t1" "$CALLS"
}

@test "deploy: значения полей не прочитались — ERROR и запись не отправляется (версии не затираются)" {
  release_with_ga1
  task GA-1 t1 merged
  kaneo_respond "GET /api/custom-field/project/pid1" '[{"id":"fid1","name":"App_version"}]'
  kaneo_run kaneo_on_deploy
  [ "$status" -eq 0 ]
  ! grep -qx "PUT /api/custom-field/value" "$CALLS"
  [[ "$(report)" == *"An error occurred when adding a version to the task GA-1"* ]]
}

@test "deploy: определения полей проекта не прочитались — ERROR, запись не отправляется" {
  release_with_ga1
  task GA-1 t1 merged
  kaneo_run kaneo_on_deploy
  [ "$status" -eq 0 ]
  ! grep -qx "PUT /api/custom-field/value" "$CALLS"
  [[ "$(report)" == *"An error occurred when adding a version to the task GA-1"* ]]
}

@test "deploy: небезопасный id поля в ответе — ERROR, запись не отправляется" {
  release_with_ga1
  task GA-1 t1 merged
  kaneo_respond "GET /api/custom-field/project/pid1" '[{"id":"f 1;id","name":"App_version"}]'
  kaneo_run kaneo_on_deploy
  ! grep -qx "PUT /api/custom-field/value" "$CALLS"
  [[ "$(report)" == *"An error occurred when adding a version"* ]]
}

@test "deploy: Kaneo вернул другое значение поля — ERROR в отчёте" {
  release_with_ga1
  task GA-1 t1 merged
  fields t1 ''
  value_saved t1 "something-else"
  kaneo_run kaneo_on_deploy
  [[ "$(report)" == *"An error occurred when adding a version to the task GA-1"* ]]
}

@test "deploy: запись поля отклонена (HTTP-ошибка) — ERROR, шаг не падает" {
  release_with_ga1
  task GA-1 t1 merged
  fields t1 ''
  kaneo_run kaneo_on_deploy
  [ "$status" -eq 0 ]
  [[ "$(report)" == *"An error occurred when adding a version to the task GA-1"* ]]
}

# ---------- несколько задач ----------

@test "deploy: не получены данные одной задачи — ERROR по ней и обработка остальных" {
  commit init 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): one' 2024-01-02T10:00:00
  commit '[GA-2] feature(api): two' 2024-01-02T11:00:00
  tag v1.1.0 2024-01-02T12:00:00
  task GA-2 t2 merged
  fields t2 ''
  value_saved t2 1.1.0
  kaneo_run kaneo_on_deploy
  [ "$status" -eq 0 ]
  [[ "$(report)" == *"An error occurred while getting information about the task GA-1"* ]]
  grep -qx "PUT /api/task/status/t2" "$CALLS"
}

@test "deploy: ссылка в отчёте относится к своей задаче, а не к предыдущей" {
  commit init 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): one' 2024-01-02T10:00:00
  commit '[GA-2] feature(api): two' 2024-01-02T11:00:00
  tag v1.1.0 2024-01-02T12:00:00
  task GA-2 t2 merged
  fields t2 ''
  value_saved t2 1.1.0
  kaneo_run kaneo_on_deploy
  # Ссылок на t1 нет: данные GA-1 не получены, а private_* сброшены между задачами.
  [[ "$(report)" != *"/task/t1"* ]]
  [[ "$(report)" == *"/task/t2"* ]]
}

@test "deploy: определения полей проекта запрашиваются один раз на проект" {
  commit init 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): one' 2024-01-02T10:00:00
  commit '[GA-2] feature(api): two' 2024-01-02T11:00:00
  tag v1.1.0 2024-01-02T12:00:00
  task GA-1 t1 merged
  task GA-2 t2 merged
  fields t1 ''
  kaneo_respond "GET /api/custom-field/task/t2" '[]'
  kaneo_respond "PUT /api/custom-field/value" \
    '{"id":"v1","taskId":"x","fieldId":"fid1","value":"1.1.0"}'
  kaneo_run kaneo_on_deploy
  [ "$(grep -cx 'GET /api/custom-field/project/pid1' "$CALLS")" -eq 1 ]
  [ "$(grep -cx 'PUT /api/custom-field/value' "$CALLS")" -eq 2 ]
}

@test "deploy: один тег в репозитории — берутся задачи всей истории" {
  commit '[GA-1] feature(api): one' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T11:00:00
  task GA-1 t1 merged
  fields t1 ''
  value_saved t1 1.0.0
  kaneo_run kaneo_on_deploy
  grep -qx "PUT /api/task/status/t1" "$CALLS"
}

@test "deploy: датный тег записывается как есть" {
  commit init 2024-01-01T10:00:00
  tag 01.01.2024 2024-01-01T10:00:00
  commit '[GA-1] feature(api): one' 2024-01-02T10:00:00
  tag 02.01.2024 2024-01-02T11:00:00
  task GA-1 t1 merged
  fields t1 ''
  value_saved t1 02.01.2024
  kaneo_run kaneo_on_deploy
  [ "$(sent_values)" = "02.01.2024" ]
}

# ---------- пропуски ----------

@test "deploy: в диапазоне нет коммитов с номером — запросов нет" {
  commit init 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit 'no key here' 2024-01-02T10:00:00
  tag v1.1.0 2024-01-02T11:00:00
  kaneo_run kaneo_on_deploy
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "deploy: пустой kaneo_status_deploy — строка в лог, запросов нет" {
  release_with_ga1
  export KANEO_STATUS_DEPLOY=''
  kaneo_run kaneo_on_deploy
  [ "$status" -eq 0 ]
  [[ "$output" == *"для события deploy не заданы"* ]]
  [ ! -s "$CALLS" ]
}

@test "deploy: пустой kaneo_status_merged — строка в лог, запросов нет" {
  release_with_ga1
  export KANEO_STATUS_MERGED=''
  kaneo_run kaneo_on_deploy
  [[ "$output" == *"для события deploy не заданы"* ]]
  [ ! -s "$CALLS" ]
}

@test "deploy: в репозитории нет тегов — строка в лог, запросов нет" {
  commit '[GA-1] feature(api): one' 2024-01-01T10:00:00
  kaneo_run kaneo_on_deploy
  [ "$status" -eq 0 ]
  [[ "$output" == *"нет тегов"* ]]
  [ ! -s "$CALLS" ]
}

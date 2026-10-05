#!/usr/bin/env bats
# Тесты движка scripts/kaneo/engine.sh: схема + событие -> перенос задач и запись полей.
# curl подменяется заглушкой с ответами по маршруту, git — настоящий.

setup() {
  load helpers
  load kaneo_helpers
  ROOT="$(repo_root)"
  TMP="$(mktemp -d)"
  kaneo_stub_setup
  kaneo_echo_bodies
  export EVENT_TYPE=push KANEO_SCHEME=single
  git -C "$WORK" init -q
  git -C "$WORK" config user.email t@t
  git -C "$WORK" config user.name t
}

teardown() {
  rm -rf "$TMP"
}

engine() {
  kaneo_run kaneo_run
}

commit() {
  local message="$1" date="${2:-2024-01-01T10:00:00}"
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

# task <номер> <id> <статус> — задача в проекте pid1.
task() {
  kaneo_respond "GET /api/task/by-ticket-id/$1" "$(kaneo_task_json "$3" "$2" pid1)"
}

# project_fields <json> / task_values <id задачи> <json> — определения полей проекта pid1
# и значения полей задачи.
project_fields() {
  kaneo_respond "GET /api/custom-field/project/pid1" "$1"
}

task_values() {
  kaneo_respond "GET /api/custom-field/task/$1" "$2"
}

version_field() {
  project_fields '[{"id":"other","name":"Sprint"},{"id":"fid1","name":"Version"}]'
}

# use_schemes <json> — своя схема вместо schemes.json (KANEO_SCHEMES_FILE — только для тестов).
use_schemes() {
  printf '%s' "$1" > "$TMP/schemes.json"
  export KANEO_SCHEMES_FILE="$TMP/schemes.json"
}

# use_field_func <имя> <тело файла> — свой файл функции поля в $TMP/fields.
use_field_func() {
  mkdir -p "$TMP/fields"
  printf '%s\n' "$2" > "$TMP/fields/$1.sh"
  export KANEO_FIELDS_DIR="$TMP/fields"
}

report() {
  cat "$WORK/message.tmpl"
}

status_bodies() {
  jq -c 'select(has("status"))' "$BODIES"
}

sent_values() {
  jq -r 'select(has("fieldId")) | .value' "$BODIES"
}

called() {
  grep -qx "$1" "$CALLS"
}

# ---------- схемы и события ----------

@test "single push: задача из backlog переносится в in-progress" {
  commit '[GA-1] feature(api): x'
  task GA-1 t1 backlog
  engine
  [ "$status" -eq 0 ]
  called "PUT /api/task/status/t1"
  [ "$(status_bodies)" = '{"status":"in-progress"}' ]
  [[ "$(report)" == *"successfully moved to the 'in-progress' column"* ]]
}

@test "single push: задача из hold тоже переносится" {
  commit '[GA-1] feature(api): x'
  task GA-1 t1 hold
  engine
  called "PUT /api/task/status/t1"
}

@test "single push: задача уже в in-progress — SKIPPED, перенос не отправляется" {
  commit '[GA-1] feature(api): x'
  task GA-1 t1 in-progress
  engine
  [ "$status" -eq 0 ]
  ! called "PUT /api/task/status/t1"
  [[ "$(report)" == *"SKIPPED"* ]]
}

@test "single push: номер задачи берётся из последнего коммита, а не из ветки" {
  commit '[GA-1] feature(api): x'
  task GA-1 t1 backlog
  GITHUB_REF_NAME=GA-9-other engine
  called "GET /api/task/by-ticket-id/GA-1"
}

@test "single deploy: in-progress -> done и версия без префикса v в Version" {
  EVENT_TYPE=deploy
  release_with_ga1
  task GA-1 t1 in-progress
  version_field
  task_values t1 '[]'
  engine
  [ "$status" -eq 0 ]
  [ "$(status_bodies)" = '{"status":"done"}' ]
  [ "$(sent_values)" = "1.1.0" ]
  [[ "$(report)" == *"The field 'Version' of the task GA-1 has been updated"* ]]
}

@test "single deploy: задача в ready не двигается (в single её нет в from) и поля не трогаются" {
  EVENT_TYPE=deploy
  release_with_ga1
  task GA-1 t1 ready
  engine
  ! called "PUT /api/task/status/t1"
  ! called "GET /api/custom-field/project/pid1"
  [[ "$(report)" == *"SKIPPED"* ]]
}

@test "single_ready deploy: задача в ready тоже переносится в done" {
  EVENT_TYPE=deploy KANEO_SCHEME=single_ready
  release_with_ga1
  task GA-1 t1 ready
  version_field
  task_values t1 '[]'
  engine
  [ "$(status_bodies)" = '{"status":"done"}' ]
  [ "$(sent_values)" = "1.1.0" ]
}

@test "multi push: номер из GITHUB_REF_NAME, backlog -> in-progress" {
  KANEO_SCHEME=multi
  task GA-5 t5 backlog
  GITHUB_REF_NAME=GA-5-feature HEAD_REF=GA-9-other engine
  [ "$(status_bodies)" = '{"status":"in-progress"}' ]
  called "GET /api/task/by-ticket-id/GA-5"
}

@test "multi pr: номер из HEAD_REF, in-progress -> review" {
  KANEO_SCHEME=multi EVENT_TYPE=pr
  task GA-5 t5 in-progress
  GITHUB_REF_NAME=merge-ref HEAD_REF=GA-5-feature engine
  [ "$(status_bodies)" = '{"status":"review"}' ]
}

@test "multi pr: задача не в in-progress — SKIPPED" {
  KANEO_SCHEME=multi EVENT_TYPE=pr
  task GA-5 t5 backlog
  HEAD_REF=GA-5-feature engine
  ! called "PUT /api/task/status/t5"
  [[ "$(report)" == *"SKIPPED"* ]]
}

@test "multi merge: review -> merged" {
  KANEO_SCHEME=multi EVENT_TYPE=merge
  task GA-5 t5 review
  HEAD_REF=GA-5-feature engine
  [ "$(status_bodies)" = '{"status":"merged"}' ]
}

@test "multi deploy: merged -> done и версия записана" {
  KANEO_SCHEME=multi EVENT_TYPE=deploy
  release_with_ga1
  task GA-1 t1 merged
  version_field
  task_values t1 '[{"fieldId":"fid1","value":"1.0.0"}]'
  engine
  [ "$(status_bodies)" = '{"status":"done"}' ]
  [ "$(sent_values)" = "1.0.0, 1.1.0" ]
}

@test "multi deploy: задача в in-progress — SKIPPED без полей" {
  KANEO_SCHEME=multi EVENT_TYPE=deploy
  release_with_ga1
  task GA-1 t1 in-progress
  engine
  ! called "PUT /api/task/status/t1"
  ! called "GET /api/custom-field/project/pid1"
}

@test "deploy: задачи диапазона тегов обрабатываются все, проект с полями запрашивается один раз" {
  EVENT_TYPE=deploy
  commit init 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): one' 2024-01-02T10:00:00
  commit '[GA-2] feature(api): two' 2024-01-02T11:00:00
  tag v1.1.0 2024-01-02T12:00:00
  task GA-1 t1 in-progress
  task GA-2 t2 in-progress
  version_field
  task_values t1 '[]'
  task_values t2 '[]'
  engine
  [ "$(grep -c '^PUT /api/task/status/' "$CALLS")" -eq 2 ]
  [ "$(grep -c '^GET /api/custom-field/project/pid1' "$CALLS")" -eq 1 ]
  [ "$(grep -c '^PUT /api/custom-field/value' "$CALLS")" -eq 2 ]
}

@test "deploy: не получена одна задача — остальные всё равно обрабатываются" {
  EVENT_TYPE=deploy
  commit init 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): one' 2024-01-02T10:00:00
  commit '[GA-2] feature(api): two' 2024-01-02T11:00:00
  tag v1.1.0 2024-01-02T12:00:00
  task GA-2 t2 in-progress
  version_field
  task_values t2 '[]'
  engine
  [ "$status" -eq 0 ]
  called "PUT /api/task/status/t2"
  [[ "$(report)" == *"An error occurred while getting information about the task GA-1"* ]]
}

@test "deploy: в репозитории нет тегов — строка в лог, код 0, запросов нет" {
  EVENT_TYPE=deploy
  commit init
  engine
  [ "$status" -eq 0 ]
  [[ "$output" == *"нет тегов"* ]]
  [ ! -s "$CALLS" ]
}

@test "событие не определено в схеме — строка в лог, код 0, запросов нет" {
  EVENT_TYPE=pr
  commit '[GA-1] feature(api): x'
  engine
  [ "$status" -eq 0 ]
  [[ "$output" == *"событие 'pr' не используется в схеме 'single'"* ]]
  [ ! -s "$CALLS" ]
}

@test "неизвестная схема — строка в лог, код 0, запросов нет" {
  KANEO_SCHEME=nope
  commit '[GA-1] feature(api): x'
  engine
  [ "$status" -eq 0 ]
  [[ "$output" == *"схема 'nope' не найдена"* ]]
  [ ! -s "$CALLS" ]
}

@test "имя схемы с управляющими символами в лог не попадает как есть" {
  KANEO_SCHEME=$'::error::x\nboom'
  engine
  [ "$status" -eq 0 ]
  [[ "$output" != *"::error::"* ]]
}

@test "нет номера задачи в коммите — строка в лог, код 0, запросов нет" {
  commit 'Update README'
  engine
  [ "$status" -eq 0 ]
  [[ "$output" == *"номера задач события нет"* ]]
  [ ! -s "$CALLS" ]
}

@test "данные задачи не получены — ERROR в отчёте, код 0, перенос не отправляется" {
  commit '[GA-1] feature(api): x'
  engine
  [ "$status" -eq 0 ]
  ! called "PUT /api/task/status/t1"
  [[ "$(report)" == *"An error occurred while getting information about the task GA-1"* ]]
}

@test "перенос не удался (ответ не совпал) — ERROR в отчёте, поля не трогаются" {
  commit '[GA-1] feature(api): x'
  task GA-1 t1 backlog
  rm "$RESP/ECHO_BODY"
  use_schemes '{"s":{"push":{"task_key":"commit","rules":[{"from":["backlog"],"to":"x","fields":{"F":"mark"}}]}}}'
  use_field_func mark 'kaneo_field_mark() { printf "v"; }'
  KANEO_SCHEME=s engine
  [ "$status" -eq 0 ]
  [[ "$(report)" == *"ERROR"* ]]
  ! called "GET /api/custom-field/project/pid1"
}

@test "статус колонки на кириллице сравнивается и отправляется без искажений" {
  commit '[GA-1] feature(api): x'
  task GA-1 t1 "в-работе"
  use_schemes '{"s":{"push":{"task_key":"commit","rules":[{"from":["в-работе"],"to":"готово"}]}}}'
  KANEO_SCHEME=s engine
  [ "$status" -eq 0 ]
  [ "$(status_bodies)" = '{"status":"готово"}' ]
}

@test "статус задачи на кириллице вне from — SKIPPED" {
  commit '[GA-1] feature(api): x'
  task GA-1 t1 "сделано"
  use_schemes '{"s":{"push":{"task_key":"commit","rules":[{"from":["в-работе"],"to":"готово"}]}}}'
  KANEO_SCHEME=s engine
  ! called "PUT /api/task/status/t1"
  [[ "$(report)" == *"SKIPPED"* ]]
}

@test "статус из ответа в лог не печатается" {
  commit '[GA-1] feature(api): x'
  task GA-1 t1 "::error::boom"
  engine
  [[ "$output" != *"boom"* ]]
}

# ---------- правила и источники номера задачи ----------

RULES='{"s":{"push":{"task_key":"commit","rules":[
  {"from":["backlog","hold"],"to":"first","fields":{"F1":"mark_a"}},
  {"from":["hold","paused"],"to":"second","fields":{"F2":"mark_b"}}]}}}'

array_setup() {
  commit '[GA-1] feature(api): x'
  use_schemes "$RULES"
  use_field_func mark_a 'kaneo_field_mark_a() { printf "a"; }'
  printf '%s\n' 'kaneo_field_mark_b() { printf "b"; }' > "$TMP/fields/mark_b.sh"
  project_fields '[{"id":"f1","name":"F1"},{"id":"f2","name":"F2"}]'
  task_values t1 '[]'
  export KANEO_SCHEME=s
}

@test "правила: срабатывает первое правило, подошедшее по from" {
  array_setup
  task GA-1 t1 hold
  engine
  [ "$(status_bodies)" = '{"status":"first"}' ]
}

@test "правила: второе правило срабатывает для своей колонки" {
  array_setup
  task GA-1 t1 paused
  engine
  [ "$(status_bodies)" = '{"status":"second"}' ]
}

@test "правила: поля берутся из сработавшего правила" {
  array_setup
  task GA-1 t1 paused
  engine
  [ "$(sent_values)" = "b" ]
  jq -e 'select(has("fieldId")) | .fieldId == "f2"' "$BODIES" > /dev/null
}

@test "правила: поля первого правила — не второго" {
  array_setup
  task GA-1 t1 backlog
  engine
  [ "$(sent_values)" = "a" ]
}

@test "правила: ни одно правило не подошло — SKIPPED с обоими целями" {
  array_setup
  task GA-1 t1 done
  engine
  ! called "PUT /api/task/status/t1"
  [[ "$(report)" == *"SKIPPED"* ]]
  [[ "$(report)" == *"first/second"* ]]
}

# ---------- поля ----------

# Схема с одним переходом push и заданными полями; fields — JSON-объект "поле": "функция".
fields_scheme() {
  use_schemes "{\"s\":{\"push\":{\"task_key\":\"commit\",\"rules\":[{\"from\":[\"backlog\"],\"to\":\"in-progress\",\"fields\":$1}]}}}"
  export KANEO_SCHEME=s
  commit '[GA-1] feature(api): x'
  task GA-1 t1 backlog
}

@test "поля: перенос задачи идёт раньше записи поля" {
  fields_scheme '{"F1":"mark"}'
  use_field_func mark 'kaneo_field_mark() { printf "v"; }'
  project_fields '[{"id":"f1","name":"F1"}]'
  task_values t1 '[]'
  engine
  [ "$(sed -n 2p "$CALLS")" = "PUT /api/task/status/t1" ]
  [ "$(sent_values)" = "v" ]
}

@test "поля: одна функция на два поля подключается один раз" {
  fields_scheme '{"F1":"mark","F2":"mark"}'
  use_field_func mark 'echo loaded >> "$LOADED"
kaneo_field_mark() { printf "v"; }'
  export LOADED="$TMP/loaded"
  project_fields '[{"id":"f1","name":"F1"},{"id":"f2","name":"F2"}]'
  task_values t1 '[]'
  engine
  [ "$(wc -l < "$LOADED")" -eq 1 ]
  [ "$(grep -c '^PUT /api/custom-field/value' "$CALLS")" -eq 2 ]
}

@test "поля: недопустимое имя функции — строка в лог, запись не отправляется, остальные поля идут" {
  fields_scheme '{"F1":"Bad-Name","F2":"mark"}'
  use_field_func mark 'kaneo_field_mark() { printf "v"; }'
  project_fields '[{"id":"f1","name":"F1"},{"id":"f2","name":"F2"}]'
  task_values t1 '[]'
  engine
  [ "$status" -eq 0 ]
  [[ "$output" == *"имя функции поля в схеме не по формату"* ]]
  [ "$(grep -c '^PUT /api/custom-field/value' "$CALLS")" -eq 1 ]
  jq -e 'select(has("fieldId")) | .fieldId == "f2"' "$BODIES" > /dev/null
}

@test "поля: имя с путём (../x) не ведёт к чужому файлу" {
  fields_scheme '{"F1":"../mark"}'
  use_field_func mark 'kaneo_field_mark() { printf "v"; }'
  project_fields '[{"id":"f1","name":"F1"}]'
  engine
  ! called "PUT /api/custom-field/value"
}

@test "поля: нет файла функции — строка в лог, запись не отправляется" {
  fields_scheme '{"F1":"missing"}'
  use_field_func other 'kaneo_field_other() { printf "v"; }'
  project_fields '[{"id":"f1","name":"F1"}]'
  engine
  [ "$status" -eq 0 ]
  [[ "$output" == *"нет файла функции поля fields/missing.sh"* ]]
  ! called "PUT /api/custom-field/value"
}

@test "поля: файл не определяет kaneo_field_<имя> — строка в лог" {
  fields_scheme '{"F1":"mark"}'
  use_field_func mark 'wrong_name() { printf "v"; }'
  engine
  [[ "$output" == *"не определяет kaneo_field_mark"* ]]
  ! called "PUT /api/custom-field/value"
}

@test "поля: в проекте нет такого поля — строка в лог, значение не читается" {
  fields_scheme '{"Absent":"mark"}'
  use_field_func mark 'kaneo_field_mark() { printf "v"; }'
  project_fields '[{"id":"f1","name":"F1"}]'
  engine
  [ "$status" -eq 0 ]
  [[ "$output" == *"нет поля Absent"* ]]
  ! called "GET /api/custom-field/task/t1"
  ! called "PUT /api/custom-field/value"
}

@test "поля: определения проекта не получены — ERROR, запись не отправляется" {
  fields_scheme '{"F1":"mark"}'
  use_field_func mark 'kaneo_field_mark() { printf "v"; }'
  engine
  [ "$status" -eq 0 ]
  [[ "$(report)" == *"An error occurred when updating the field 'F1'"* ]]
  ! called "PUT /api/custom-field/value"
}

@test "поля: значения не прочитались — ERROR, функция не вызывается, запись не отправляется" {
  fields_scheme '{"F1":"mark"}'
  use_field_func mark 'echo called >> "$LOADED"
kaneo_field_mark() { echo called >> "$LOADED"; printf "v"; }'
  export LOADED="$TMP/loaded"
  project_fields '[{"id":"f1","name":"F1"}]'
  engine
  [ "$status" -eq 0 ]
  [[ "$(report)" == *"ERROR"* ]]
  [ "$(wc -l < "$LOADED")" -eq 1 ]
  ! called "PUT /api/custom-field/value"
}

@test "поля: функция вернула ошибку — поле пропущено, следующее записывается" {
  fields_scheme '{"F1":"bad","F2":"mark"}'
  use_field_func bad 'kaneo_field_bad() { echo "boom" >&2; return 3; }'
  printf '%s\n' 'kaneo_field_mark() { printf "v"; }' > "$TMP/fields/mark.sh"
  project_fields '[{"id":"f1","name":"F1"},{"id":"f2","name":"F2"}]'
  task_values t1 '[]'
  engine
  [ "$status" -eq 0 ]
  [ "$(sent_values)" = "v" ]
  [[ "$(report)" == *"An error occurred when updating the field 'F1'"* ]]
}

@test "поля: значение не изменилось — запись не отправляется" {
  fields_scheme '{"F1":"keep"}'
  use_field_func keep 'kaneo_field_keep() { printf "%s" "$KANEO_FIELD_VALUE"; }'
  project_fields '[{"id":"f1","name":"F1"}]'
  task_values t1 '[{"fieldId":"f1","value":"same"}]'
  engine
  [ "$status" -eq 0 ]
  ! called "PUT /api/custom-field/value"
}

@test "поля: значение null считается пустым, функция получает пустую строку" {
  fields_scheme '{"F1":"show"}'
  use_field_func show 'kaneo_field_show() { printf "[%s]" "$KANEO_FIELD_VALUE"; }'
  project_fields '[{"id":"f1","name":"F1"}]'
  task_values t1 '[{"fieldId":"f1","value":null}]'
  engine
  [ "$(sent_values)" = "[]" ]
}

@test "поля: функция получает контекст через env и ни одного аргумента" {
  fields_scheme '{"F1":"ctx"}'
  use_field_func ctx 'kaneo_field_ctx() { printf "%s|%s|%s|%s|%s" "$KANEO_FIELD_VALUE" "$KANEO_TASK_KEY" "$KANEO_TASK_STATUS" "$KANEO_EVENT" "$#"; }'
  project_fields '[{"id":"f1","name":"F1"}]'
  task_values t1 '[{"fieldId":"f1","value":"old"}]'
  engine
  [ "$(sent_values)" = "old|GA-1|backlog|push|0" ]
}

@test "поля: контекст функции не утекает в окружение движка" {
  fields_scheme '{"F1":"ctx"}'
  use_field_func ctx 'kaneo_field_ctx() { printf "v"; }'
  project_fields '[{"id":"f1","name":"F1"}]'
  task_values t1 '[]'
  kaneo_run "kaneo_run; echo \"[\${KANEO_FIELD_VALUE-unset}]\""
  [[ "$output" == *"[unset]"* ]]
}

@test "поля: значение с кавычкой и переводом строки уходит в теле JSON без искажений" {
  fields_scheme '{"F1":"odd"}'
  use_field_func odd 'kaneo_field_odd() { printf "a\"b\nc"; }'
  project_fields '[{"id":"f1","name":"F1"}]'
  task_values t1 '[]'
  engine
  [ "$(sent_values)" = $'a"b\nc' ]
}

@test "task_key tags на push: задачи берутся из диапазона тегов, а не из коммита" {
  use_schemes '{"s":{"push":{"task_key":"tags","rules":[{"from":["backlog"],"to":"in-progress"}]}}}'
  KANEO_SCHEME=s
  release_with_ga1
  commit '[GA-9] feature(api): head' 2024-01-03T10:00:00
  task GA-1 t1 backlog
  engine
  called "GET /api/task/by-ticket-id/GA-1"
  ! called "GET /api/task/by-ticket-id/GA-9"
}

@test "task_key commit на deploy: номер из последнего коммита, теги не нужны" {
  use_schemes '{"s":{"deploy":{"task_key":"commit","rules":[{"from":["backlog"],"to":"done"}]}}}'
  KANEO_SCHEME=s EVENT_TYPE=deploy
  commit '[GA-3] feature(api): x'
  task GA-3 t3 backlog
  engine
  [ "$(status_bodies)" = '{"status":"done"}' ]
}

@test "task_key branch на pr в одной схеме и commit на push в другом событии: источник свой у каждого события" {
  use_schemes '{"s":{"push":{"task_key":"commit","rules":[{"from":["backlog"],"to":"a"}]},"pr":{"task_key":"branch","rules":[{"from":["backlog"],"to":"b"}]}}}'
  KANEO_SCHEME=s EVENT_TYPE=pr
  commit '[GA-1] feature(api): x'
  task GA-5 t5 backlog
  HEAD_REF=GA-5-feature engine
  [ "$(status_bodies)" = '{"status":"b"}' ]
}

@test "task_key неизвестного источника: номера нет, строка в лог, запросов нет" {
  use_schemes '{"s":{"push":{"task_key":"bogus","rules":[{"from":["backlog"],"to":"a"}]}}}'
  KANEO_SCHEME=s
  commit '[GA-1] feature(api): x'
  engine
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}


#!/usr/bin/env bats
# Тесты scripts/kaneo_flow.sh: kaneo_prepare и переходы push/pr/merge. curl подменяется
# заглушкой с ответами по маршруту (tests/kaneo_helpers.bash), шаги идут под bash -e.

setup() {
  load helpers
  load kaneo_helpers
  ROOT="$(repo_root)"
  TMP="$(mktemp -d)"
  kaneo_stub_setup
  export KANEO_STATUS_IN_PROGRESS=in-progress KANEO_STATUS_REVIEW=in-review
  export KANEO_STATUS_MERGED=merged
  export PROJECT_TYPE=multi_branch
  export KANEO_TASK_KEY=GA-25 KANEO_TASK_ID=tid1 KANEO_PROJECT_ID=pid1 KANEO_WORKSPACE_ID=wid1
}

teardown() {
  rm -rf "$TMP"
}

# Подготовка к шагам переходов: текущий статус задачи и ответ на PUT status.
move_ready() {
  export CURRENT_STATUS="$1"
  kaneo_respond "PUT /api/task/status/tid1" "$(kaneo_task_json "$2")"
}

report() {
  cat "$WORK/message.tmpl"
}

# ---------- kaneo_prepare ----------

@test "prepare: номер из ветки -> данные задачи в GITHUB_OUTPUT" {
  export EVENT_TYPE=push GITHUB_REF_NAME=GA-25-new-thing
  kaneo_respond "GET /api/task/by-ticket-id/GA-25" "$(kaneo_task_json todo)"
  kaneo_run kaneo_prepare
  [ "$status" -eq 0 ]
  [ "$(output_value task_key)" = "GA-25" ]
  [ "$(output_value task_id)" = "tid1" ]
  [ "$(output_value project_id)" = "pid1" ]
  [ "$(output_value workspace_id)" = "wid1" ]
  [ "$(output_value current_status)" = "todo" ]
  [[ "$output" == *"task_key GA-25"* ]]
}

@test "prepare: pr берёт номер из HEAD_REF" {
  export EVENT_TYPE=pr HEAD_REF=GA-30_feature GITHUB_REF_NAME=123/merge
  kaneo_respond "GET /api/task/by-ticket-id/GA-30" "$(kaneo_task_json in-progress)"
  kaneo_run kaneo_prepare
  [ "$(output_value task_key)" = "GA-30" ]
  grep -qx "GET /api/task/by-ticket-id/GA-30" "$CALLS"
}

@test "prepare: нет номера в ветке — строка в лог, ни одного запроса, вывода нет" {
  export EVENT_TYPE=push GITHUB_REF_NAME=master
  kaneo_run kaneo_prepare
  [ "$status" -eq 0 ]
  [[ "$output" == *"нет номера задачи"* ]]
  [ ! -s "$CALLS" ]
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "prepare: Kaneo недоступен — шаги пропущены, код 0, вывода нет" {
  export EVENT_TYPE=push GITHUB_REF_NAME=GA-25-x
  kaneo_run kaneo_prepare
  [ "$status" -eq 0 ]
  [[ "$output" == *"не удалось получить данные задачи GA-25"* ]]
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "prepare: ответ не JSON — шаги пропущены" {
  export EVENT_TYPE=push GITHUB_REF_NAME=GA-25-x
  kaneo_respond "GET /api/task/by-ticket-id/GA-25" '<html>502</html>'
  kaneo_run kaneo_prepare
  [ "$status" -eq 0 ]
  [[ "$output" == *"не удалось получить данные"* ]]
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "prepare: небезопасный id в ответе не попадает ни в вывод, ни в лог" {
  export EVENT_TYPE=push GITHUB_REF_NAME=GA-25-x
  kaneo_respond "GET /api/task/by-ticket-id/GA-25" \
    '{"id":"t1","projectId":"p $(id)","workspaceId":"w1","status":"todo"}'
  kaneo_run kaneo_prepare
  [ "$status" -eq 0 ]
  [ ! -s "$GITHUB_OUTPUT" ]
  [[ "$output" != *'$(id)'* ]]
}

@test "prepare: статус с переводом строки не может дописать строку в GITHUB_OUTPUT" {
  export EVENT_TYPE=push GITHUB_REF_NAME=GA-25-x
  kaneo_respond "GET /api/task/by-ticket-id/GA-25" \
    '{"id":"t1","projectId":"p1","workspaceId":"w1","status":"todo\ninjected=1"}'
  kaneo_run kaneo_prepare
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "prepare: в ответе нет workspaceId — шаги пропущены" {
  export EVENT_TYPE=push GITHUB_REF_NAME=GA-25-x
  kaneo_respond "GET /api/task/by-ticket-id/GA-25" '{"id":"t1","projectId":"p1","status":"todo"}'
  kaneo_run kaneo_prepare
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "prepare: single_branch берёт номер из последнего коммита" {
  export EVENT_TYPE=push PROJECT_TYPE=single_branch GITHUB_REF_NAME=master
  git -C "$WORK" init -q
  git -C "$WORK" -c user.email=t@t -c user.name=t commit -q --allow-empty -m '[GA-77] feature(api): x'
  kaneo_respond "GET /api/task/by-ticket-id/GA-77" "$(kaneo_task_json todo)"
  kaneo_run kaneo_prepare
  [ "$(output_value task_key)" = "GA-77" ]
}

# ---------- kaneo_require_statuses ----------

@test "require_statuses: все заданы — код 0 и тишина" {
  kaneo_run "kaneo_require_statuses pr a b"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "require_statuses: один пустой — код 1 и строка в лог" {
  kaneo_run "kaneo_require_statuses pr a ''"
  [ "$status" -eq 1 ]
  [[ "$output" == *"для события pr не заданы нужные kaneo_status_*"* ]]
}

# ---------- push ----------

@test "push: задача в другой колонке -> PUT status in-progress и SUCCESS в отчёте" {
  move_ready todo in-progress
  kaneo_run kaneo_on_push
  [ "$status" -eq 0 ]
  grep -qx "PUT /api/task/status/tid1" "$CALLS"
  jq -e '. == {status: "in-progress"}' "$BODIES" >/dev/null
  [[ "$(report)" == *"SUCCESS"* ]]
  [[ "$(report)" == *"The task GA-25 has been successfully moved to the 'IN_PROGRESS' column"* ]]
  [[ "$(report)" == *"/dashboard/workspace/wid1/project/pid1/task/tid1"* ]]
}

@test "push: задача уже в in-progress — запроса на перенос нет, в отчёте SKIPPED" {
  move_ready in-progress in-progress
  kaneo_run kaneo_on_push
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  [[ "$(report)" == *"SKIPPED"* ]]
}

@test "push multi_branch: задача в review не откатывается в in-progress" {
  move_ready in-review in-progress
  kaneo_run kaneo_on_push
  [ ! -s "$CALLS" ]
  [[ "$(report)" == *"SKIPPED"* ]]
}

@test "push single_branch: статус review ничем не особенный — задача переносится" {
  export PROJECT_TYPE=single_branch
  move_ready in-review in-progress
  kaneo_run kaneo_on_push
  grep -qx "PUT /api/task/status/tid1" "$CALLS"
}

@test "push multi_branch без kaneo_status_review: перенос из любой другой колонки" {
  export KANEO_STATUS_REVIEW=''
  move_ready todo in-progress
  kaneo_run kaneo_on_push
  grep -qx "PUT /api/task/status/tid1" "$CALLS"
}

@test "push: Kaneo не принял перенос — ERROR в отчёте, шаг не падает" {
  export CURRENT_STATUS=todo
  kaneo_run kaneo_on_push
  [ "$status" -eq 0 ]
  [[ "$(report)" == *"ERROR"* ]]
  [[ "$(report)" == *"An error occurred when moving the task GA-25 to the 'IN_PROGRESS' column"* ]]
}

@test "push: в ответе другой статус — это ошибка, не успех" {
  move_ready todo todo
  kaneo_run kaneo_on_push
  [[ "$(report)" == *"ERROR"* ]]
  [[ "$(report)" != *"SUCCESS"* ]]
}

@test "push: не-JSON ответ на перенос — ERROR, шаг не падает под bash -e" {
  export CURRENT_STATUS=todo
  kaneo_respond "PUT /api/task/status/tid1" 'oops'
  kaneo_run kaneo_on_push
  [ "$status" -eq 0 ]
  [[ "$(report)" == *"ERROR"* ]]
}

@test "push: пустой kaneo_status_in_progress — строка в лог, запросов нет" {
  export KANEO_STATUS_IN_PROGRESS='' CURRENT_STATUS=todo
  kaneo_run kaneo_on_push
  [ "$status" -eq 0 ]
  [[ "$output" == *"не заданы нужные kaneo_status_*"* ]]
  [ ! -s "$CALLS" ]
  [ ! -e "$WORK/message.tmpl" ]
}

# ---------- pr ----------

@test "pr: из in-progress -> in-review" {
  move_ready in-progress in-review
  kaneo_run kaneo_on_pr
  jq -e '. == {status: "in-review"}' "$BODIES" >/dev/null
  [[ "$(report)" == *"moved to the 'REVIEW' column"* ]]
}

@test "pr: задача не в in-progress — перенос не нужен" {
  move_ready todo in-review
  kaneo_run kaneo_on_pr
  [ ! -s "$CALLS" ]
  [[ "$(report)" == *"SKIPPED"* ]]
}

@test "pr: задача уже в in-review не переносится повторно" {
  move_ready in-review in-review
  kaneo_run kaneo_on_pr
  [ ! -s "$CALLS" ]
}

@test "pr: пустой kaneo_status_review — строка в лог, запросов нет" {
  export KANEO_STATUS_REVIEW='' CURRENT_STATUS=in-progress
  kaneo_run kaneo_on_pr
  [ "$status" -eq 0 ]
  [[ "$output" == *"для события pr не заданы"* ]]
  [ ! -s "$CALLS" ]
}

# ---------- merge ----------

@test "merge: из in-review -> merged" {
  move_ready in-review merged
  kaneo_run kaneo_on_merge
  jq -e '. == {status: "merged"}' "$BODIES" >/dev/null
  [[ "$(report)" == *"moved to the 'MERGED' column"* ]]
}

@test "merge: задача не в in-review — перенос не нужен" {
  move_ready in-progress merged
  kaneo_run kaneo_on_merge
  [ ! -s "$CALLS" ]
  [[ "$(report)" == *"SKIPPED"* ]]
}

@test "merge: пустой kaneo_status_merged — строка в лог, запросов нет" {
  export KANEO_STATUS_MERGED='' CURRENT_STATUS=in-review
  kaneo_run kaneo_on_merge
  [[ "$output" == *"для события merge не заданы"* ]]
  [ ! -s "$CALLS" ]
}

@test "два перехода подряд пишут один отчёт с разделителем" {
  move_ready in-review merged
  kaneo_run "kaneo_on_merge; kaneo_on_merge"
  [ "$(grep -c -- '----------' "$WORK/message.tmpl")" -eq 1 ]
}

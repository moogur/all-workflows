#!/usr/bin/env bats
# Тесты функций отчёта (message.tmpl) в scripts/kaneo_messages.sh.
# Проверяется содержимое файла-отчёта.

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/scripts/kaneo_requests.sh"
  MSG="$ROOT/scripts/kaneo_messages.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# Выполняет код после source скриптов с переопределённым путём отчёта и текущей задачей,
# затем выводит содержимое файла-отчёта в $output.
msg() {
  run bash -c "source '$LIB'; source '$MSG'; private_file_path='$TMP/m'; private_url='https://kaneo.example'; \
    private_task_id=tid1; private_project_id=pid1; private_workspace_id=wid1; $*; cat '$TMP/m'"
}

# ---------- save_message_in_file ----------

@test "move success: заголовок SUCCESS и сообщение об успехе" {
  msg "save_message_in_file DEPLOY GA-42 'raw' true"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUCCESS"* ]]
  [[ "$output" == *"The task GA-42 has been successfully moved to the 'DEPLOY' column"* ]]
  [[ "$output" != *"Raw error"* ]]
}

@test "move failure: заголовок ERROR, сообщение и raw" {
  msg "save_message_in_file REVIEW GA-13 'boom' false"
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"An error occurred when moving the task GA-13 to the 'REVIEW' column"* ]]
  [[ "$output" == *"Raw error - 'boom'"* ]]
}

@test "move: любое значение кроме точного 'true' трактуется как ошибка" {
  msg "save_message_in_file COL GA-1 'r' True"
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" != *"SUCCESS"* ]]
}

@test "failure: многословный raw печатается целиком" {
  msg "save_message_in_file REVIEW GA-7 'first second third' false"
  [[ "$output" == *"Raw error - 'first second third'"* ]]
}

@test "failure: пустой raw (запрос не удался) не даёт строки Raw error" {
  msg "save_message_in_file REVIEW GA-7 '' false"
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" != *"Raw error"* ]]
}

@test "ссылка на задачу — полный путь по id пространства, проекта и задачи" {
  msg "save_message_in_file DEPLOY GA-42 'raw' true"
  [[ "$output" == *"Link to the task - https://kaneo.example/dashboard/workspace/wid1/project/pid1/task/tid1"* ]]
}

@test "без id задачи ссылки в отчёте нет" {
  msg "private_task_id=''; save_message_in_file DEPLOY GA-42 'raw' false"
  [[ "$output" != *"Link to the task"* ]]
}

@test "два сообщения подряд разделяются линией" {
  msg "save_message_in_file A GA-1 'r' true; save_message_in_file B GA-2 'r' true"
  [[ "$output" == *"----------"* ]]
}

@test "первое сообщение разделителя не содержит" {
  msg "save_message_in_file A GA-1 'r' true"
  [[ "$output" != *"----------"* ]]
}

# ---------- очистка raw (недоверенный ответ API) ----------

@test "raw: перевод строки и workflow-команда не попадают в отчёт отдельной строкой" {
  msg "save_message_in_file A GA-1 \$'x\n::add-mask::secret' false"
  [[ "$output" != *$'\n::'* ]]
  [[ "$output" == *"Raw error - 'x::add-mask::secret'"* ]]
}

@test "raw: управляющие символы, \$, обратные кавычки и скобки удаляются" {
  msg "save_message_in_file A GA-1 \$'a\x1b[0m\`id\`\$(id)b' false"
  [[ "$output" == *"Raw error - 'a0mididb'"* ]]
}

@test "raw: длина ограничена 300 символами" {
  local long
  long=$(printf 'a%.0s' $(seq 1 400))
  msg "save_message_in_file A GA-1 '$long' false"
  [[ "$output" == *"Raw error - '$(printf 'a%.0s' $(seq 1 300))'"* ]]
  [[ "$output" != *"$(printf 'a%.0s' $(seq 1 301))"* ]]
}

# ---------- остальные сообщения ----------

@test "add version success" {
  msg "save_message_in_file_for_add_app_version GA-9 'r' true"
  [[ "$output" == *"SUCCESS"* ]]
  [[ "$output" == *"For the task GA-9, a version has been added"* ]]
}

@test "add version failure" {
  msg "save_message_in_file_for_add_app_version GA-9 'oops' false"
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"An error occurred when adding a version to the task GA-9"* ]]
  [[ "$output" == *"Raw error - 'oops'"* ]]
}

@test "get task error: сообщение об ошибке получения данных" {
  msg "save_message_in_file_for_get_task_error GA-4"
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"An error occurred while getting information about the task GA-4"* ]]
}

@test "skip: заголовок SKIPPED без SUCCESS/ERROR и пояснение" {
  msg "save_skip_message_in_file REVIEW GA-3"
  [[ "$output" == *"SKIPPED"* ]]
  [[ "$output" == *"The task GA-3 was not moved to the 'REVIEW' column"* ]]
  [[ "$output" != *"ERROR"* ]]
  [[ "$output" != *"SUCCESS"* ]]
}

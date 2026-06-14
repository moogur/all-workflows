#!/usr/bin/env bats
# Тесты функций формирования отчёта (message.tmpl) в scripts/kanboard_requests.sh.
# Проверяется содержимое файла-отчёта. Скрипт не модифицируется.

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/scripts/kanboard_requests.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# Выполняет код после source библиотеки с переопределённым путём отчёта,
# затем выводит содержимое файла-отчёта в $output.
msg() {
  run bash -c "source '$LIB'; private_file_path='$TMP/m'; private_url='https://kb.example'; $*; cat '$TMP/m'"
}

# ---------- save_message_in_file ----------

@test "move success: заголовок SUCCESS и сообщение об успехе" {
  msg "save_message_in_file 'DEPLOY' 42 'raw' true"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUCCESS"* ]]
  [[ "$output" == *"The task with id 42 has been successfully moved to the 'DEPLOY' column"* ]]
  [[ "$output" != *"Raw error"* ]]
}

@test "move success: многословный raw НЕ печатает 'Raw error' (аргументы закавычены)" {
  # Регрессия на баг word-splitting: ответ Kanboard (JSON с пробелами) при success
  # больше не сдвигает result и не вызывает ложную 'Raw error'.
  msg "save_message_in_file 'DEPLOY' 42 'two words in raw' true"
  [[ "$output" != *"Raw error"* ]]
}

@test "move false: многословный raw печатается целиком" {
  # При ошибке raw-сообщение выводится полностью, а не только первое слово.
  msg "save_message_in_file 'REVIEW' 7 'first second third' false"
  [[ "$output" == *"Raw error - 'first second third'"* ]]
}

@test "move success: ссылка на задачу с task_id" {
  msg "save_message_in_file 'DEPLOY' 42 'raw' true"
  [[ "$output" == *"Link to the task - https://kb.example/?controller=TaskViewController&action=show&task_id=42"* ]]
}

@test "move false: заголовок ERROR, сообщение об ошибке и raw" {
  msg "save_message_in_file 'REVIEW' 13 'boom' false"
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"An error occurred when moving a task with id 13 to the 'REVIEW' column"* ]]
  [[ "$output" == *"Raw error - 'boom'"* ]]
}

@test "move unknown result: сообщение о неизвестной ошибке" {
  msg "save_message_in_file 'COL' 5 'r' null"
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"An unknown error occurred when moving the task from id 5 to the 'COL' column"* ]]
}

@test "move: result 'True' (не точное 'true') трактуется как неизвестный" {
  msg "save_message_in_file 'COL' 1 'r' True"
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"An unknown error occurred"* ]]
}

@test "move: task_id=-1 подставляется из private_task_id" {
  msg "private_task_id=77; save_message_in_file 'COL' -1 'r' true"
  [[ "$output" == *"id 77"* ]]
  [[ "$output" == *"task_id=77"* ]]
}

@test "два сообщения подряд разделяются линией" {
  msg "save_message_in_file 'A' 1 'r' true; save_message_in_file 'B' 2 'r' true"
  [[ "$output" == *"----------"* ]]
}

# ---------- save_message_in_file_for_add_app_version ----------

@test "add version success" {
  msg "save_message_in_file_for_add_app_version 9 'r' true"
  [[ "$output" == *"SUCCESS"* ]]
  [[ "$output" == *"For a task with id 9, a version has been added"* ]]
  [[ "$output" == *"task_id=9"* ]]
}

@test "add version false" {
  msg "save_message_in_file_for_add_app_version 9 'oops' false"
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"An error occurred when adding a version to a task with id 9"* ]]
  [[ "$output" == *"Raw error - 'oops'"* ]]
}

@test "add version unknown" {
  msg "save_message_in_file_for_add_app_version 9 'r' weird"
  [[ "$output" == *"An unknown error occurred when adding a version to a task with id 9"* ]]
}

# ---------- save_message_in_file_for_deploy_get_task_info_error ----------

@test "deploy get-info error: сообщение и raw" {
  msg "save_message_in_file_for_deploy_get_task_info_error 4 'info-fail'"
  [[ "$output" == *"An error occurred while getting information about a task with id 4"* ]]
  [[ "$output" == *"Raw error - 'info-fail'"* ]]
  [[ "$output" == *"task_id=4"* ]]
}

# ---------- вспомогательные функции ----------

@test "save_message_header_in_file: true -> SUCCESS" {
  msg "save_message_header_in_file true"
  [[ "$output" == *"SUCCESS"* ]]
}

@test "save_message_header_in_file: иначе -> ERROR" {
  msg "save_message_header_in_file false"
  [[ "$output" == *"ERROR"* ]]
}

@test "save_task_link_in_file: формат ссылки" {
  msg "save_task_link_in_file 5"
  [[ "$output" == *"Link to the task - https://kb.example/?controller=TaskViewController&action=show&task_id=5"* ]]
}

@test "save_raw_message_in_file: при result=true ничего не пишет" {
  msg "save_raw_message_in_file 'secret' true"
  [[ "$output" != *"Raw error"* ]]
}

@test "save_raw_message_in_file: при result!=true пишет raw" {
  msg "save_raw_message_in_file 'secret' false"
  [[ "$output" == *"Raw error - 'secret'"* ]]
}

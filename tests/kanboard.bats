#!/usr/bin/env bats
# Тесты генераторов JSON-RPC payload в scripts/kanboard_requests.sh.
# Проверяется только формирование тела запроса (чистые функции), без сетевых вызовов.
# Скрипт не модифицируется.

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/scripts/kanboard_requests.sh"
}

# Выполняет код в подоболочке после source библиотеки; вывод — в $output.
sh() {
  run bash -c "source '$LIB'; $*"
}

# ---------- getTask ----------

@test "getTask: валидный JSON, метод и task_id" {
  sh "generate_post_data_for_get_info_task 42"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.jsonrpc == "2.0" and .id == 1 and .method == "getTask" and .params.task_id == 42' >/dev/null
}

@test "getTask: task_id выводится как число, не строка" {
  sh "generate_post_data_for_get_info_task 42"
  echo "$output" | jq -e '(.params.task_id | type) == "number"' >/dev/null
}

# ---------- moveTaskPosition ----------

@test "moveTaskPosition: валидный JSON со всеми полями" {
  sh "generate_post_data_for_move_task 5 42 100 1 2"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.method == "moveTaskPosition" and .params.column_id == 5 and .params.task_id == 42 and .params.position == 100 and .params.project_id == 1 and .params.swimlane_id == 2' >/dev/null
}

@test "moveTaskPosition: position по умолчанию = 100" {
  sh "generate_post_data_for_move_task 5 42 '' 1 2"
  echo "$output" | jq -e '.params.position == 100' >/dev/null
}

@test "moveTaskPosition: пустой task_id берётся из private_task_id" {
  sh "private_task_id=99; generate_post_data_for_move_task 5 '' 100 1 2"
  echo "$output" | jq -e '.params.task_id == 99' >/dev/null
}

@test "moveTaskPosition: пустой project_id берётся из private_project_id" {
  sh "private_project_id=7; generate_post_data_for_move_task 5 42 100 '' 2"
  echo "$output" | jq -e '.params.project_id == 7' >/dev/null
}

@test "moveTaskPosition: пустой swimlane_id берётся из private_swimlane_id" {
  sh "private_swimlane_id=3; generate_post_data_for_move_task 5 42 100 1 ''"
  echo "$output" | jq -e '.params.swimlane_id == 3' >/dev/null
}

@test "moveTaskPosition: все необязательные поля по умолчанию" {
  sh "private_task_id=99; private_project_id=7; private_swimlane_id=3; generate_post_data_for_move_task 5"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.params.column_id == 5 and .params.task_id == 99 and .params.position == 100 and .params.project_id == 7 and .params.swimlane_id == 3' >/dev/null
}

# ---------- getTaskMetadataByName ----------

@test "getTaskMetadataByName: запрашивает App_version" {
  sh "generate_post_data_for_get_metadata_task 7"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.method == "getTaskMetadataByName" and .params.name == "App_version" and .params.task_id == 7' >/dev/null
}

# ---------- saveTaskMetadata ----------

@test "saveTaskMetadata: проставляет App_version (строка)" {
  sh "generate_post_data_for_update_task_app_version 7 1.2.3"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.method == "saveTaskMetadata" and .params.task_id == 7 and .params.values.App_version == "1.2.3"' >/dev/null
}

@test "saveTaskMetadata: App_version выводится как строка" {
  sh "generate_post_data_for_update_task_app_version 7 2024.01"
  echo "$output" | jq -e '(.params.values.App_version | type) == "string"' >/dev/null
}

@test "saveTaskMetadata: версия из нескольких частей через запятую" {
  sh "generate_post_data_for_update_task_app_version 7 '1.0.0, 1.1.0'"
  echo "$output" | jq -e '.params.values.App_version == "1.0.0, 1.1.0"' >/dev/null
}

# ---------- характеристические особенности ----------
# Генераторы не экранируют ввод: спецсимволы в значениях ломают JSON.
# Тест фиксирует это поведение (см. docs/modernization.md).

@test "(особенность) кавычка в App_version ломает JSON" {
  sh 'generate_post_data_for_update_task_app_version 7 "a\"b"'
  # payload получается невалидным — jq не может его разобрать
  run bash -c "echo '$output' | jq -e . >/dev/null 2>&1"
  [ "$status" -ne 0 ]
}

#!/usr/bin/env bats
# Тесты генераторов тела запроса и проверки id в scripts/kaneo_requests.sh.
# Проверяется только формирование тела запроса (чистые функции), без сетевых вызовов.

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/scripts/kaneo_requests.sh"
}

# Выполняет код в подоболочке после source библиотеки; вывод — в $output.
sh() {
  run bash -c "source '$LIB'; $*"
}

# ---------- перенос задачи ----------

@test "move: тело {status} со slug колонки" {
  sh "generate_post_data_for_move_task in-progress"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == {status: "in-progress"}' >/dev/null
}

@test "move: кавычка в статусе экранируется, JSON остаётся валидным" {
  sh 'generate_post_data_for_move_task "a\"b"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "a\"b"' >/dev/null
}

@test "move: пустой статус отвергается, stdout пуст" {
  run bash -c "source '$LIB'; generate_post_data_for_move_task '' 2>/dev/null"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# ---------- значение пользовательского поля ----------

@test "set field: тело с taskId, fieldId и значением-строкой" {
  sh "generate_post_data_for_set_field_value tid1 fid1 '1.0.0, 1.1.0'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == {taskId: "tid1", fieldId: "fid1", value: "1.0.0, 1.1.0"}' >/dev/null
}

@test "set field: значение, похожее на число, остаётся строкой" {
  sh "generate_post_data_for_set_field_value tid1 fid1 2024.01"
  echo "$output" | jq -e '(.value | type) == "string"' >/dev/null
}

@test "set field: кавычка в значении экранируется" {
  sh 'generate_post_data_for_set_field_value tid1 fid1 "a\"b"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.value == "a\"b"' >/dev/null
}

@test "set field: небезопасный id задачи или поля отвергается, stdout пуст" {
  run bash -c "source '$LIB'; generate_post_data_for_set_field_value '1;id' fid1 v 2>/dev/null"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  run bash -c "source '$LIB'; generate_post_data_for_set_field_value tid1 'a b' v 2>/dev/null"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "set field: пустой id отвергается" {
  sh "generate_post_data_for_set_field_value '' fid1 v"
  [ "$status" -ne 0 ]
}

# ---------- require_kaneo_id ----------

@test "require_kaneo_id: сообщение не содержит самого значения" {
  run bash -c "source '$LIB'; require_kaneo_id task_id 'secret-\$(x) y' 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"task_id is not a valid id"* ]]
  [[ "$output" != *"secret"* ]]
}

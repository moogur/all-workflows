#!/usr/bin/env bats
# Тесты отказов генераторов тела запроса и проверки id в scripts/kaneo/requests.sh
# (пустой статус, небезопасные id), без сетевых вызовов.

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/scripts/kaneo/requests.sh"
}

# Выполняет код в подоболочке после source библиотеки; вывод — в $output.
sh() {
  run bash -c "source '$LIB'; $*"
}

# ---------- перенос задачи ----------

@test "move: пустой статус отвергается, stdout пуст" {
  run bash -c "source '$LIB'; generate_post_data_for_move_task '' 2>/dev/null"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# ---------- значение пользовательского поля ----------

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

#!/usr/bin/env bats
# Guard-тест scripts/kaneo/schemes.json: структура схем и наличие функций полей.
# Опечатка в схеме иначе вскрылась бы только на реальном прогоне у потребителя.

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCHEMES="$ROOT/scripts/kaneo/schemes.json"
  LIB="$ROOT/lib/kaneo.sh"
}

# Правила всех событий всех схем, по одному JSON в строке.
rules() {
  jq -c '.[] | .[] | .rules[]' "$SCHEMES"
}

@test "schemes.json: валидный JSON-объект с непустым набором схем" {
  jq -e 'type == "object" and length > 0' "$SCHEMES" > /dev/null
}

@test "schemes.json: есть схемы single, single_ready, single_hold, push_only и multi" {
  jq -e 'has("single") and has("single_ready") and has("single_hold") and has("push_only") and has("multi")' "$SCHEMES" > /dev/null
}

@test "schemes.json: схема — объект с непустым набором событий, других ключей (вроде task_key) нет" {
  jq -e 'all(.[]; type == "object" and length > 0)' "$SCHEMES" > /dev/null
}

@test "schemes.json: события — только push, pr, merge, deploy" {
  jq -e 'all(.[] | keys[]; IN("push", "pr", "merge", "deploy"))' "$SCHEMES" > /dev/null
}

@test "schemes.json: у каждого события task_key — commit, branch или tags" {
  jq -e 'all(.[] | .[]; .task_key == "commit" or .task_key == "branch" or .task_key == "tags")' "$SCHEMES" > /dev/null
}

@test "schemes.json: у каждого события rules — непустой массив объектов" {
  jq -e 'all(.[] | .[]; (.rules | type == "array" and length > 0 and all(.[]; type == "object")))' "$SCHEMES" > /dev/null
}

@test "schemes.json: у каждого правила непустой from из строк и непустой to" {
  local rule
  while IFS= read -r rule; do
    jq -e '(.from | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
      and (.to | type == "string" and length > 0)' <<< "$rule" > /dev/null
  done < <(rules)
}

@test "schemes.json: fields — объект из непустых имён полей и имён функций" {
  local rule
  while IFS= read -r rule; do
    jq -e '(.fields // {}) | type == "object" and all(to_entries[]; (.key | length > 0) and (.value | type == "string"))' <<< "$rule" > /dev/null
  done < <(rules)
}

@test "schemes.json: каждая функция поля — валидное имя, файл fields/<имя>.sh определяет kaneo_field_<имя>" {
  local func
  while IFS= read -r func; do
    run bash -c "source '$LIB'; kaneo_func_name_valid '$func'"
    [ "$status" -eq 0 ]
    [ -f "$ROOT/scripts/kaneo/fields/$func.sh" ]
    run bash -c "source '$ROOT/scripts/kaneo/fields/$func.sh'; declare -F kaneo_field_$func"
    [ "$status" -eq 0 ]
  done < <(rules | jq -r '(.fields // {})[]')
}

@test "fields/: каждый файл функции называется валидным именем и определяет свою функцию" {
  local file name
  for file in "$ROOT"/scripts/kaneo/fields/*.sh; do
    name=$(basename "$file" .sh)
    run bash -c "source '$LIB'; kaneo_func_name_valid '$name'"
    [ "$status" -eq 0 ]
    run bash -c "source '$file'; declare -F kaneo_field_$name"
    [ "$status" -eq 0 ]
  done
}

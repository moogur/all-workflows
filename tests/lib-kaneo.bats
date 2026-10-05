#!/usr/bin/env bats
# Тесты lib/kaneo.sh: формат id сущностей Kaneo (допускается в URL и в вывод шагов).

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/lib/kaneo.sh"
}

@test "kaneo_id_valid: буквы, цифры, '_' и '-' проходят" {
  local good
  for good in tid1 cuid2abc123 A_b-C 0 in-progress; do
    run bash -c "source '$LIB'; kaneo_id_valid \"\$1\"" _ "$good"
    [ "$status" -eq 0 ]
  done
}

@test "kaneo_id_valid: пустое, пробел, '/', '..', '?', ';', '\$(...)', кавычки и перевод строки отвергаются" {
  local bad
  for bad in '' 'a b' 'a/b' '..' 'a?x=1' 'a;id' '$(id)' 'a"b' "a'b" 'a#b' 'ключ'; do
    run bash -c "source '$LIB'; kaneo_id_valid \"\$1\"" _ "$bad"
    [ "$status" -ne 0 ]
  done
  run bash -c "source '$LIB'; kaneo_id_valid \$'abc\\nid'"
  [ "$status" -ne 0 ]
}

@test "source: повторное подключение в том же shell не падает под bash -e" {
  run bash -e -c "source '$LIB'; source '$LIB'; kaneo_id_valid ok1 && echo ok"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "kaneo_func_name_valid: строчные буквы, цифры и '_' (не с цифры) проходят" {
  local good
  for good in release_version a _x v2 date_2; do
    run bash -c "source '$LIB'; kaneo_func_name_valid \"\$1\"" _ "$good"
    [ "$status" -eq 0 ]
  done
}

@test "kaneo_func_name_valid: пустое, заглавные, цифра первой, '-', '.', '/', пробел и перевод строки отвергаются" {
  local bad
  for bad in '' Release 1abc a-b a.b ../x 'a b' 'a;id' '$(id)' 'имя'; do
    run bash -c "source '$LIB'; kaneo_func_name_valid \"\$1\"" _ "$bad"
    [ "$status" -ne 0 ]
  done
  run bash -c "source '$LIB'; kaneo_func_name_valid \$'abc\\nid'"
  [ "$status" -ne 0 ]
}

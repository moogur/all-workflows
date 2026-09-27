#!/usr/bin/env bats
# Guard-тест: форматы "базовых значений" (версия/тег, коммит, docker-ссылка, ...)
# разбираются только в lib/*.sh — в .github, scripts и .husky не должно быть их
# повторной реализации (регэкспов/идиом), только вызовы lib-функций.
# Комментарии-упоминания формата в прозе не считаются: только строки кода.

setup() {
  load helpers
  ROOT="$(repo_root)"
}

# assert_no_code_matches <шаблон> <директории...> — грепает шаблон (фиксированной
# строкой) вне lib/ и tests/, отбрасывает строки-комментарии (начинаются с '#').
assert_no_code_matches() {
  local pattern="$1"
  shift
  local hits
  hits=$(grep -rnF -- "$pattern" "$@" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
  if [[ -n "$hits" ]]; then
    echo "Найдены повторы формата ('${pattern}') вне lib/:"
    echo "$hits"
    return 1
  fi
}

@test "формат даты (dd.mm.yyyy) не переизобретается вне lib/version.sh" {
  run assert_no_code_matches '[0-9]{2}\.[0-9]{2}\.[0-9]{4}' "$ROOT/.github" "$ROOT/scripts" "$ROOT/.husky"
  [ "$status" -eq 0 ]
}

@test "формат semver (^v[0-9]) не переизобретается вне lib/version.sh" {
  run assert_no_code_matches '^v[0-9]' "$ROOT/.github" "$ROOT/scripts" "$ROOT/.husky"
  [ "$status" -eq 0 ]
}

@test "сортировка тегов по creatordate не переизобретается вне lib/tags.sh" {
  run assert_no_code_matches 'creatordate' "$ROOT/.github" "$ROOT/scripts" "$ROOT/.husky"
  [ "$status" -eq 0 ]
}

@test "распознавание Merge pull request не переизобретается вне lib/commit.sh" {
  run assert_no_code_matches 'Merge pull request' "$ROOT/.github" "$ROOT/scripts" "$ROOT/.husky"
  [ "$status" -eq 0 ]
}

@test "список типов коммита (feature bugfix ...) не переизобретается вне lib/commit.sh" {
  run assert_no_code_matches 'feature bugfix' "$ROOT/.github" "$ROOT/scripts" "$ROOT/.husky"
  [ "$status" -eq 0 ]
}

@test "снятие refs/tags/ не переизобретается вне lib/version.sh" {
  run assert_no_code_matches '#refs/tags/' "$ROOT/.github" "$ROOT/scripts" "$ROOT/.husky"
  [ "$status" -eq 0 ]
}

@test "разбор task_id через 'tr \"-\" \" \"' не переизобретается вне lib/commit.sh" {
  run assert_no_code_matches 'tr "-" " "' "$ROOT/.github" "$ROOT/scripts" "$ROOT/.husky"
  [ "$status" -eq 0 ]
}

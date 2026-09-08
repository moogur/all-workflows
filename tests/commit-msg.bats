#!/usr/bin/env bats
# Тесты для git-хука .husky/commit-msg.
# Формат сообщения: [GA-<num>] <type>(<scope>): <subject>
# Скрипт не модифицируется — тесты фиксируют его фактическое поведение.

setup() {
  load helpers
  ROOT="$(repo_root)"
  HOOK="$ROOT/.husky/commit-msg"
  TMP="$(mktemp -d)"
  MSG="$TMP/msg"
}

teardown() {
  rm -rf "$TMP"
}

expect_pass() {
  printf '%s\n' "$1" > "$MSG"
  run bash "$HOOK" "$MSG"
  if [ "$status" -ne 0 ]; then
    echo "Ожидалось ПРОХОЖДЕНИЕ для: '$1'"
    echo "status=$status output=$output"
    return 1
  fi
}

expect_fail() {
  printf '%s\n' "$1" > "$MSG"
  run bash "$HOOK" "$MSG"
  if [ "$status" -eq 0 ]; then
    echo "Ожидался ОТКАЗ для: '$1'"
    return 1
  fi
}

# ---------- happy path: все допустимые типы ----------

@test "тип feature проходит" { expect_pass "[GA-1] feature(api): add endpoint"; }
@test "тип bugfix проходит"  { expect_pass "[GA-2] bugfix(api): fix null check"; }
@test "тип ci проходит"      { expect_pass "[GA-3] ci(pipeline): cache modules"; }
@test "тип config проходит"  { expect_pass "[GA-4] config(eslint): tune rules"; }
@test "тип refactor проходит" { expect_pass "[GA-5] refactor(core): split module"; }
@test "тип test проходит"    { expect_pass "[GA-6] test(core): add cases"; }
@test "тип docs проходит"    { expect_pass "[GA-7] docs(readme): describe usage"; }

# ---------- happy path: номер задачи ----------

@test "многозначный номер задачи" { expect_pass "[GA-123456] feature(api): x"; }
@test "номер с ведущим нулём"     { expect_pass "[GA-007] feature(api): x"; }

# ---------- happy path: subject ----------

@test "subject с цифрами и пунктуацией (нижний регистр)" {
  expect_pass "[GA-1] feature(api): add v2.1 support (beta)"
}

@test "scope с цифрами" { expect_pass "[GA-1] feature(api2): x"; }

@test "subject ровно 125 символов проходит" {
  local s; s=$(printf 'a%.0s' {1..125})
  expect_pass "[GA-1] feature(api): $s"
}

# ---------- breaking: номер задачи ----------

@test "номер без скобок отклоняется"          { expect_fail "GA-1 feature(api): x"; }
@test "номер без пробела после скобок"         { expect_fail "[GA-1]feature(api): x"; }
@test "номер в нижнем регистре (ga) отклоняется" { expect_fail "[ga-1] feature(api): x"; }
@test "номер без цифр отклоняется"             { expect_fail "[GA-] feature(api): x"; }
@test "номер с буквой в цифрах отклоняется"    { expect_fail "[GA-1a] feature(api): x"; }
@test "другой префикс задачи (JIRA) отклоняется" { expect_fail "[JIRA-1] feature(api): x"; }
@test "пустое сообщение отклоняется"           { expect_fail ""; }

# ---------- breaking: тип ----------

@test "тип с заглавной буквы отклоняется"   { expect_fail "[GA-1] Feature(api): x"; }
@test "неизвестный тип отклоняется"          { expect_fail "[GA-1] unknown(api): x"; }
@test "пустой тип отклоняется"               { expect_fail "[GA-1] (api): x"; }

# ---------- breaking: scope ----------

@test "пустой scope отклоняется"             { expect_fail "[GA-1] feature(): x"; }
@test "scope в верхнем регистре отклоняется" { expect_fail "[GA-1] feature(Api): x"; }
@test "scope с заглавной буквой внутри отклоняется" { expect_fail "[GA-1] feature(apiV2): x"; }
@test "отсутствие scope (без скобок) отклоняется"   { expect_fail "[GA-1] feature: x"; }

# ---------- breaking: subject ----------

@test "subject в верхнем регистре отклоняется" { expect_fail "[GA-1] feature(api): Add X"; }
@test "пустой subject отклоняется"             { expect_fail "[GA-1] feature(api): "; }
@test "отсутствие ': ' отклоняется"            { expect_fail "[GA-1] feature(api) add x"; }

@test "subject 126 символов отклоняется (граница)" {
  local s; s=$(printf 'a%.0s' {1..126})
  expect_fail "[GA-1] feature(api): $s"
}

# ---------- многострочные сообщения ----------
# Регрессия: разбирался весь файл целиком, и awk склеивал токены всех строк,
# из-за чего валидный коммит с телом отклонялся.

expect_pass_multiline() {
  printf '%s\n' "$@" > "$MSG"
  run bash "$HOOK" "$MSG"
  if [ "$status" -ne 0 ]; then
    echo "Ожидалось ПРОХОЖДЕНИЕ для многострочного сообщения"
    echo "status=$status output=$output"
    return 1
  fi
}

@test "заголовок с телом проходит" {
  expect_pass_multiline "[GA-1] feature(api): add endpoint" "" "detail line one" "detail line two"
}

@test "тело в верхнем регистре не влияет на проверку" {
  expect_pass_multiline "[GA-1] feature(api): add endpoint" "" "BREAKING CHANGE: Renamed input"
}

@test "тело длиннее 125 символов не влияет на проверку" {
  local s; s=$(printf 'A%.0s' {1..200})
  expect_pass_multiline "[GA-1] feature(api): add endpoint" "" "$s"
}

@test "тело со скобками и двоеточиями не подменяет scope и subject" {
  expect_pass_multiline "[GA-1] feature(api): add endpoint" "" "see docker-tags(action): Details" "type: WRONG"
}

@test "битый заголовок отклоняется даже при валидной строке в теле" {
  printf '%s\n' "wrong header" "" "[GA-1] feature(api): add endpoint" > "$MSG"
  run bash "$HOOK" "$MSG"
  [ "$status" -ne 0 ]
}

# ---------- характеристические особенности парсинга ----------
# Эти тесты фиксируют фактическое (нестрогое) поведение валидатора,
# чтобы изменения в нём были замечены. См. docs/modernization.md.

@test "(особенность) частичное совпадение типа проходит: 'feat' ⊂ 'feature'" {
  # includeInTypes использует подстрочное совпадение без якорей,
  # поэтому 'feat' проходит как часть 'feature'.
  expect_pass "[GA-1] feat(api): x"
}

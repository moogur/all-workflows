#!/usr/bin/env bats
# Тесты для lib/commit.sh: формат заголовка коммита, PR-заголовки, тип, task_id.
# Поведение хука .husky/commit-msg (сообщения, требование префикса GA) — в
# tests/commit-msg.bats; категории тела релиза по типу — в tests/release-notes*.bats.

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/lib/commit.sh"
}

sh() {
  run bash -c "source '$LIB'; $*"
}

# ---------- COMMIT_HEADER_REGEX ----------

@test "header: заголовок валидного формата разбирается на 4 группы" {
  sh '[[ "[GA-557] feature(frontend): add endpoint" =~ $COMMIT_HEADER_REGEX ]] &&
      printf "%s|%s|%s|%s" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"'
  [ "$status" -eq 0 ]
  [ "$output" = "GA-557|feature|frontend|add endpoint" ]
}

@test "header: произвольный префикс задачи (не GA) тоже разбирается" {
  sh '[[ "[IPB-572] refactor(src): split" =~ $COMMIT_HEADER_REGEX ]] && echo "${BASH_REMATCH[1]}"'
  [ "$output" = "IPB-572" ]
}

@test "header: без пробела после ']' не матчится" {
  sh '[[ "[GA-1]feature(api): x" =~ $COMMIT_HEADER_REGEX ]]'
  [ "$status" -ne 0 ]
}

@test "header: пустой subject (только пробел после ':') не матчится" {
  # Регрессия: '*' на пробеле после ':' даёт subject=' ' (не пустой) — квантификатор '+'.
  sh '[[ "[GA-1] feature(api): " =~ $COMMIT_HEADER_REGEX ]]'
  [ "$status" -ne 0 ]
}

@test "header: пустой scope не матчится" {
  sh '[[ "[GA-1] feature(): x" =~ $COMMIT_HEADER_REGEX ]]'
  [ "$status" -ne 0 ]
}

@test "header: без скобок вокруг scope не матчится" {
  sh '[[ "[GA-1] feature: x" =~ $COMMIT_HEADER_REGEX ]]'
  [ "$status" -ne 0 ]
}

@test "header: тип с заглавной буквы не матчится" {
  sh '[[ "[GA-1] Feature(api): x" =~ $COMMIT_HEADER_REGEX ]]'
  [ "$status" -ne 0 ]
}

# ---------- COMMIT_MERGE_PR_REGEX / COMMIT_SQUASH_PR_REGEX ----------

@test "merge_pr: захватывает номер PR" {
  sh '[[ "Merge pull request #12 from user/feature" =~ $COMMIT_MERGE_PR_REGEX ]] && echo "${BASH_REMATCH[1]}"'
  [ "$output" = "12" ]
}

@test "merge_pr: 'Merge branch' не матчится" {
  sh "[[ \"Merge branch 'chore'\" =~ \$COMMIT_MERGE_PR_REGEX ]]"
  [ "$status" -ne 0 ]
}

@test "squash_pr: захватывает заголовок без суффикса и номер PR" {
  sh '[[ "[GA-2] bugfix(x): y (#13)" =~ $COMMIT_SQUASH_PR_REGEX ]] && printf "%s|%s" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"'
  [ "$output" = "[GA-2] bugfix(x): y|13" ]
}

@test "squash_pr: без суффикса '(#N)' не матчится" {
  sh '[[ "[GA-2] bugfix(x): y" =~ $COMMIT_SQUASH_PR_REGEX ]]'
  [ "$status" -ne 0 ]
}

# ---------- commit_type_allowed ----------

@test "type_allowed: все объявленные типы проходят" {
  for t in feature bugfix ci config refactor test docs; do
    sh "commit_type_allowed $t"
    [ "$status" -eq 0 ]
  done
}

@test "type_allowed: точное совпадение — 'feat' не проходит как часть 'feature'" {
  sh "commit_type_allowed feat"
  [ "$status" -ne 0 ]
}

@test "type_allowed: неизвестный тип отклоняется" {
  sh "commit_type_allowed unknown"
  [ "$status" -ne 0 ]
}

# ---------- COMMIT_CATEGORY_OF ----------

@test "category_of: feature и test — features" {
  sh 'echo "${COMMIT_CATEGORY_OF[feature]} ${COMMIT_CATEGORY_OF[test]}"'
  [ "$output" = "features features" ]
}

@test "category_of: ci и config — configuration" {
  sh 'echo "${COMMIT_CATEGORY_OF[ci]} ${COMMIT_CATEGORY_OF[config]}"'
  [ "$output" = "configuration configuration" ]
}

@test "category_of: неизвестный тип не имеет записи (вызывающий код решает про 'other')" {
  sh 'echo "${COMMIT_CATEGORY_OF[unknown]:-other}"'
  [ "$output" = "other" ]
}

# ---------- commit_is_lowercase ----------

@test "is_lowercase: нижний регистр проходит" {
  sh "commit_is_lowercase api"
  [ "$status" -eq 0 ]
}

@test "is_lowercase: заглавная буква отклоняется" {
  sh "commit_is_lowercase Api"
  [ "$status" -ne 0 ]
}

# ---------- commit_task_id_token ----------

@test "task_id_token: заголовок коммита '[GA-557] ...' -> 557" {
  sh "commit_task_id_token '[GA-557] feature(frontend): add endpoint'"
  [ "$output" = "557" ]
}

@test "task_id_token: имя ветки с дефисами 'GA-123-fix-thing' -> 123" {
  sh "commit_task_id_token GA-123-fix-thing"
  [ "$output" = "123" ]
}

@test "task_id_token: имя ветки с подчёркиваниями 'GA-123_fix_thing' -> 123" {
  sh "commit_task_id_token GA-123_fix_thing"
  [ "$output" = "123" ]
}

@test "task_id_token: многострочный текст — смотрит только первую строку" {
  sh $'commit_task_id_token "[GA-9] feature(api): x\\n\\nGA-999 in the body"'
  [ "$output" = "9" ]
}

@test "task_id_token: текст без разделителей отдаёт пустую строку" {
  sh "commit_task_id_token onewordonly"
  [ -z "$output" ]
}

#!/usr/bin/env bats
# Тесты для lib/commit.sh: формат заголовка коммита, PR-заголовки, тип, номер задачи.
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

# ---------- commit_task_key_valid ----------

@test "task_key_valid: PREFIX-N с любым префиксом проходит, включая ведущие нули" {
  sh "commit_task_key_valid GA-557"
  [ "$status" -eq 0 ]
  sh "commit_task_key_valid IPB-007"
  [ "$status" -eq 0 ]
  sh "commit_task_key_valid A1-1"
  [ "$status" -eq 0 ]
}

@test "task_key_valid: пустое, без номера, строчный префикс, пробел, ';', '\$(...)' и перевод строки отвергаются" {
  local bad
  for bad in '' GA GA- GA-12a ga-12 1A-12 ' GA-12' 'GA-12 ' 'GA-1;id' 'GA-$(id)' 'GA--1' '-12'; do
    run bash -c "source '$LIB'; commit_task_key_valid \"\$1\"" _ "$bad"
    [ "$status" -ne 0 ]
  done
  run bash -c "source '$LIB'; commit_task_key_valid \$'GA-12\\nid'"
  [ "$status" -ne 0 ]
}

# ---------- commit_task_key ----------

@test "task_key: заголовок коммита '[GA-557] ...' -> GA-557" {
  sh "commit_task_key '[GA-557] feature(frontend): add endpoint'"
  [ "$output" = "GA-557" ]
}

@test "task_key: префикс другого проекта сохраняется" {
  sh "commit_task_key '[IPB-456] bugfix(api): x'"
  [ "$output" = "IPB-456" ]
}

@test "task_key: имя ветки с дефисами 'GA-123-fix-thing' -> GA-123" {
  sh "commit_task_key GA-123-fix-thing"
  [ "$output" = "GA-123" ]
}

@test "task_key: имя ветки с подчёркиваниями 'GA-123_fix_thing' -> GA-123" {
  sh "commit_task_key GA-123_fix_thing"
  [ "$output" = "GA-123" ]
}

@test "task_key: имя без суффикса 'GA-123' -> GA-123" {
  sh "commit_task_key GA-123"
  [ "$output" = "GA-123" ]
}

@test "task_key: многострочный текст — смотрит только первую строку" {
  sh $'commit_task_key "[GA-9] feature(api): x\\n\\nGA-999 in the body"'
  [ "$output" = "GA-9" ]
}

@test "task_key: номер только в теле, первая строка без номера — пусто" {
  sh $'commit_task_key "no key here\\n[GA-9] feature(api): x"'
  [ -z "$output" ]
}

@test "task_key: строчный префикс не принимается" {
  sh "commit_task_key ga-123-fix"
  [ -z "$output" ]
}

@test "task_key: подстановка команды в заголовке не выполняется и номера нет" {
  local marker="$BATS_TEST_TMPDIR/pwned"
  run bash -c "source '$LIB'; commit_task_key '[GA-\$(touch\${IFS}$marker)] x'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$marker" ]
}

@test "task_key: 'GA-\$(id)-x' и 'GA-1;id' не дают номера" {
  sh "commit_task_key 'GA-\$(id)-x'"
  [ -z "$output" ]
  sh "commit_task_key 'GA-1;id'"
  [ -z "$output" ]
}

@test "task_key: без номера (одно слово, пустой ввод) — пусто и код 0" {
  sh "commit_task_key onewordonly"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  sh "commit_task_key ''"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "task_key: старые числовые функции удалены" {
  sh "type commit_task_id commit_task_id_token commit_task_id_valid"
  [ "$status" -ne 0 ]
}

# ---------- повторное подключение ----------

@test "source: повторное подключение в том же shell не падает под bash -e" {
  run bash -e -c "source '$LIB'; source '$LIB'; echo ok"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "source: все скрипты kaneo в одном shell, в обоих порядках — как в kaneo.yml" {
  local task_id="$ROOT/scripts/kaneo/task_key.sh" requests="$ROOT/scripts/kaneo/requests.sh"
  # После двойного подключения константы и функции обоих скриптов на месте
  local probe="commit_task_key '[GA-557] feature(api): x'; echo \$COMMIT_SUBJECT_MAX_LENGTH;
    require_kaneo_id task tid1 && echo valid; declare -F tags_latest_n >/dev/null && echo tags"
  run bash -e -c "source '$task_id'; source '$requests'; $probe"
  [ "$status" -eq 0 ]
  [ "$output" = $'GA-557\n125\nvalid\ntags' ]
  run bash -e -c "source '$requests'; source '$task_id'; $probe"
  [ "$status" -eq 0 ]
  [ "$output" = $'GA-557\n125\nvalid\ntags' ]
}

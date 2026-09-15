#!/usr/bin/env bats
# Guard-тесты pr_annotation.yml: этот workflow единственный исполняет код из
# Pull Request, поэтому важно, чтобы форки до него не доходили, а токен
# приватного scope не лежал рядом с тестами.

setup() {
  load helpers
  ROOT="$(repo_root)"
  WF="$ROOT/.github/workflows/pr_annotation.yml"
}

# Номер строки первого совпадения с шаблоном.
line_of() {
  grep -nE "$1" "$WF" | head -n1 | cut -d: -f1
}

@test "job не запускается на Pull Request из форка" {
  grep -qE '^ +if: .*github\.event\.pull_request\.head\.repo\.full_name == github\.repository' "$WF"
}

@test "не-PR события условие не отсекает" {
  grep -qE "github\.event_name != 'pull_request' \|\|" "$WF"
}

@test ".npmrc удаляется после установки зависимостей" {
  local install remove
  install=$(line_of '^ +run: npm ci$')
  remove=$(line_of '^ +run: rm -f \.npmrc$')
  [ -n "$install" ]
  [ -n "$remove" ]
  [ "$remove" -gt "$install" ]
}

@test ".npmrc удаляется до выполнения кода из PR" {
  local remove coverage
  remove=$(line_of '^ +run: rm -f \.npmrc$')
  coverage=$(line_of 'uses: ArtiomTr/jest-coverage-report-action')
  [ -n "$coverage" ]
  [ "$remove" -lt "$coverage" ]
}

@test "action покрытия не ставит зависимости сам" {
  # Свой install он сделал бы уже без .npmrc — приватный scope не поднялся бы.
  grep -qE '^ +skip-step: install$' "$WF"
}

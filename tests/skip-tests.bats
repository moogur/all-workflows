#!/usr/bin/env bats
# Guard-тесты выключателя тестов: если переиспользуемый workflow гоняет тесты,
# то потребитель обязан иметь возможность их выключить входом skip_tests.
# ci.yml не проверяется — это CI самого репозитория, а не reusable workflow.

setup() {
  load helpers
  ROOT="$(repo_root)"
  WF="$ROOT/.github/workflows"
}

# Команды, которые считаются запуском тестов.
TEST_COMMANDS='npm run test|go test |jest-coverage-report-action'

# Список reusable workflow'ов, где есть шаг с тестами.
workflows_with_tests() {
  local wf
  for wf in "$WF"/*.yml; do
    grep -q 'workflow_call' "$wf" || continue
    grep -qE "$TEST_COMMANDS" "$wf" && echo "$wf"
  done
}

@test "тестовый шаг закрыт условием skip_tests" {
  # Шаг идёт как "- name: / if: / run:", поэтому к моменту тестовой команды
  # условие уже встречено; на каждом новом "- name:" флаг сбрасывается.
  local ungated
  ungated=$(workflows_with_tests | xargs awk -v pattern="$TEST_COMMANDS" '
    /^ +- name:/ { gated = 0 }
    /inputs\.skip_tests/ { gated = 1 }
    $0 ~ pattern && !gated { print FILENAME }
  ' | sort -u)

  [ -z "$ungated" ] || { echo "Тесты нельзя выключить в: $ungated"; return 1; }
}

@test "вход skip_tests объявлен и не обязателен" {
  local wf
  for wf in $(workflows_with_tests); do
    grep -qE '^ +skip_tests:' "$wf" \
      || { echo "В $(basename "$wf") нет входа skip_tests"; return 1; }
    grep -A4 -E '^ +skip_tests:' "$wf" | grep -qE '^ +default: .false.' \
      || { echo "В $(basename "$wf") у skip_tests нет default: 'false'"; return 1; }
  done
}

@test "тесты по умолчанию включены" {
  # Вход необязательный, поэтому потребитель, ничего не передавший, гоняет тесты.
  local wf
  for wf in $(workflows_with_tests); do
    grep -A4 -E '^ +skip_tests:' "$wf" | grep -qE '^ +required: false' \
      || { echo "В $(basename "$wf") skip_tests не объявлен как required: false"; return 1; }
  done
}

@test "шаг тестов есть во всех workflow'ах, где объявлен skip_tests" {
  # Обратная проверка: вход без единого закрытого им шага — забытая правка.
  local wf
  for wf in "$WF"/*.yml; do
    grep -qE '^ +skip_tests:' "$wf" || continue
    grep -qE "$TEST_COMMANDS" "$wf" \
      || { echo "В $(basename "$wf") есть skip_tests, но нет шага с тестами"; return 1; }
  done
}

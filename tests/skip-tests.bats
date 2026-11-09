#!/usr/bin/env bats
# Guard-тесты выключателя тестов: если переиспользуемый workflow гоняет тесты,
# то потребитель обязан иметь возможность их выключить входом skip_tests.
# Там же — тесты подготовки к тестам: такой workflow принимает скрипт потребителя
# (test_setup_script) и кэш к нему (test_setup_cache) и запускает их только вместе
# с тестами — вплотную перед тестовым шагом и под тем же условием skip_tests.
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

# Номер шага (по счёту "- name:") с первой тестовой командой, не считая комментариев; 0 — если её нет.
test_step_number() {
  awk -v pattern="$TEST_COMMANDS" '
    /^ +- name:/ { step++ }
    /^ *#/ { next }
    $0 ~ pattern { print step; found = 1; exit }
    END { if (!found) print 0 }
  ' "$1"
}

# Номер шага с `uses: <action>`, закрытого условием, где есть все слова из $3
# (через пробел); 0 — если такого шага нет.
gated_step_number() {
  awk -v action="$2" -v words="$3" '
    BEGIN { n = split(words, need, " ") }
    /^ +- name:/ { step++; gated = 0 }
    /^ +if:/ {
      gated = 1
      for (i = 1; i <= n; i++) if (index($0, need[i]) == 0) gated = 0
    }
    gated && index($0, "uses: " action) { print step; found = 1; exit }
    END { if (!found) print 0 }
  ' "$1"
}

RUN_BUILD_SCRIPT='moogur/all-workflows/.github/actions/run-build-script@master'

@test "входы test_setup_script и test_setup_cache объявлены, не обязательны и по умолчанию пусты" {
  local wf input
  for wf in $(workflows_with_tests); do
    for input in test_setup_script test_setup_cache; do
      grep -qE "^ +${input}:" "$wf" \
        || { echo "В $(basename "$wf") нет входа $input"; return 1; }
      grep -A4 -E "^ +${input}:" "$wf" | grep -qE '^ +required: false' \
        || { echo "В $(basename "$wf") $input не объявлен как required: false"; return 1; }
      grep -A4 -E "^ +${input}:" "$wf" | grep -qE "^ +default: ''" \
        || { echo "В $(basename "$wf") у $input нет default: ''"; return 1; }
    done
  done
}

@test "скрипт подготовки идёт через run-build-script и закрыт skip_tests и test_setup_script" {
  local wf
  for wf in $(workflows_with_tests); do
    [ "$(gated_step_number "$wf" "$RUN_BUILD_SCRIPT" 'inputs.skip_tests inputs.test_setup_script')" -gt 0 ] \
      || { echo "В $(basename "$wf") нет шага run-build-script под условием skip_tests и test_setup_script"; return 1; }
  done
}

@test "скрипт подготовки получает путь из входа test_setup_script" {
  local wf
  for wf in $(workflows_with_tests); do
    grep -qE 'file_path: \$\{\{ inputs\.test_setup_script \}\}' "$wf" \
      || { echo "В $(basename "$wf") file_path не берётся из inputs.test_setup_script"; return 1; }
  done
}

@test "кэш подготовки закрыт skip_tests и обоими входами" {
  local wf
  for wf in $(workflows_with_tests); do
    [ "$(gated_step_number "$wf" 'actions/cache@' 'inputs.skip_tests inputs.test_setup_script inputs.test_setup_cache')" -gt 0 ] \
      || { echo "В $(basename "$wf") нет шага actions/cache под условием skip_tests, test_setup_script и test_setup_cache"; return 1; }
  done
}

@test "ключ кэша подготовки зависит от содержимого скрипта" {
  local wf
  for wf in $(workflows_with_tests); do
    grep -qF 'key: setup-${{ runner.os }}-${{ runner.arch }}-${{ hashFiles(inputs.test_setup_script) }}' "$wf" \
      || { echo "В $(basename "$wf") ключ кэша подготовки не включает hashFiles(inputs.test_setup_script)"; return 1; }
  done
}

@test "подготовка стоит вплотную перед тестовым шагом: кэш, затем скрипт, затем тесты" {
  local wf cache script tests
  for wf in $(workflows_with_tests); do
    cache=$(gated_step_number "$wf" 'actions/cache@' 'inputs.test_setup_cache')
    script=$(gated_step_number "$wf" "$RUN_BUILD_SCRIPT" 'inputs.test_setup_script')
    tests=$(test_step_number "$wf")
    [ "$tests" -gt 0 ] && [ "$script" -gt 0 ] && [ "$cache" -gt 0 ] \
      || { echo "В $(basename "$wf") не найден шаг: кэш=$cache скрипт=$script тесты=$tests"; return 1; }
    [ "$script" -eq $((tests - 1)) ] \
      || { echo "В $(basename "$wf") скрипт подготовки (шаг $script) не стоит вплотную перед тестами (шаг $tests)"; return 1; }
    [ "$cache" -eq $((script - 1)) ] \
      || { echo "В $(basename "$wf") кэш (шаг $cache) не стоит вплотную перед скриптом (шаг $script)"; return 1; }
  done
}

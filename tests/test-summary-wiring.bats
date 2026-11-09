#!/usr/bin/env bats
# Guard-тесты подключения сводки тестов: тестовый шаг пишет отчёт, а шаг сводки идёт
# после него и запускается, в том числе когда тесты упали, но не когда они не запускались.

setup() {
  load helpers
  ROOT="$(repo_root)"
  WF="$ROOT/.github/workflows"
}

# Номер строки первого совпадения с шаблоном в файле; пусто, если совпадения нет.
line_of() {
  grep -nE "$2" "$1" | head -n1 | cut -d: -f1
}

# Строки шага от "- name: <имя>" до следующего "- name:" или конца файла.
step_text() {
  awk -v name="$2" '
    /^ +- name:/ { in_step = (index($0, name) > 0) }
    in_step { print }
  ' "$1"
}

SUMMARY_ACTION='moogur/all-workflows/.github/actions/test-summary@master'

@test "go: тесты идут под bash с pipefail — упавший go test роняет шаг, а не теряется за jq" {
  # Без явного shell: bash GitHub запускает `bash -e {0}` без pipefail, и конвейер с tee и jq
  # возвращает статус последней команды — зелёный шаг при красных тестах.
  step_text "$WF/actions_for_push_go.yml" 'Run tests' | grep -qxF '        shell: bash'
}

@test "go: тесты пишут отчёт -json в файл и не теряют человекочитаемый лог" {
  step_text "$WF/actions_for_push_go.yml" 'Run tests' | grep -qF 'go test -race -vet=off -json ./...'
  step_text "$WF/actions_for_push_go.yml" 'Run tests' | grep -qF 'tee "$REPORT"'
  step_text "$WF/actions_for_push_go.yml" 'Run tests' | grep -qF '"build-output"'
}

@test "go: сводка идёт после тестов, формат go, запускается и при падении тестов" {
  local text
  text=$(step_text "$WF/actions_for_push_go.yml" 'Test summary')
  grep -qF "uses: $SUMMARY_ACTION" <<< "$text"
  grep -qxF '          format: go' <<< "$text"
  grep -qF "if: \"!cancelled() && steps.tests.outcome != 'skipped'\"" <<< "$text"
  [ "$(line_of "$WF/actions_for_push_go.yml" 'name: .Test summary')" -gt "$(line_of "$WF/actions_for_push_go.yml" 'name: Run tests')" ]
}

@test "go: отчёт пишется и читается по одному и тому же пути" {
  grep -qF 'REPORT: ${{ runner.temp }}/go-test-report.json' "$WF/actions_for_push_go.yml"
  grep -qF 'report: ${{ runner.temp }}/go-test-report.json' "$WF/actions_for_push_go.yml"
}

@test "node: тест получает аргументы раннера, сводка берёт формат и путь из его шага" {
  local text
  step_text "$WF/actions_for_push.yml" "'Test'" | grep -qF 'TEST_ARGS: ${{ steps.runner.outputs.args }}'
  step_text "$WF/actions_for_push.yml" "'Test'" | grep -qF 'npm run test:coverage -- $TEST_ARGS'
  text=$(step_text "$WF/actions_for_push.yml" 'Test summary')
  grep -qF "uses: $SUMMARY_ACTION" <<< "$text"
  grep -qF 'format: ${{ steps.runner.outputs.format }}' <<< "$text"
  grep -qF 'report: ${{ steps.runner.outputs.report }}' <<< "$text"
}

@test "node: сводка запускается при падении тестов, но не когда они пропущены или раннер не найден" {
  step_text "$WF/actions_for_push.yml" 'Test summary' \
    | grep -qF "if: \"!cancelled() && steps.tests.outcome != 'skipped' && steps.runner.outputs.format != ''\""
}

@test "node: раннер определяется до тестового шага и закрыт skip_tests" {
  local wf="$WF/actions_for_push.yml"
  [ "$(line_of "$wf" "name: 'Detect test runner'")" -lt "$(line_of "$wf" "name: 'Test'")" ]
  step_text "$wf" 'Detect test runner' | grep -qF "if: \"inputs.skip_tests != 'true'\""
}

@test "pr_annotation: тесты идут через обёртку, путь отчёта не содержит report.json" {
  # Action не добавит флаги jest, если в команде есть подстрока report.json (isOldScript).
  local wf="$WF/pr_annotation.yml" line
  line=$(step_text "$wf" 'Test coverage (jest)' | grep -E '^ +test-script:')
  grep -qF 'bash ${{ steps.wrapper.outputs.script }} ${{ runner.temp }}/jest-head.json' <<< "$line"
  [[ "$line" != *report.json* ]]
  step_text "$wf" 'Jest wrapper' | grep -qF 'uses: moogur/all-workflows/.github/actions/jest-head-wrapper@master'
  step_text "$wf" 'Jest wrapper' | grep -qF "if: \"inputs.skip_tests != 'true'\""
}

@test "pr_annotation: сводка идёт после тестов, формат jest, тот же путь отчёта, запускается и при падении" {
  local wf="$WF/pr_annotation.yml" text
  text=$(step_text "$wf" 'Test summary')
  grep -qF "uses: $SUMMARY_ACTION" <<< "$text"
  grep -qxF '          format: jest' <<< "$text"
  grep -qF 'report: ${{ runner.temp }}/jest-head.json' <<< "$text"
  grep -qF "if: \"!cancelled() && steps.tests.outcome != 'skipped'\"" <<< "$text"
  [ "$(line_of "$wf" "name: 'Test summary'")" -gt "$(line_of "$wf" "name: 'Test coverage")" ]
}

@test "pr_annotation: обёртка определяется до подготовки к тестам, чтобы та стояла вплотную к тестовому шагу" {
  local wf="$WF/pr_annotation.yml"
  [ "$(line_of "$wf" "name: 'Jest wrapper'")" -lt "$(line_of "$wf" "name: 'Restore setup cache'")" ]
}

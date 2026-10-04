#!/usr/bin/env bats
# Guard-тест kanboard.yml: значения не подставляются в исполняемый файл, секреты
# доходят до kanboard_requests.sh только через env (docs/security.md, п. 8).

setup() {
  load helpers
  ROOT="$(repo_root)"
  WORKFLOW="$ROOT/.github/workflows/kanboard.yml"
}

# Строки кода workflow без комментариев.
code_lines() {
  grep -vE '^[[:space:]]*#' "$WORKFLOW"
}

@test "kanboard.yml не правит requests.sh через sed и не копирует скрипт" {
  run bash -c "grep -vE '^[[:space:]]*#' '$WORKFLOW' | grep -E 'sed[[:space:]]+-i|requests\\.sh[[:space:]]*$' | grep -vE 'source|^[[:space:]]*\\. '"
  [ -z "$output" ]
  run bash -c "grep -vE '^[[:space:]]*#' '$WORKFLOW' | grep -E 'sed |cp .*requests'"
  [ "$status" -ne 0 ]
}

@test "kanboard.yml не интерполирует secrets.* в тело run (только в env)" {
  # Любая строка с secrets.* должна быть присваиванием переменной окружения KANBOARD_*.
  run bash -c "grep -vE '^[[:space:]]*#' '$WORKFLOW' | grep 'secrets\\.' | grep -vE '^[[:space:]]+KANBOARD_(URL|USER|TOKEN): \\\$\\{\\{ secrets\\.KANBOARD_(HOST|USER|TOKEN) \\}\\}\$'"
  [ "$status" -ne 0 ]
}

@test "kanboard.yml: каждый шаг, подключающий requests.sh, получает KANBOARD_URL/USER/TOKEN через env" {
  local sources envs
  sources=$(code_lines | grep -c 'kanboard_requests\.sh')
  envs=$(code_lines | grep -c 'KANBOARD_TOKEN: \${{ secrets\.KANBOARD_TOKEN }}')
  [ "$sources" -ge 1 ]
  [ "$sources" -eq "$envs" ]
}

@test "kanboard.yml: push/pr/merge-шаги пропускаются без task_id" {
  run grep -c "steps.variables.outputs.task_id != ''" "$WORKFLOW"
  [ "$output" -eq 3 ]
}

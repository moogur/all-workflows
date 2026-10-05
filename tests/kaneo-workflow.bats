#!/usr/bin/env bats
# Guard-тест kaneo.yml: значения не подставляются в исполняемый файл, секреты и входы
# доходят до скриптов kaneo только через env (docs/security.md, п. 8).

setup() {
  load helpers
  ROOT="$(repo_root)"
  WORKFLOW="$ROOT/.github/workflows/kaneo.yml"
}

# Строки кода workflow без комментариев.
code_lines() {
  grep -vE '^[[:space:]]*#' "$WORKFLOW"
}

@test "kaneo.yml не правит скрипты через sed и не копирует их" {
  run bash -c "grep -vE '^[[:space:]]*#' '$WORKFLOW' | grep -E 'sed |cp .*kaneo'"
  [ "$status" -ne 0 ]
}

@test "kaneo.yml не интерполирует secrets.* в тело run (только в env)" {
  # Любая строка с secrets.* должна быть присваиванием переменной окружения KANEO_*.
  run bash -c "grep -vE '^[[:space:]]*#' '$WORKFLOW' | grep 'secrets\\.' | grep -vE '^[[:space:]]+KANEO_(URL|TOKEN): \\\$\\{\\{ secrets\\.KANEO_(HOST|TOKEN) \\}\\}\$'"
  [ "$status" -ne 0 ]
}

@test "kaneo.yml: каждый шаг, подключающий скрипты kaneo, получает KANEO_URL и KANEO_TOKEN через env" {
  local sources urls tokens
  sources=$(code_lines | grep -c 'source .all-workflows/scripts/kaneo_')
  urls=$(code_lines | grep -c 'KANEO_URL: \${{ secrets\.KANEO_HOST }}')
  tokens=$(code_lines | grep -c 'KANEO_TOKEN: \${{ secrets\.KANEO_TOKEN }}')
  [ "$sources" -eq 5 ]
  [ "$urls" -eq "$sources" ]
  [ "$tokens" -eq "$sources" ]
}

@test "kaneo.yml: пользовательского секрета (user) больше нет" {
  run grep -iE 'KANEO_USER|KANBOARD' "$WORKFLOW"
  [ "$status" -ne 0 ]
}

@test "kaneo.yml: push/pr/merge-шаги пропускаются без task_key" {
  run grep -c "steps.variables.outputs.task_key != ''" "$WORKFLOW"
  [ "$output" -eq 3 ]
}

@test "kaneo.yml: входы статусов review/merged/deploy необязательные, in_progress обязательный" {
  run input_required kaneo_status_in_progress
  [ "$output" = "true" ]
  local name
  for name in kaneo_status_review kaneo_status_merged kaneo_status_deploy; do
    run input_required "$name"
    [ "$output" = "false" ]
    run grep -A5 "      $name:" "$WORKFLOW"
    [[ "$output" == *"default: ''"* ]]
  done
}

# Значение required входа workflow_call (без yq: ищем строку required в блоке входа).
input_required() {
  awk -v name="      $1:" '$0 == name {found=1; next} found && /required:/ {print $2; exit}' "$WORKFLOW"
}

@test "kaneo.yml: права contents: read и concurrency объявлены" {
  grep -qE '^permissions:' "$WORKFLOW"
  grep -qE '^  contents: read$' "$WORKFLOW"
  grep -qE '^concurrency:' "$WORKFLOW"
}

@test "kaneo.yml: all-workflows выкачивается на job_workflow_sha" {
  run grep -c 'ref: \${{ github.job_workflow_sha }}' "$WORKFLOW"
  [ "$output" -eq 1 ]
}

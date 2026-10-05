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

@test "kaneo.yml: входы ровно kaneo_scheme и event_type, оба обязательные" {
  run yq_inputs
  [ "$output" = $'kaneo_scheme\nevent_type' ]
  run input_required kaneo_scheme
  [ "$output" = "true" ]
  run input_required event_type
  [ "$output" = "true" ]
}

# Имена входов workflow_call (без yq: строки с отступом 6 пробелов между inputs: и permissions:).
yq_inputs() {
  code_lines | awk '/^    inputs:/ {on=1; next} /^permissions:/ {on=0} on && /^      [a-z_]+:$/ {gsub(/[ :]/, ""); print}'
}

# Значение required входа workflow_call (ищем строку required в блоке входа).
input_required() {
  awk -v name="      $1:" '$0 == name {found=1; next} found && /required:/ {print $2; exit}' "$WORKFLOW"
}

@test "kaneo.yml: старые входы project_type и kaneo_status_* удалены" {
  run grep -E 'project_type|kaneo_status_|PROJECT_TYPE' "$WORKFLOW"
  [ "$status" -ne 0 ]
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

@test "kaneo.yml: в тело run не подставляются выражения \${{ }}" {
  run awk '/^ +run: \|/ {inrun=1; next} inrun && /^      - / {inrun=0} inrun && /\$\{\{/ {print; bad=1} END {exit bad}' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "kaneo.yml: единственный шаг со скриптом kaneo получает все значения через env" {
  [ "$(code_lines | grep -c 'source .all-workflows/scripts/kaneo/engine.sh')" -eq 1 ]
  code_lines | grep -q 'KANEO_URL: \${{ secrets\.KANEO_HOST }}'
  code_lines | grep -q 'KANEO_TOKEN: \${{ secrets\.KANEO_TOKEN }}'
  code_lines | grep -q 'KANEO_SCHEME: \${{ inputs\.kaneo_scheme }}'
  code_lines | grep -q 'EVENT_TYPE: \${{ inputs\.event_type }}'
  code_lines | grep -q 'HEAD_REF: \${{ github\.head_ref }}'
}

@test "kaneo.yml: данные задачи между шагами через outputs не передаются" {
  run grep -E 'GITHUB_OUTPUT|steps\.[a-z_]+\.outputs' "$WORKFLOW"
  [ "$status" -ne 0 ]
}

@test "kaneo.yml: пользовательского секрета (user) больше нет" {
  run grep -iE 'KANEO_USER|KANBOARD' "$WORKFLOW"
  [ "$status" -ne 0 ]
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

@test "kaneo.yml: репозиторий потребителя выкачивается с полной историей (fetch-depth: 0)" {
  grep -qE '^          fetch-depth: 0$' "$WORKFLOW"
}

@test "kaneo.yml: шаг Show result сохранён" {
  grep -q 'name: "Show result"' "$WORKFLOW"
}

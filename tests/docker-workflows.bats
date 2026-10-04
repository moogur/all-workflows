#!/usr/bin/env bats
# Guard-тесты docker-workflow'ов: всё тело сборки живёт в общем action
# docker-image, а сами workflow'ы только подставляют специфику стека.
# Поведение скриптов экшена проверяется в tests/docker-image.bats.

setup() {
  load helpers
  ROOT="$(repo_root)"
  WF="$ROOT/.github/workflows"
  DOCKER_WORKFLOWS=(deploy_for_backend deploy_for_go_backend deploy_for_full_app deploy_for_docker_container)
}

@test "все docker-workflow'ы собирают образ общим action" {
  local wf
  for wf in "${DOCKER_WORKFLOWS[@]}"; do
    grep -qF "moogur/all-workflows/.github/actions/docker-image@master" "$WF/$wf.yml" \
      || { echo "В $wf.yml сборка идёт мимо docker-image"; return 1; }
  done
}

@test "ни один workflow не собирает и не пушит образ сам" {
  # Ровно то место, где раньше расползались копии: теги, build-arg'и, push.
  local wf
  for wf in "${DOCKER_WORKFLOWS[@]}"; do
    run grep -qE 'docker (build|push|login)' "$WF/$wf.yml"
    [ "$status" -ne 0 ] || { echo "В $wf.yml остались свои docker-команды"; return 1; }
  done
}

@test "теги образа формирует docker-tags — и только в общем action" {
  grep -qF "moogur/all-workflows/.github/actions/docker-tags@master" "$ROOT/.github/actions/docker-image/action.yml"
  run grep -rlF "actions/docker-tags@master" "$WF"
  [ "$status" -ne 0 ]
}

@test "запрошенные Dockerfile и .dockerignore существуют в репозитории" {
  local wf name
  for wf in "${DOCKER_WORKFLOWS[@]}"; do
    while IFS= read -r name; do
      [ -f "$ROOT/dockerfiles/$name" ] || { echo "В $wf.yml запрошен $name, которого нет в dockerfiles/"; return 1; }
    done < <(awk '/^ *dockerfile: |^ *dockerignore: / { print $2 }' "$WF/$wf.yml")
  done
}

@test "deploy_for_docker_container собирает Dockerfile проекта" {
  # Подмена файла — признак того, что workflow перепутали с deploy_for_backend.
  run grep -qE '^ *dockerfile: ' "$WF/deploy_for_docker_container.yml"
  [ "$status" -ne 0 ]
}

# ---------- docker-release ----------

@test "docker-image публикует релиз только по тегу и последним шагом" {
  local action="$ROOT/.github/actions/docker-image/action.yml"
  local release_line publish_line
  release_line=$(grep -n "actions/docker-release@master" "$action" | cut -d: -f1)
  publish_line=$(grep -n 'run: bash "\$GITHUB_ACTION_PATH/publish.sh"' "$action" | cut -d: -f1)
  [ -n "$release_line" ]
  [ "$publish_line" -lt "$release_line" ]
  # Условие стоит на шаге прямо перед uses: docker-release, а не где-то ещё выше.
  sed -n "$((release_line - 1))p" "$action" | grep -qE "if: github\.ref_type == 'tag'"
}

@test "ни один из четырёх workflow'ов не вызывает docker-release сам" {
  # Публикация релиза — забота docker-image, а не отдельных workflow'ов.
  run grep -rlF "actions/docker-release@master" "$WF"
  [ "$status" -ne 0 ]
}

@test "ни один вход workflow или action не имеет дефолта, начинающегося с \$" {
  # Дефолт вида $GITHUB_ACTOR — просто строка: в with/env он не раскрывается
  # и попадает в команду как есть (так ломалась ссылка на образ).
  local found
  found=$(grep -rnE "^[[:space:]]+default:[[:space:]]*[\"']?\\$" "$ROOT/.github/workflows" "$ROOT/.github/actions" || true)
  [ -z "$found" ] || { echo "Дефолт с неразвёрнутой переменной: $found"; return 1; }
}

@test "github_user в docker-workflow'ах по умолчанию пустой — подставляет владельца resolve.sh" {
  local wf
  for wf in "${DOCKER_WORKFLOWS[@]}"; do
    awk '/^      github_user:/{f=1;next} f&&/^      [a-z_]+:/{exit} f&&/default:/{print}' "$WF/$wf.yml" \
      | grep -qE "default: ''$" || { echo "В $wf.yml default github_user не пустой"; return 1; }
  done
}

# Шаг экшена docker-image, в котором вызывается скрипт $1: строки от его "- " до следующего шага
action_step() {
  awk -v script="$1" '
    /^    - / { if (found) exit; step = "" }
    { step = step $0 "\n" }
    index($0, script) { found = 1 }
    END { if (found) printf "%s", step }
  ' "$ROOT/.github/actions/docker-image/action.yml"
}

@test "publish.sh логинится под пользователем, которого вычислил resolve.sh" {
  # Правило «пусто — владелец репозитория» живёт только в resolve.sh. Если шаг
  # публикации возьмёт inputs.github_user напрямую, пустой вход уйдёт в docker login.
  local step
  step=$(action_step 'publish.sh')
  [ -n "$step" ]
  grep -qF 'GITHUB_USER: ${{ steps.resolve.outputs.user }}' <<< "$step" \
    || { echo "Шаг публикации берёт пользователя не из resolve: $step"; return 1; }
}

@test "сырой вход github_user читает только resolve.sh" {
  local step uses
  step=$(action_step 'resolve.sh')
  grep -qF 'GITHUB_USER: ${{ inputs.github_user }}' <<< "$step"
  uses=$(grep -cF '${{ inputs.github_user }}' "$ROOT/.github/actions/docker-image/action.yml")
  [ "$uses" -eq 1 ] || { echo "inputs.github_user читается в $uses местах вместо одного"; return 1; }
}

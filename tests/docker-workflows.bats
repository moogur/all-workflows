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

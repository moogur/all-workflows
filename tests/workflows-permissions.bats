#!/usr/bin/env bats
# Guard-тесты прав GITHUB_TOKEN: каждый переиспользуемый workflow объявляет
# permissions явно, никто не просит write-all, а вызывающие auto_deploy не уже
# вложенных в них workflow'ов (вызванный не может просить больше вызвавшего).

setup() {
  load helpers
  ROOT="$(repo_root)"
  WF="$ROOT/.github/workflows"
}

@test "каждый workflow объявляет permissions" {
  local wf
  for wf in "$WF"/*.yml; do
    grep -qE '^permissions:' "$wf" || { echo "В $(basename "$wf") нет блока permissions"; return 1; }
  done
}

@test "никто не просит write-all" {
  run grep -rlE '^permissions:[[:space:]]*write-all' "$WF"
  [ "$status" -ne 0 ]
}

@test "auto_deploy не уже вложенного деплоя по packages" {
  # deploy_for_docker_container просит packages: write — вызывающий обязан тоже.
  grep -qE '^  packages: write' "$WF/auto_deploy_for_docker_container.yml"
}

@test "auto_deploy не уже вложенного деплоя по contents" {
  # deploy_for_build_application создаёт релиз, значит нужен contents: write.
  grep -qE '^  contents: write' "$WF/auto_deploy_for_build_application.yml"
}

@test "auto_deploy не уже вложенного деплоя по pull-requests" {
  # deploy_for_build_application умеет режим drafter, а тому нужны PR.
  grep -qE '^  pull-requests: read' "$WF/auto_deploy_for_build_application.yml"
}

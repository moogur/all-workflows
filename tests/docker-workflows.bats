#!/usr/bin/env bats
# Guard-тесты docker-workflow'ов: теги образа собирает общий action, версия
# берётся из тега, инициировавшего запуск, а semver действует только на сборку
# по тегу — плановая пересборка не должна переписывать релизные vX.Y.Z.

setup() {
  load helpers
  ROOT="$(repo_root)"
  WF="$ROOT/.github/workflows"
  # deploy_for_docker_container живёт по своим правилам (версия из ref_name,
  # без app-version) и проверяется в auto-deploy.bats.
  TAGGED_WORKFLOWS=(deploy_for_backend deploy_for_go_backend deploy_for_full_app)
}

@test "все docker-workflow'ы формируют теги через docker-tags" {
  local wf
  for wf in "${TAGGED_WORKFLOWS[@]}" deploy_for_docker_container; do
    grep -qF "moogur/all-workflows/.github/actions/docker-tags@master" "$WF/$wf.yml" \
      || { echo "В $wf.yml теги собираются мимо docker-tags"; return 1; }
  done
}

@test "версия берётся из тега запуска, а не из git describe" {
  local wf
  for wf in "${TAGGED_WORKFLOWS[@]}"; do
    grep -qF "mode: \${{ github.ref_type == 'tag' && 'ref' || 'git' }}" "$WF/$wf.yml" \
      || { echo "В $wf.yml версия не привязана к тегу запуска"; return 1; }
  done
}

@test "semver действует только на сборку по тегу" {
  local wf
  for wf in "${TAGGED_WORKFLOWS[@]}"; do
    grep -qF "format_mode: \${{ github.ref_type == 'tag' && inputs.format_mode || 'date' }}" "$WF/$wf.yml" \
      || { echo "В $wf.yml пересборка без тега может переписать релизные теги"; return 1; }
  done
}

@test "образ пушится циклом по списку тегов" {
  local wf
  for wf in "${TAGGED_WORKFLOWS[@]}" deploy_for_docker_container; do
    grep -qF 'for ref in ${{ steps.tags.outputs.tags }}; do docker push "$ref"; done' "$WF/$wf.yml" \
      || { echo "В $wf.yml публикуются не все теги"; return 1; }
  done
}

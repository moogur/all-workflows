#!/usr/bin/env bats
# Guard-тесты релизных workflow'ов: единая цепочка github-release (tag-format →
# release-notes → publish-release), вызываемая только по тегу, и отсутствие
# удалённой инфраструктуры (release.yml, release_with_artifacts.yml, Release
# Drafter, notes_source).

setup() {
  load helpers
  ROOT="$(repo_root)"
  WF="$ROOT/.github/workflows"
  # Workflow'ы, которые напрямую вызывают github-release.
  DIRECT_RELEASE_WORKFLOWS=(deploy_for_build_application release_frontend go_build_with_artifacts publish_package deploy_for_lerna)
  # Docker-workflow'ы релизят через docker-image → docker-release → github-release
  # (проверено отдельно в tests/docker-workflows.bats).
  DOCKER_WORKFLOWS=(deploy_for_backend deploy_for_go_backend deploy_for_full_app deploy_for_docker_container)
}

@test "release.yml и release_with_artifacts.yml удалены" {
  [ ! -f "$WF/release.yml" ]
  [ ! -f "$WF/release_with_artifacts.yml" ]
}

@test "release-drafter.yml удалён" {
  [ ! -f "$ROOT/.github/release-drafter.yml" ]
}

@test "release-drafter нигде не используется" {
  run grep -rlF "release-drafter" "$ROOT/.github"
  [ "$status" -ne 0 ]
}

@test "notes_source нигде не осталось" {
  run grep -rlF "notes_source" "$ROOT/.github"
  [ "$status" -ne 0 ]
}

@test "все прямые релизные workflow'ы вызывают github-release" {
  for wf in "${DIRECT_RELEASE_WORKFLOWS[@]}"; do
    grep -qF "moogur/all-workflows/.github/actions/github-release@master" "$WF/$wf.yml" \
      || { echo "В $wf.yml нет github-release"; return 1; }
  done
}

@test "github-release вызывается только по тегу" {
  local wf line
  for wf in "${DIRECT_RELEASE_WORKFLOWS[@]}"; do
    line=$(grep -n "actions/github-release@master" "$WF/$wf.yml" | cut -d: -f1)
    sed -n "$((line - 1))p" "$WF/$wf.yml" | grep -qE "if: github\.ref_type == 'tag'" \
      || { echo "В $wf.yml github-release не закрыт условием github.ref_type == 'tag'"; return 1; }
  done
}

@test "github-release — единственный производственный вызывающий release-notes и publish-release" {
  run grep -rlF "actions/release-notes@master" "$ROOT/.github"
  [ "$output" = "$ROOT/.github/actions/github-release/action.yml" ]

  run grep -rlF "actions/publish-release@master" "$ROOT/.github"
  [ "$output" = "$ROOT/.github/actions/github-release/action.yml" ]
}

@test "tag-format вызывается только внутри github-release/docker-tags и как ранний фейл-фаст двух build-workflow'ов" {
  # release_frontend и deploy_for_build_application зовут его сами (до сборки),
  # github-release зовёт его же для самой публикации — источник правила один и тот же.
  run grep -rlF "actions/tag-format@master" "$WF"
  [ "$status" -eq 0 ]
  local expected
  expected=$(printf '%s\n' "$WF/deploy_for_build_application.yml" "$WF/release_frontend.yml" | sort)
  [ "$(printf '%s\n' "${lines[@]}" | sort)" = "$expected" ]
}

@test "ранний Check tag format в build-workflow'ах не дублирует regexp, а зовёт tag-format" {
  for wf in deploy_for_build_application release_frontend; do
    run awk '/Check tag format/,/version:/' "$WF/$wf.yml"
    [[ "$output" == *"actions/tag-format@master"* ]] \
      || { echo "В $wf.yml Check tag format не вызывает tag-format"; return 1; }
    [[ "$output" != *'=~'* ]] \
      || { echo "В $wf.yml Check tag format содержит собственный regexp"; return 1; }
  done
}

@test "заархивированные release-экшены нигде не используются" {
  run grep -rlE "uses: actions/(create-release|upload-release-asset)@" "$WF"
  [ "$status" -ne 0 ]   # grep -l: статус !=0 означает «совпадений нет»
}

@test "релизные npm-workflow'ы собирают блок через npm-package-notes" {
  for wf in publish_package deploy_for_lerna; do
    grep -qF "moogur/all-workflows/.github/actions/npm-package-notes@master" "$WF/$wf.yml" \
      || { echo "В $wf.yml нет npm-package-notes"; return 1; }
  done
}

@test "deploy_for_lerna определяет список пакетов до Publish packages" {
  # Неверная раскладка packages/*/package.json должна падать до lerna publish,
  # а не после — иначе публикация уже произошла, а релиз с ней нет.
  local file="$WF/deploy_for_lerna.yml"
  local determine_line publish_line
  determine_line=$(grep -n "Determine published packages" "$file" | cut -d: -f1)
  publish_line=$(grep -n '"Publish packages"' "$file" | cut -d: -f1)
  [ -n "$determine_line" ] && [ -n "$publish_line" ]
  [ "$determine_line" -lt "$publish_line" ]
}

@test "go_build_with_artifacts именует ассет релиза по goos/goarch" {
  grep -qE 'assets: \./\$\{\{ inputs\.projectname \}\}-\$\{\{ inputs\.goos \}\}-\$\{\{ inputs\.goarch \}\}\.tar\.gz' \
    "$WF/go_build_with_artifacts.yml"
}

@test "deploy_for_build_application без тега пропускает релиз целиком" {
  # Авто-деплой по расписанию собирает, но не релизит: версии из тега нет.
  local file="$WF/deploy_for_build_application.yml"
  for name in 'Determining the version' 'Publish release'; do
    run awk -v name="$name" '
      {
        line = $0
        sub(/^[[:space:]]*-?[[:space:]]*name:[[:space:]]*/, "", line)
        gsub(/^[\x27"]|[\x27"][[:space:]]*$/, "", line)
        if (line == name) { found = 1; next }
      }
      found && /if:/ { print; exit }
      found && /^ *- name:/ { exit }
    ' "$file"
    [[ "$output" == *"if: github.ref_type == 'tag'"* ]] \
      || { echo "Шаг '$name' не закрыт условием github.ref_type == 'tag'"; return 1; }
  done
}

@test "deploy_for_build_application берёт версию только из тега" {
  # git describe на коммите с несколькими тегами мог выбрать не тот — версия только mode: ref.
  grep -qE '^ +mode: ref$' "$WF/deploy_for_build_application.yml"
  run grep -F "github.ref_type == 'tag' && 'ref' || 'git'" "$WF/deploy_for_build_application.yml"
  [ "$status" -ne 0 ]
}

@test "docker-workflow'ы не вызывают github-release напрямую" {
  # Их вызывает docker-image → docker-release (см. tests/docker-workflows.bats).
  for wf in "${DOCKER_WORKFLOWS[@]}"; do
    run grep -qF "actions/github-release@master" "$WF/$wf.yml"
    [ "$status" -ne 0 ] || { echo "В $wf.yml github-release вызван напрямую, минуя docker-release"; return 1; }
  done
}

#!/usr/bin/env bats
# Guard-тесты релизных workflow'ов: два источника тела релиза (drafter по PR,
# commits по коммитам между тегами), общая публикация через publish-release
# и отсутствие заархивированных release-экшенов.

setup() {
  load helpers
  ROOT="$(repo_root)"
  WF="$ROOT/.github/workflows"
  # Workflow'ы, которые сами создают релиз.
  RELEASE_WORKFLOWS=(release release_frontend deploy_for_build_application)
  # Из них — те, у кого drafter стоит источником по умолчанию.
  DRAFTER_DEFAULT_WORKFLOWS=(release release_frontend release_with_artifacts)
}

# default_of <файл> — значение default у input notes_source.
# Ключ ищется с отступом: notes_source упоминается и в шапке-комментарии workflow.
default_of() {
  awk '/^[[:space:]]+notes_source:/ { found = 1 } found && /default:/ { print $2; exit }' "$1"
}

@test "источник тела релиза по умолчанию — drafter" {
  # Потребители с PR-флоу не должны заметить появления режима commits.
  for wf in "${DRAFTER_DEFAULT_WORKFLOWS[@]}"; do
    [ "$(default_of "$WF/$wf.yml")" = "'drafter'" ] || { echo "В $wf.yml дефолт не drafter"; return 1; }
  done
}

@test "deploy_for_build_application по умолчанию оставляет тело пустым" {
  # Драфтер у него появился позже, поэтому дефолт — прежнее поведение.
  [ "$(default_of "$WF/deploy_for_build_application.yml")" = "'none'" ]
}

@test "deploy_for_build_application просит права под Release Drafter" {
  # Вызванный workflow не может просить больше вызвавшего, поэтому право нужно и у auto_deploy.
  grep -qE '^  pull-requests: read' "$WF/deploy_for_build_application.yml"
  grep -qE '^  pull-requests: read' "$WF/auto_deploy_for_build_application.yml"
}

@test "режим commits забирает полную историю тегов" {
  for wf in release release_frontend; do
    # Строки, а не числа: 0 в выражении GitHub ложно, и условие всегда дало бы 1.
    grep -qF "inputs.notes_source == 'commits' && '0' || '1'" "$WF/$wf.yml" \
      || { echo "В $wf.yml нет условной глубины checkout"; return 1; }
  done
  # Полная история остаётся не только ради версии: нужна и пользовательскому
  # скрипту сборки, и release-notes в режиме commits.
  grep -qF 'fetch-depth: 0' "$WF/deploy_for_build_application.yml"
}

@test "все релизные workflow'ы публикуют через общий action" {
  for wf in "${RELEASE_WORKFLOWS[@]}"; do
    grep -qF "moogur/all-workflows/.github/actions/publish-release@master" "$WF/$wf.yml" \
      || { echo "В $wf.yml нет publish-release"; return 1; }
  done
}

@test "тело в режиме commits считает общий action" {
  for wf in "${RELEASE_WORKFLOWS[@]}"; do
    grep -qF "moogur/all-workflows/.github/actions/release-notes@master" "$WF/$wf.yml" \
      || { echo "В $wf.yml нет release-notes"; return 1; }
  done
}

@test "заархивированные release-экшены больше нигде не используются" {
  run grep -rlE "uses: actions/(create-release|upload-release-asset)@" "$WF"
  [ "$status" -ne 0 ]   # grep -l: статус !=0 означает «совпадений нет»
}

@test "в режиме drafter тег для ассетов берётся из вывода release-drafter" {
  # tag-template драфтера может разойтись с именем тега в репозитории (1.2.3 -> v1.2.3).
  for wf in "${RELEASE_WORKFLOWS[@]}"; do
    grep -qF "steps.create_release.outputs.tag_name ||" "$WF/$wf.yml" \
      || { echo "В $wf.yml тег ассетов не из вывода драфтера"; return 1; }
  done
}

@test "драфтер вешает релиз на тег как есть, без своей версии" {
  # version драфтер приводит к semver и tag-template добавляет v: 14.03.2026 стал бы v14.3.2026.
  for wf in "${RELEASE_WORKFLOWS[@]}"; do
    run awk '/release-drafter\/release-drafter@/ { found = 1 } found && /^ *version:/ { print; exit }' "$WF/$wf.yml"
    [ -z "$output" ] || { echo "В $wf.yml драфтеру передаётся version"; return 1; }
    grep -qE '^ +tag: \$\{\{ (github\.ref_name|steps\.version\.outputs\.version) \}\}$' "$WF/$wf.yml" \
      || { echo "В $wf.yml драфтеру не передан tag"; return 1; }
  done
}

@test "deploy_for_build_application берёт версию только из тега" {
  # git describe на коммите с несколькими тегами мог выбрать не тот — теперь без него.
  grep -qE '^ +mode: ref$' "$WF/deploy_for_build_application.yml"
  run grep -F "github.ref_type == 'tag' && 'ref' || 'git'" "$WF/deploy_for_build_application.yml"
  [ "$status" -ne 0 ]
}

@test "deploy_for_build_application без тега пропускает релиз целиком" {
  # Авто-деплой по расписанию собирает, но не релизит: версии из тега больше нет.
  local file="$WF/deploy_for_build_application.yml"
  for name in 'Determining the version' 'Check tag format' 'Publish release (drafter)' 'Release notes' 'Publish release'; do
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

@test "в режиме drafter заголовок существующего релиза не перетирается" {
  # Пустая строка в выражении GitHub ложна, поэтому условие пишется через отрицание.
  grep -qF "inputs.notes_source != 'drafter' && format('Release {0}'" "$WF/deploy_for_build_application.yml"
}

@test "в release.yml один шаг публикации на оба режима" {
  # Ветки drafter и commits взаимоисключающие, а публикация после них общая.
  [ "$(grep -cF "actions/publish-release@master" "$WF/release.yml")" -eq 1 ]
  grep -qF "if: inputs.notes_source == 'drafter'" "$WF/release.yml"
  grep -qF "if: inputs.notes_source == 'commits'" "$WF/release.yml"
}

@test "ассет подключается только когда артефакт запрошен" {
  grep -qF "if: inputs.artifact != ''" "$WF/release.yml"
  grep -qF "assets: \${{ inputs.artifact != '' &&" "$WF/release.yml"
}

@test "release_with_artifacts — тонкая обёртка над release.yml" {
  # Своих шагов у неё быть не должно: тело живёт в release.yml.
  grep -qF "uses: ./.github/workflows/release.yml" "$WF/release_with_artifacts.yml"
  run grep -qE '^ +steps:' "$WF/release_with_artifacts.yml"
  [ "$status" -ne 0 ]
}

@test "все релизные workflow'ы проверяют формат тега до релиза" {
  for wf in "${RELEASE_WORKFLOWS[@]}"; do
    grep -qF "moogur/all-workflows/.github/actions/tag-format@master" "$WF/$wf.yml" \
      || { echo "В $wf.yml нет проверки формата тега"; return 1; }
  done
}

@test "release-drafter остаётся источником для PR-флоу" {
  for wf in "${RELEASE_WORKFLOWS[@]}"; do
    grep -qF "release-drafter/release-drafter@" "$WF/$wf.yml" \
      || { echo "В $wf.yml нет release-drafter"; return 1; }
  done
}

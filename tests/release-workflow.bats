#!/usr/bin/env bats
# Guard-тесты: фиксируют конфигурацию релизных workflow'ов — два источника тела
# релиза (drafter по PR, commits по коммитам между тегами), общую публикацию
# через publish-release и отсутствие заархивированных release-экшенов.

setup() {
  load helpers
  ROOT="$(repo_root)"
  WF="$ROOT/.github/workflows"
  # Workflow'ы, которые создают релиз.
  RELEASE_WORKFLOWS=(release release_frontend release_with_artifacts deploy_for_build_application)
  # Из них — те, у кого drafter стоит источником по умолчанию.
  DRAFTER_DEFAULT_WORKFLOWS=(release release_frontend release_with_artifacts)
  # Те, что прикладывают ассеты к релизу и потому берут тег у создателя релиза.
  ASSET_WORKFLOWS=(release_frontend release_with_artifacts deploy_for_build_application)
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
  for wf in "${DRAFTER_DEFAULT_WORKFLOWS[@]}"; do
    # Строки, а не числа: 0 в выражении GitHub ложно, и условие всегда дало бы 1.
    grep -qF "inputs.notes_source == 'commits' && '0' || '1'" "$WF/$wf.yml" \
      || { echo "В $wf.yml нет условной глубины checkout"; return 1; }
  done
  # Этому и без релиза нужна история: версия берётся через git describe.
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
  for wf in "${ASSET_WORKFLOWS[@]}"; do
    grep -qF "steps.create_release.outputs.tag_name ||" "$WF/$wf.yml" \
      || { echo "В $wf.yml тег ассетов не из вывода драфтера"; return 1; }
  done
}

@test "в режиме drafter заголовок существующего релиза не перетирается" {
  # Пустая строка в выражении GitHub ложна, поэтому условие пишется через отрицание.
  grep -qF "inputs.notes_source != 'drafter' && format('Release {0}'" "$WF/deploy_for_build_application.yml"
}

@test "оба шага публикации в release.yml стоят под взаимоисключающими условиями" {
  [ "$(grep -cF "if: inputs.notes_source == 'drafter'" "$WF/release.yml")" -eq 2 ]
  [ "$(grep -cF "if: inputs.notes_source == 'commits'" "$WF/release.yml")" -eq 2 ]
}

@test "release-drafter остаётся источником для PR-флоу" {
  for wf in "${RELEASE_WORKFLOWS[@]}"; do
    grep -qF "release-drafter/release-drafter@v6" "$WF/$wf.yml" \
      || { echo "В $wf.yml нет release-drafter"; return 1; }
  done
}

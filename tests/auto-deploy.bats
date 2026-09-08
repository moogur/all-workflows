#!/usr/bin/env bats
# Guard-тесты авто-деплоя: фиксируют, что «последняя увиденная» версия
# сохраняется только после успешного деплоя, что вложенный деплой получает
# секреты и что проверка обновления живёт в общем composite action.

setup() {
  load helpers
  ROOT="$(repo_root)"
  WF="$ROOT/.github/workflows"
  AUTO_WORKFLOWS=(auto_deploy_for_docker_container auto_deploy_for_build_application)
}

@test "переменная сохраняется отдельным job'ом после деплоя" {
  for wf in "${AUTO_WORKFLOWS[@]}"; do
    grep -qF "needs: [checking_to_use_the_latest_version, auto_deploy]" "$WF/$wf.yml" \
      || { echo "В $wf.yml сохранение версии не зависит от результата деплоя"; return 1; }
  done
}

@test "job проверки не обновляет переменную" {
  for wf in "${AUTO_WORKFLOWS[@]}"; do
    # Запись идёт через action, и только в job'е сохранения.
    [ "$(grep -cF 'save-update-value@master' "$WF/$wf.yml")" -eq 1 ] \
      || { echo "В $wf.yml не один вызов save-update-value"; return 1; }
  done
}

@test "вложенный вызов деплоя наследует секреты" {
  for wf in "${AUTO_WORKFLOWS[@]}"; do
    grep -qF "secrets: inherit" "$WF/$wf.yml" \
      || { echo "В $wf.yml вложенный деплой без secrets: inherit"; return 1; }
  done
}

@test "проверка обновления вынесена в общий action" {
  for wf in "${AUTO_WORKFLOWS[@]}"; do
    grep -qF "moogur/all-workflows/.github/actions/remote-update-check@master" "$WF/$wf.yml" \
      || { echo "В $wf.yml нет action remote-update-check"; return 1; }
  done
}

@test "auto-workflow'ы не делают лишний checkout" {
  for wf in "${AUTO_WORKFLOWS[@]}"; do
    run grep -qF "actions/checkout@" "$WF/$wf.yml"
    [ "$status" -ne 0 ] || { echo "В $wf.yml остался ненужный checkout"; return 1; }
  done
}

@test "метка авто-сборки содержит время и берётся в UTC" {
  grep -qF 'date -u +"%d.%m.%Y-%H%M-auto"' "$WF/deploy_for_docker_container.yml"
}

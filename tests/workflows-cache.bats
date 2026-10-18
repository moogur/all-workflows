#!/usr/bin/env bats
# Guard-тесты кэширования npm. Правило: кэш живёт только внутри action npm-install.
# Он кэширует node_modules по точному ключу (ОС + версия Node + хэш lock-файла) и
# пропускает npm ci лишь при точном попадании. Смена ABI (версии Node) или lock-файла
# даёт промах, и тогда выполняется чистый npm ci. Поэтому workflow'ы не вызывают
# actions/cache сами, не пропускают шаги по cache-hit и не запускают npm ci напрямую,
# а у npm-install нет restore-keys (частичное попадание подсунуло бы чужой node_modules).

setup() {
  load helpers
  ROOT="$(repo_root)"
  WF="$ROOT/.github/workflows"
  NPM_WORKFLOWS="actions_for_push pr_annotation publish_package release_frontend deploy_for_frontend deploy_for_static_site deploy_for_lerna"
}

@test "ни один workflow не использует actions/cache напрямую" {
  run grep -rlF "uses: actions/cache@" "$WF"
  [ "$status" -ne 0 ]   # grep -l: статус !=0 означает «совпадений нет»
}

@test "ни один workflow не пропускает шаги по cache-hit" {
  run grep -rlF "cache-hit" "$WF"
  [ "$status" -ne 0 ]
}

@test "ни один workflow не запускает npm ci напрямую" {
  run grep -rnE "^\s*(- )?run: .*npm ci" "$WF"
  [ "$status" -ne 0 ]
}

@test "npm-workflow'ы используют общий action npm-install" {
  for wf in $NPM_WORKFLOWS; do
    grep -qF "moogur/all-workflows/.github/actions/npm-install@master" "$WF/$wf.yml" \
      || { echo "В $wf.yml нет npm-install action"; return 1; }
  done
}

@test "npm-workflow'ы используют общий action setup-node" {
  for wf in $NPM_WORKFLOWS; do
    grep -qF "moogur/all-workflows/.github/actions/setup-node@master" "$WF/$wf.yml" \
      || { echo "В $wf.yml нет setup-node action"; return 1; }
  done
}

@test "npm-install стоит после npm-auth в каждом npm-workflow" {
  local auth install
  for wf in $NPM_WORKFLOWS; do
    auth=$(grep -nF "actions/npm-auth@master" "$WF/$wf.yml" | head -n1 | cut -d: -f1)
    install=$(grep -nF "actions/npm-install@master" "$WF/$wf.yml" | head -n1 | cut -d: -f1)
    { [ -n "$auth" ] && [ -n "$install" ] && [ "$install" -gt "$auth" ]; } \
      || { echo "В $wf.yml npm-install не после npm-auth"; return 1; }
  done
}

@test "setup-node больше не включает кэш npm" {
  run grep -E "cache: npm|cache-dependency-path" "$ROOT/.github/actions/setup-node/action.yml"
  [ "$status" -ne 0 ]
}

@test "npm-install не использует restore-keys" {
  run grep -F "restore-keys" "$ROOT/.github/actions/npm-install/action.yml"
  [ "$status" -ne 0 ]
}

@test "npm-install ставит зависимости только при промахе кэша" {
  grep -qF "steps.modules.outputs.cache-hit != 'true'" "$ROOT/.github/actions/npm-install/action.yml"
}

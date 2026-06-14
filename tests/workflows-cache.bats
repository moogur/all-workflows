#!/usr/bin/env bats
# Guard-тесты: фиксируют переход на идиоматичное кэширование npm
# (setup-node с cache: 'npm' + всегда npm ci) и запрещают возврат
# к кэшированию каталога node_modules с пропуском установки.

setup() {
  load helpers
  ROOT="$(repo_root)"
  WF="$ROOT/.github/workflows"
}

@test "ни один workflow не кэширует каталог node_modules" {
  run grep -rlF "path: '**/node_modules'" "$WF"
  [ "$status" -ne 0 ]   # grep -l: статус !=0 означает «совпадений нет»
}

@test "ни один workflow не пропускает шаги по cache-hit" {
  run grep -rlF "steps.cache.outputs.cache-hit" "$WF"
  [ "$status" -ne 0 ]
}

@test "ни один workflow не использует actions/cache напрямую" {
  run grep -rlF "uses: actions/cache@" "$WF"
  [ "$status" -ne 0 ]
}

@test "action setup-node включает кэш npm" {
  grep -qF "cache: npm" "$ROOT/.github/actions/setup-node/action.yml"
}

@test "npm-workflow'ы используют общий action setup-node" {
  for wf in actions_for_push pr_annotation publish_package release_frontend deploy_for_frontend deploy_for_lerna; do
    grep -qF "moogur/all-workflows/.github/actions/setup-node@master" "$WF/$wf.yml" \
      || { echo "В $wf.yml нет setup-node action"; return 1; }
  done
}

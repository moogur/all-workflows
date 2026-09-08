#!/usr/bin/env bats
# Тесты для .github/actions/save-update-value/save.sh
# gh подменяется заглушкой: проверяем, какие вызовы API делает скрипт.

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/save-update-value/save.sh"
  TMP="$(mktemp -d)"
  GH_LOG="$TMP/gh.log"
  : > "$GH_LOG"
}

teardown() {
  rm -rf "$TMP"
}

# Заглушка gh: пишет аргументы в лог и возвращает заданные коды для PATCH/POST.
make_gh_stub() {
  local patch_status="$1"
  local post_status="${2:-0}"
  mkdir -p "$TMP/bin"
  {
    echo '#!/usr/bin/env bash'
    echo "echo \"\$*\" >> '$GH_LOG'"
    echo "if [[ \"\$*\" == *PATCH* ]]; then exit $patch_status; fi"
    echo "exit $post_status"
  } > "$TMP/bin/gh"
  chmod +x "$TMP/bin/gh"
}

run_save() {
  run env PATH="$TMP/bin:$PATH" \
    OWNER=moogur REPO=adminer ENVIRONMENT=DEPLOY \
    VARIABLE_NAME=LAST_UPDATE_VALUE VARIABLE_VALUE=4.8.1 GH_TOKEN=token \
    bash "$SCRIPT"
}

@test "существующая переменная обновляется одним PATCH" {
  make_gh_stub 0
  run_save
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$GH_LOG")" -eq 1 ]
  grep -qF "PATCH" "$GH_LOG"
  grep -qF "repos/moogur/adminer/environments/DEPLOY/variables/LAST_UPDATE_VALUE" "$GH_LOG"
  grep -qF "value=4.8.1" "$GH_LOG"
}

@test "отсутствующая переменная создаётся через POST" {
  make_gh_stub 1 0
  run_save
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$GH_LOG")" -eq 2 ]
  grep -qF "POST" "$GH_LOG"
  # POST идёт в коллекцию, без имени переменной в пути
  grep -qE "POST .*repos/moogur/adminer/environments/DEPLOY/variables( |$)" "$GH_LOG"
}

@test "успешный PATCH не приводит к POST" {
  make_gh_stub 0
  run_save
  run grep -cF "POST" "$GH_LOG"
  [ "$output" = "0" ]
}

@test "падение и PATCH, и POST завершается с ошибкой" {
  make_gh_stub 1 1
  run_save
  [ "$status" -ne 0 ]
}

@test "без обязательных переменных окружения завершается с ошибкой" {
  make_gh_stub 0
  run env PATH="$TMP/bin:$PATH" OWNER=moogur bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

#!/usr/bin/env bats
# Тесты для .github/actions/run-build-script/run.sh: проверка пути к скрипту сборки
# перед source (workflow deploy_for_build_application).

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/run-build-script/run.sh"
  TMP="$(mktemp -d)"
  WS="$(cd "$TMP" && pwd -P)/ws"
  mkdir -p "$WS/scripts" "$TMP/outside"
  printf 'touch "$PWD/ran"\n' > "$WS/scripts/build.sh"
  printf 'touch "%s/outside-ran"\n' "$TMP" > "$TMP/outside/evil.sh"
}

teardown() {
  rm -rf "$TMP"
}

# Запуск из workspace, как на раннере.
run_script() {
  cd "$WS"
  run env FILE_PATH="$1" GITHUB_WORKSPACE="$WS" bash "$SCRIPT"
}

@test "относительный путь внутри workspace: скрипт выполняется" {
  run_script "scripts/build.sh"
  [ "$status" -eq 0 ]
  [ -e "$WS/ran" ]
}

@test "путь с ./ допустим" {
  run_script "./scripts/build.sh"
  [ "$status" -eq 0 ]
  [ -e "$WS/ran" ]
}

@test "скрипт выполняется в оболочке с текущим каталогом workspace, а не по PATH" {
  printf 'echo "$PWD" > "$PWD/cwd"\n' > "$WS/build.sh"
  run_script "build.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$WS/cwd")" = "$WS" ]
}

@test "падение пользовательского скрипта даёт ненулевой код" {
  printf 'exit 7\n' > "$WS/scripts/fail.sh"
  run_script "scripts/fail.sh"
  [ "$status" -eq 7 ]
}

@test "пустой путь отвергается" {
  run_script ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"file_path is empty"* ]]
}

@test "абсолютный путь отвергается, скрипт не выполняется" {
  run_script "$TMP/outside/evil.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be relative"* ]]
  [ ! -e "$TMP/outside-ran" ]
}

@test "сегмент .. в начале отвергается" {
  run_script "../outside/evil.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"'..'"* ]]
  [ ! -e "$TMP/outside-ran" ]
}

@test "сегмент .. в середине отвергается даже если путь остаётся внутри" {
  run_script "scripts/../scripts/build.sh"
  [ "$status" -ne 0 ]
  [ ! -e "$WS/ran" ]
}

@test "имя файла с двумя точками (не сегмент ..) допустимо" {
  printf 'touch "$PWD/ran"\n' > "$WS/scripts/a..b.sh"
  run_script "scripts/a..b.sh"
  [ "$status" -eq 0 ]
  [ -e "$WS/ran" ]
}

@test "несуществующий файл отвергается" {
  run_script "scripts/missing.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not an existing regular file"* ]]
}

@test "каталог вместо файла отвергается" {
  run_script "scripts"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not an existing regular file"* ]]
}

@test "симлинк на файл вне workspace отвергается" {
  ln -s "$TMP/outside/evil.sh" "$WS/scripts/link.sh"
  run_script "scripts/link.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the workspace"* ]]
  [ ! -e "$TMP/outside-ran" ]
}

@test "симлинк на каталог вне workspace отвергается" {
  ln -s "$TMP/outside" "$WS/linkdir"
  run_script "linkdir/evil.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the workspace"* ]]
  [ ! -e "$TMP/outside-ran" ]
}

@test "симлинк на файл внутри workspace допустим" {
  ln -s build.sh "$WS/scripts/link.sh"
  run_script "scripts/link.sh"
  [ "$status" -eq 0 ]
  [ -e "$WS/ran" ]
}

@test "метасимволы оболочки в пути не выполняются" {
  run_script "x; touch $TMP/pwned; #"
  [ "$status" -ne 0 ]
  [ ! -e "$TMP/pwned" ]
}

@test "путь с пробелом и \$(...) трактуется как имя файла" {
  printf 'touch "$PWD/ran"\n' > "$WS/scripts/my build.sh"
  run_script "scripts/my build.sh"
  [ "$status" -eq 0 ]
  [ -e "$WS/ran" ]
  run_script "\$(touch $TMP/pwned).sh"
  [ "$status" -ne 0 ]
  [ ! -e "$TMP/pwned" ]
}

# ---------- guard: workflow ходит только через проверяющий action ----------

@test "deploy_for_build_application выполняет file_path только через run-build-script" {
  local wf="$ROOT/.github/workflows/deploy_for_build_application.yml"
  grep -q 'actions/run-build-script@master' "$wf"
  # Нет собственного source/запуска file_path в run.
  run bash -c "grep -vE '^[[:space:]]*#' '$wf' | grep -E '^[[:space:]]*(\\. |source )'"
  [ "$status" -ne 0 ]
}

@test "action run-build-script получает путь через env, а не через run" {
  local act="$ROOT/.github/actions/run-build-script/action.yml"
  grep -q 'FILE_PATH: \${{ inputs.file_path }}' "$act"
  grep -q 'run: bash "\$GITHUB_ACTION_PATH/run.sh"' "$act"
}

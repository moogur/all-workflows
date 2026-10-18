#!/usr/bin/env bats
# Тесты для .github/actions/npm-install/key.sh

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/npm-install/key.sh"
  TMP="$(mktemp -d)"
  export GITHUB_OUTPUT="$TMP/output"
  : > "$GITHUB_OUTPUT"
  mkdir -p "$TMP/bin"
  set_node v20.11.0
  printf '{"lock":1}\n' > "$TMP/package-lock.json"
}

teardown() {
  rm -rf "$TMP"
}

# Подменяет node в PATH: node --version печатает $1.
set_node() {
  printf '#!/usr/bin/env bash\necho "%s"\n' "$1" > "$TMP/bin/node"
  chmod +x "$TMP/bin/node"
}

# Значение многострочного output path (между path<<DELIM и DELIM).
path_lines() {
  awk '/^path<</{d=substr($0,7); on=1; next} on&&$0==d{on=0} on' "$GITHUB_OUTPUT"
}

# Создаёт каталоги workspace'ов в $TMP/$1 (относительно корня проекта).
mkdirs() { (cd "$TMP" && mkdir -p "$@"); }

# Запускает скрипт в $TMP; $1 — путь к lock-файлу, $2 — RUNNER_OS.
run_key() {
  : > "$GITHUB_OUTPUT"
  run env PATH="$TMP/bin:$PATH" RUNNER_OS="${2:-Linux}" LOCK_FILE="$1" \
    GITHUB_OUTPUT="$GITHUB_OUTPUT" bash -c "cd '$TMP' && bash '$SCRIPT'"
}

@test "одинаковые ОС, Node и lock дают одинаковый ключ" {
  run_key package-lock.json
  first="$(output_value key)"
  run_key package-lock.json
  [ "$status" -eq 0 ]
  [ "$(output_value key)" = "$first" ]
}

@test "ключ содержит ОС, версию Node и sha256 lock-файла" {
  run_key package-lock.json
  [ "$status" -eq 0 ]
  hash="$(shasum -a 256 "$TMP/package-lock.json" | cut -d' ' -f1)"
  [ "$(output_value key)" = "Linux-node_modules-v20.11.0-$hash" ]
}

@test "смена версии Node меняет ключ" {
  run_key package-lock.json
  first="$(output_value key)"
  set_node v22.1.0
  run_key package-lock.json
  [ "$status" -eq 0 ]
  [ "$(output_value key)" != "$first" ]
}

@test "смена содержимого lock-файла меняет ключ" {
  run_key package-lock.json
  first="$(output_value key)"
  printf '{"lock":2}\n' > "$TMP/package-lock.json"
  run_key package-lock.json
  [ "$status" -eq 0 ]
  [ "$(output_value key)" != "$first" ]
}

@test "смена ОС меняет ключ" {
  run_key package-lock.json Linux
  first="$(output_value key)"
  run_key package-lock.json macOS
  [ "$status" -eq 0 ]
  [ "$(output_value key)" != "$first" ]
}

@test "path и dir указывают рядом с lock-файлом в корне" {
  run_key package-lock.json
  [ "$(path_lines)" = "./node_modules" ]
  [ "$(output_value dir)" = "." ]
}

@test "path и dir указывают рядом с lock-файлом во вложенном каталоге" {
  mkdir -p "$TMP/frontend"
  printf '{}\n' > "$TMP/frontend/package-lock.json"
  run_key frontend/package-lock.json
  [ "$status" -eq 0 ]
  [ "$(path_lines)" = "frontend/node_modules" ]
  [ "$(output_value dir)" = "frontend" ]
}

@test "отсутствие lock-файла — ошибка с понятным сообщением и без вывода" {
  run_key missing/package-lock.json
  [ "$status" -ne 0 ]
  [[ "$output" == *"Lock-файл не найден: missing/package-lock.json"* ]]
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "package.json без workspaces — один путь" {
  printf '{"name":"x"}\n' > "$TMP/package.json"
  mkdirs packages/a
  run_key package-lock.json
  [ "$status" -eq 0 ]
  [ "$(path_lines)" = "./node_modules" ]
}

@test "workspaces-массив с glob — корень и каждый найденный пакет" {
  printf '{"workspaces":["packages/*"]}\n' > "$TMP/package.json"
  mkdirs packages/a packages/b
  touch "$TMP/packages/file.txt"
  run_key package-lock.json
  [ "$status" -eq 0 ]
  [ "$(path_lines)" = $'./node_modules\n./packages/a/node_modules\n./packages/b/node_modules' ]
}

@test "workspaces в форме объекта packages" {
  printf '{"workspaces":{"packages":["libs/*","tools/cli"]}}\n' > "$TMP/package.json"
  mkdirs libs/core tools/cli
  run_key package-lock.json
  [ "$status" -eq 0 ]
  [ "$(path_lines)" = $'./node_modules\n./libs/core/node_modules\n./tools/cli/node_modules' ]
}

@test "glob без совпадений — только корневой node_modules" {
  printf '{"workspaces":["packages/*"]}\n' > "$TMP/package.json"
  run_key package-lock.json
  [ "$status" -eq 0 ]
  [ "$(path_lines)" = "./node_modules" ]
}

@test "workspaces раскрываются относительно каталога lock-файла" {
  mkdirs app/packages/a
  printf '{}\n' > "$TMP/app/package-lock.json"
  printf '{"workspaces":["packages/*"]}\n' > "$TMP/app/package.json"
  run_key app/package-lock.json
  [ "$status" -eq 0 ]
  [ "$(path_lines)" = $'app/node_modules\napp/packages/a/node_modules' ]
}

@test "ключ не зависит от workspaces" {
  run_key package-lock.json
  first="$(output_value key)"
  printf '{"workspaces":["packages/*"]}\n' > "$TMP/package.json"
  mkdirs packages/a
  run_key package-lock.json
  [ "$(output_value key)" = "$first" ]
}

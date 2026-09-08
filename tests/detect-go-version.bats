#!/usr/bin/env bats
# Тесты для .github/actions/detect-go-version/detect.sh

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/detect-go-version/detect.sh"
  TMP="$(mktemp -d)"
  export GITHUB_OUTPUT="$TMP/output"
  : > "$GITHUB_OUTPUT"
}

teardown() {
  rm -rf "$TMP"
}

# Записывает go.mod и запускает скрипт в каталоге $TMP.
detect_with() {
  printf '%s' "$1" > "$TMP/go.mod"
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" bash -c "cd '$TMP' && bash '$SCRIPT'"
}

@test "версия из директивы go (с патчем)" {
  detect_with 'module example.com/x

go 1.22.0

require ()
'
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "1.22.0" ]
}

@test "версия без патча (major.minor)" {
  detect_with 'module example.com/x

go 1.21
'
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "1.21" ]
}

@test "патч-версия" {
  detect_with 'module example.com/x

go 1.21.5
'
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "1.21.5" ]
}

@test "берёт первую директиву go, игнорируя require-блок" {
  detect_with 'module example.com/x

go 1.21

require (
	golang.org/x/tools v0.1.0
)
'
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "1.21" ]
}

@test "строка toolchain не перебивает директиву go" {
  detect_with 'module example.com/x

go 1.22.0

toolchain go1.22.3
'
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "1.22.0" ]
}

@test "директива go не на первой строке файла" {
  detect_with 'module example.com/x

require golang.org/x/sys v0.1.0

go 1.20
'
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "1.20" ]
}

@test "отсутствие директивы go — ошибка с сообщением" {
  # Раньше пустая версия молча уезжала в setup-go.
  detect_with 'module example.com/x

require golang.org/x/sys v0.1.0
'
  [ "$status" -ne 0 ]
  [[ "$output" == *"go directive is not found"* ]]
}

#!/usr/bin/env bats
# Тесты для .github/actions/npm-package-notes/notes.sh

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/npm-package-notes/notes.sh"
  TMP="$(mktemp -d)"
  export GITHUB_OUTPUT="$TMP/output"
  : > "$GITHUB_OUTPUT"
}

teardown() {
  rm -rf "$TMP"
}

run_notes() {
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" PACKAGES="$1" bash "$SCRIPT"
}

# notes_output — многострочное значение "notes" из $GITHUB_OUTPUT.
notes_output() {
  awk '/^notes<</ { flag=1; next } flag && $0 ~ /^notes_[0-9]+$/ { exit } flag { print }' "$GITHUB_OUTPUT"
}

@test "один пакет: одна команда npm install" {
  run_notes '@moogur/lib@1.2.3'
  [ "$status" -eq 0 ]
  [ "$(notes_output | head -n1)" = '## 📦 npm package' ]
  notes_output | grep -qF 'npm install @moogur/lib@1.2.3'
}

@test "несколько пакетов: команда на каждый, в одном код-блоке" {
  run_notes $'@moogur/a@1.0.0\n@moogur/b@2.0.0'
  [ "$status" -eq 0 ]
  notes_output | grep -qF 'npm install @moogur/a@1.0.0'
  notes_output | grep -qF 'npm install @moogur/b@2.0.0'
  [ "$(notes_output | grep -cF '```')" -eq 2 ]
}

@test "пустые строки в списке пропускаются" {
  run_notes $'@moogur/a@1.0.0\n\n@moogur/b@2.0.0\n'
  [ "$status" -eq 0 ]
  [ "$(notes_output | grep -cF 'npm install')" -eq 2 ]
}

@test "без PACKAGES завершается с ошибкой" {
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PACKAGES is required"* ]]
}

@test "PACKAGES из одних пробелов/переводов строк — ошибка, а не пустой блок" {
  run_notes $'  \n\n  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"no non-empty entries"* ]]
}

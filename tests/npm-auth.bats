#!/usr/bin/env bats
# Тесты для .github/actions/npm-auth/configure.sh

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/npm-auth/configure.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

run_with() {  # token, [subdir]
  local dir="$TMP${2:+/$2}"
  mkdir -p "$dir"
  run env NODE_AUTH_TOKEN="$1" bash -c "cd '$dir' && bash '$SCRIPT'"
  NPMRC="$dir/.npmrc"
}

@test "создаёт .npmrc с реестром и токеном" {
  run_with secret123
  [ "$status" -eq 0 ]
  [ -f "$NPMRC" ]
  grep -qx '@moogur:registry=https://npm.pkg.github.com/' "$NPMRC"
  grep -qx '//npm.pkg.github.com/:_authToken=secret123' "$NPMRC"
}

@test ".npmrc содержит ровно две строки" {
  run_with abc
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$NPMRC")" -eq 2 ]
}

@test "токен со спецсимволами записывается дословно" {
  run_with 'ghp_AbC123/xy+z='
  [ "$status" -eq 0 ]
  grep -qx '//npm.pkg.github.com/:_authToken=ghp_AbC123/xy+z=' "$NPMRC"
}

@test "работает во вложенном каталоге (frontend)" {
  run_with tok frontend
  [ "$status" -eq 0 ]
  [ -f "$TMP/frontend/.npmrc" ]
  grep -qx '//npm.pkg.github.com/:_authToken=tok' "$TMP/frontend/.npmrc"
}

@test "повторный запуск идемпотентен (две строки, без дублей)" {
  run_with first
  run env NODE_AUTH_TOKEN=second bash -c "cd '$TMP' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$TMP/.npmrc")" -eq 2 ]
  grep -qx '//npm.pkg.github.com/:_authToken=second' "$TMP/.npmrc"
}

@test "первая строка — реестр scope @moogur" {
  run_with tok
  [ "$(head -n1 "$NPMRC")" = '@moogur:registry=https://npm.pkg.github.com/' ]
}

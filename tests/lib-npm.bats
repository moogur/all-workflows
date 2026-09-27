#!/usr/bin/env bats
# Тесты для lib/npm.sh: "имя@версия" из package.json, приватные пакеты исключаются.

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/lib/npm.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

write_package() {
  local file="$1" json="$2"
  echo "$json" > "$file"
}

sh() {
  run bash -c "source '$LIB'; $*"
}

@test "package_ref: имя@версия из обычного package.json" {
  write_package "$TMP/package.json" '{"name":"@moogur/lib","version":"1.2.3"}'
  sh "npm_package_ref '$TMP/package.json'"
  [ "$status" -eq 0 ]
  [ "$output" = "@moogur/lib@1.2.3" ]
}

@test "package_ref: приватный пакет (private: true) отдаёт пустую строку" {
  write_package "$TMP/package.json" '{"name":"@moogur/lib","version":"1.2.3","private":true}'
  sh "npm_package_ref '$TMP/package.json'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "package_ref: private: false — как обычный пакет" {
  write_package "$TMP/package.json" '{"name":"@moogur/lib","version":"1.2.3","private":false}'
  sh "npm_package_ref '$TMP/package.json'"
  [ "$output" = "@moogur/lib@1.2.3" ]
}

@test "package_ref: несуществующий файл завершается с ошибкой" {
  sh "npm_package_ref '$TMP/no-such-file.json'"
  [ "$status" -ne 0 ]
}

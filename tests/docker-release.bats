#!/usr/bin/env bats
# Тесты для .github/actions/docker-release/image-notes.sh
# Скрипт печатает блок про образ в $GITHUB_OUTPUT (notes) — сам он ничего не
# дописывает в файл тела релиза, это делает github-release@append-notes.sh.
# Композитная цепочка (image-notes.sh → github-release) guard-тестами не
# проверяется: она собрана из уже покрытых экшенов.

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/docker-release/image-notes.sh"
  TMP="$(mktemp -d)"
  export GITHUB_OUTPUT="$TMP/output"
  : > "$GITHUB_OUTPUT"
}

teardown() {
  rm -rf "$TMP"
}

run_notes() {
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" "$@" bash "$SCRIPT"
}

# notes_output — многострочное значение "notes" из $GITHUB_OUTPUT (между <<delim и delim).
notes_output() {
  awk '/^notes<</ { flag=1; next } flag && $0 ~ /^notes_[0-9]+$/ { exit } flag { print }' "$GITHUB_OUTPUT"
}

# ---------- содержимое блока ----------

@test "docker pull использует VERSION, даже если он не первый тег в списке" {
  run_notes TAGS='ghcr.io/user/repo:latest ghcr.io/user/repo:v1.2.3' VERSION=v1.2.3
  [ "$status" -eq 0 ]
  notes_output | grep -qF 'docker pull ghcr.io/user/repo:v1.2.3'
}

@test "теги семвер-лестницы перечисляются все, в исходном порядке" {
  run_notes TAGS='ghcr.io/user/repo:v1.2.3 ghcr.io/user/repo:v1.2 ghcr.io/user/repo:v1 ghcr.io/user/repo:latest' VERSION=v1.2.3
  [ "$status" -eq 0 ]
  notes_output | grep -qF 'Tags: `v1.2.3`, `v1.2`, `v1`, `latest`'
}

@test "датная версия: единственный тег плюс latest" {
  run_notes TAGS='ghcr.io/user/repo:14.03.2026 ghcr.io/user/repo:latest' VERSION=14.03.2026
  [ "$status" -eq 0 ]
  notes_output | grep -qF 'docker pull ghcr.io/user/repo:14.03.2026'
  notes_output | grep -qF 'Tags: `14.03.2026`, `latest`'
}

@test "единственный тег без списка не оставляет висячую запятую" {
  run_notes TAGS='ghcr.io/user/repo:latest' VERSION=latest
  [ "$status" -eq 0 ]
  notes_output | grep -qF 'Tags: `latest`'
}

@test "ссылка на пакеты добавляется при заданном GITHUB_REPOSITORY" {
  run_notes TAGS='ghcr.io/user/repo:v1' VERSION=v1 \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=user/repo
  [ "$status" -eq 0 ]
  notes_output | grep -qF '**Packages**: https://github.com/user/repo/packages'
}

@test "без GITHUB_REPOSITORY ссылки на пакеты нет" {
  run_notes TAGS='ghcr.io/user/repo:v1' VERSION=v1
  [ "$status" -eq 0 ]
  ! notes_output | grep -qF '**Packages**'
}

@test "блок начинается с заголовка Docker image" {
  run_notes TAGS='ghcr.io/user/repo:v1' VERSION=v1
  [ "$status" -eq 0 ]
  [ "$(notes_output | head -n1)" = '## 🐳 Docker image' ]
}

# ---------- ошибки ----------

@test "без VERSION завершается с ошибкой" {
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" TAGS='ghcr.io/user/repo:v1' bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"VERSION"* ]]
}

@test "без TAGS завершается с ошибкой" {
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" VERSION=v1 bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"TAGS"* ]]
}

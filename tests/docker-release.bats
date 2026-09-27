#!/usr/bin/env bats
# Тесты для .github/actions/docker-release/image-notes.sh
# Композитная цепочка (release-notes → image-notes.sh → publish-release)
# guard-тестами не проверяется: она собрана из уже покрытых экшенов.

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/docker-release/image-notes.sh"
  TMP="$(mktemp -d)"
  NOTES="$TMP/notes.md"
}

teardown() {
  rm -rf "$TMP"
}

run_notes() {
  run env NOTES_FILE="$NOTES" "$@" bash "$SCRIPT"
}

# ---------- содержимое блока ----------

@test "docker pull использует VERSION, даже если он не первый тег в списке" {
  echo '# What'"'"'s Changed' > "$NOTES"
  run_notes TAGS='ghcr.io/user/repo:latest ghcr.io/user/repo:v1.2.3' VERSION=v1.2.3
  [ "$status" -eq 0 ]
  grep -qF 'docker pull ghcr.io/user/repo:v1.2.3' "$NOTES"
}

@test "теги семвер-лестницы перечисляются все, в исходном порядке" {
  echo '# What'"'"'s Changed' > "$NOTES"
  run_notes TAGS='ghcr.io/user/repo:v1.2.3 ghcr.io/user/repo:v1.2 ghcr.io/user/repo:v1 ghcr.io/user/repo:latest' VERSION=v1.2.3
  [ "$status" -eq 0 ]
  grep -qF 'Tags: `v1.2.3`, `v1.2`, `v1`, `latest`' "$NOTES"
}

@test "датная версия: единственный тег плюс latest" {
  echo '# What'"'"'s Changed' > "$NOTES"
  run_notes TAGS='ghcr.io/user/repo:14.03.2026 ghcr.io/user/repo:latest' VERSION=14.03.2026
  [ "$status" -eq 0 ]
  grep -qF 'docker pull ghcr.io/user/repo:14.03.2026' "$NOTES"
  grep -qF 'Tags: `14.03.2026`, `latest`' "$NOTES"
}

@test "единственный тег без списка не оставляет висячую запятую" {
  echo '# What'"'"'s Changed' > "$NOTES"
  run_notes TAGS='ghcr.io/user/repo:latest' VERSION=latest
  [ "$status" -eq 0 ]
  grep -qF 'Tags: `latest`' "$NOTES"
}

@test "ссылка на пакеты добавляется при заданном GITHUB_REPOSITORY" {
  echo '# What'"'"'s Changed' > "$NOTES"
  run_notes TAGS='ghcr.io/user/repo:v1' VERSION=v1 \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=user/repo
  [ "$status" -eq 0 ]
  grep -qF '**Packages**: https://github.com/user/repo/packages' "$NOTES"
}

@test "без GITHUB_REPOSITORY ссылки на пакеты нет" {
  echo '# What'"'"'s Changed' > "$NOTES"
  run_notes TAGS='ghcr.io/user/repo:v1' VERSION=v1
  [ "$status" -eq 0 ]
  run grep -cF '**Packages**' "$NOTES"
  [ "$status" -ne 0 ]
}

@test "существующее тело релиза сохраняется, блок дописывается после" {
  printf '# What'"'"'s Changed\n\n**1 commit** since `v1.0.0`.\n' > "$NOTES"
  run_notes TAGS='ghcr.io/user/repo:v1' VERSION=v1
  [ "$status" -eq 0 ]
  grep -qF "What's Changed" "$NOTES"
  local changed_line docker_line
  changed_line=$(grep -n "What's Changed" "$NOTES" | cut -d: -f1)
  docker_line=$(grep -n '## 🐳 Docker image' "$NOTES" | cut -d: -f1)
  [ "$changed_line" -lt "$docker_line" ]
}

# ---------- ошибки ----------

@test "без NOTES_FILE завершается с ошибкой" {
  run env TAGS='ghcr.io/user/repo:v1' VERSION=v1 bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOTES_FILE"* ]]
}

@test "без VERSION завершается с ошибкой" {
  echo 'body' > "$NOTES"
  run env NOTES_FILE="$NOTES" TAGS='ghcr.io/user/repo:v1' bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"VERSION"* ]]
}

@test "без TAGS завершается с ошибкой" {
  echo 'body' > "$NOTES"
  run env NOTES_FILE="$NOTES" VERSION=v1 bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"TAGS"* ]]
}

@test "указанный, но отсутствующий файл заметок — ошибка" {
  run env NOTES_FILE="$TMP/missing.md" TAGS='ghcr.io/user/repo:v1' VERSION=v1 bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

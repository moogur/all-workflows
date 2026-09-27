#!/usr/bin/env bats
# Тесты для .github/actions/github-release/append-notes.sh
# Сама цепочка (tag-format → release-notes → append-notes.sh → publish-release)
# guard-тестами не проверяется: она собрана из уже покрытых экшенов.

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/github-release/append-notes.sh"
  TMP="$(mktemp -d)"
  NOTES="$TMP/notes.md"
}

teardown() {
  rm -rf "$TMP"
}

run_append() {
  run env NOTES_FILE="$NOTES" "$@" bash "$SCRIPT"
}

# ---------- дописывание блока ----------

@test "существующее тело релиза сохраняется, блок дописывается после" {
  printf '# What'"'"'s Changed\n\n**1 commit** since `v1.0.0`.\n' > "$NOTES"
  run_append EXTRA_NOTES=$'## 🐳 Docker image\n\ndocker pull user/repo:v1'
  [ "$status" -eq 0 ]
  grep -qF "What's Changed" "$NOTES"
  local changed_line docker_line
  changed_line=$(grep -n "What's Changed" "$NOTES" | cut -d: -f1)
  docker_line=$(grep -n '## 🐳 Docker image' "$NOTES" | cut -d: -f1)
  [ "$changed_line" -lt "$docker_line" ]
}

@test "блок отделяется от тела пустой строкой" {
  printf 'body\n' > "$NOTES"
  run_append EXTRA_NOTES='extra block'
  [ "$status" -eq 0 ]
  [ "$(sed -n '2p' "$NOTES")" = "" ]
  [ "$(sed -n '3p' "$NOTES")" = "extra block" ]
}

@test "многострочный блок дописывается как есть" {
  printf 'body\n' > "$NOTES"
  run_append EXTRA_NOTES=$'📦 npm package\n\n```bash\nnpm install @moogur/lib@1.2.3\n```'
  [ "$status" -eq 0 ]
  grep -qF 'npm install @moogur/lib@1.2.3' "$NOTES"
}

# ---------- ошибки ----------

@test "без NOTES_FILE завершается с ошибкой" {
  run env EXTRA_NOTES='extra' bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOTES_FILE"* ]]
}

@test "без EXTRA_NOTES завершается с ошибкой" {
  echo 'body' > "$NOTES"
  run env NOTES_FILE="$NOTES" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"EXTRA_NOTES"* ]]
}

@test "указанный, но отсутствующий файл тела — ошибка" {
  run_append EXTRA_NOTES='extra' NOTES_FILE="$TMP/missing.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

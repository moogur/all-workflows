#!/usr/bin/env bats
# Тесты для .github/actions/publish-release/publish.sh
# gh подменяется заглушкой: проверяем, какие вызовы делает скрипт.

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/publish-release/publish.sh"
  TMP="$(mktemp -d)"
  GH_LOG="$TMP/gh.log"
  NOTES="$TMP/notes.md"
  : > "$GH_LOG"
  echo '# What'"'"'s Changed' > "$NOTES"
}

teardown() {
  rm -rf "$TMP"
}

# Заглушка gh: пишет аргументы в лог; код возврата "release view" задаётся параметром
# (0 — релиз существует, 1 — нет).
make_gh_stub() {
  local view_status="$1"
  mkdir -p "$TMP/bin"
  {
    echo '#!/usr/bin/env bash'
    echo "echo \"\$*\" >> '$GH_LOG'"
    echo "if [[ \"\$*\" == release\\ view* ]]; then exit $view_status; fi"
    echo 'exit 0'
  } > "$TMP/bin/gh"
  chmod +x "$TMP/bin/gh"
}

run_publish() {
  run env PATH="$TMP/bin:$PATH" GH_TOKEN=token TAG=v1.2.3 "$@" bash "$SCRIPT"
}

# ---------- создание ----------

@test "релиза нет: создаётся с телом из файла" {
  make_gh_stub 1
  run_publish NOTES_FILE="$NOTES"
  [ "$status" -eq 0 ]
  grep -qF "release create v1.2.3" "$GH_LOG"
  grep -qF -- "--notes-file $NOTES" "$GH_LOG"
  run grep -cF "release edit" "$GH_LOG"
  [ "$status" -ne 0 ]
}

@test "релиза нет и тела нет: создаётся с пустым телом и именем тега" {
  make_gh_stub 1
  run_publish
  [ "$status" -eq 0 ]
  grep -qF "release create v1.2.3 --title v1.2.3 --notes" "$GH_LOG"
}

@test "заголовок передаётся при создании" {
  make_gh_stub 1
  run_publish RELEASE_TITLE='Release v1.2.3'
  [ "$status" -eq 0 ]
  grep -qF -- "--title Release v1.2.3" "$GH_LOG"
}

# ---------- существующий релиз ----------

@test "релиз есть: обновляется, а не создаётся заново" {
  make_gh_stub 0
  run_publish NOTES_FILE="$NOTES"
  [ "$status" -eq 0 ]
  grep -qF "release edit v1.2.3" "$GH_LOG"
  grep -qF -- "--notes-file $NOTES" "$GH_LOG"
  run grep -cF "release create" "$GH_LOG"
  [ "$status" -ne 0 ]
}

@test "релиз есть и менять нечего: ни create, ни edit" {
  make_gh_stub 0
  run_publish
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to update"* ]]
  [ "$(wc -l < "$GH_LOG")" -eq 1 ]   # только release view
}

@test "режим drafter: тело и заголовок существующего релиза не перетираются" {
  make_gh_stub 0
  run_publish ASSETS='./application.zip'
  [ "$status" -eq 0 ]
  run grep -cE -- "--notes|--title" "$GH_LOG"
  [ "$status" -ne 0 ]
  grep -qF "release upload v1.2.3 ./application.zip" "$GH_LOG"
}

# ---------- ассеты ----------

@test "ассеты грузятся с --clobber, чтобы перезапуск не падал" {
  make_gh_stub 1
  run_publish ASSETS='./application.zip'
  [ "$status" -eq 0 ]
  grep -qF -- "release upload v1.2.3 ./application.zip --clobber" "$GH_LOG"
}

@test "несколько ассетов уходят одним вызовом" {
  make_gh_stub 1
  run_publish ASSETS='./main.tar.gz ./application.zip'
  [ "$status" -eq 0 ]
  grep -qF -- "release upload v1.2.3 ./main.tar.gz ./application.zip --clobber" "$GH_LOG"
}

@test "без ассетов upload не вызывается" {
  make_gh_stub 1
  run_publish
  [ "$status" -eq 0 ]
  run grep -cF "release upload" "$GH_LOG"
  [ "$status" -ne 0 ]
}

# ---------- ошибки ----------

@test "указанный, но отсутствующий файл тела — ошибка до вызова gh" {
  make_gh_stub 1
  run_publish NOTES_FILE="$TMP/missing.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
  [ ! -s "$GH_LOG" ]
}

@test "без TAG завершается с ошибкой" {
  make_gh_stub 1
  run env PATH="$TMP/bin:$PATH" GH_TOKEN=token bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"TAG is required"* ]]
}

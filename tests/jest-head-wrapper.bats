#!/usr/bin/env bats
# Тесты для .github/actions/jest-head-wrapper: обёртка тестового скрипта для
# ArtiomTr/jest-coverage-report-action, которая оставляет отчёт только первого
# запуска (голова PR). Второй запуск action (база) пишет тот же report.json.

setup() {
  load helpers
  ROOT="$(repo_root)"
  ACTION="$ROOT/.github/actions/jest-head-wrapper"
  TMP="$(mktemp -d)"
  WS="$TMP/ws"
  BIN="$TMP/bin"
  mkdir -p "$WS" "$BIN"
  SAVED="$TMP/jest-head.json"
  # npm-заглушка: пишет отчёт с номером запуска в report.json (если не STUB_NO_REPORT),
  # запоминает аргументы и выходит с кодом STUB_EXIT.
  cat > "$BIN/npm" <<'S'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
runs=$(wc -l < "$STUB_LOG" | tr -d ' ')
[[ -n "${STUB_NO_REPORT:-}" ]] || echo "{\"run\": $runs}" > report.json
exit "${STUB_EXIT:-0}"
S
  chmod +x "$BIN/npm"
  export STUB_LOG="$TMP/npm.log"
}

teardown() {
  rm -rf "$TMP"
}

# Запуск обёртки из workspace, как на раннере; остальные env подставляет вызывающий через `env`.
wrap() {
  cd "$WS"
  run env PATH="$BIN:$PATH" "$@" bash "$ACTION/wrap.sh" "$SAVED" --ci --json --outputFile=report.json
}

@test "первый запуск: report.json копируется в указанное место" {
  wrap
  [ "$status" -eq 0 ]
  [ "$(cat "$SAVED")" = '{"run": 1}' ]
}

@test "второй запуск (база) не затирает отчёт первого" {
  wrap
  wrap
  [ "$(cat "$WS/report.json")" = '{"run": 2}' ]
  [ "$(cat "$SAVED")" = '{"run": 1}' ]
}

@test "если первый запуск не оставил отчёта, отчёт базы его не подменяет" {
  wrap STUB_NO_REPORT=1
  [ ! -e "$SAVED" ]
  wrap
  [ ! -e "$SAVED" ]
}

@test "флаги action пробрасываются в npm run test:coverage после --" {
  wrap
  [ "$(cat "$STUB_LOG")" = 'run test:coverage -- --ci --json --outputFile=report.json' ]
}

@test "код выхода тестов сохраняется, отчёт упавшего запуска всё равно копируется" {
  wrap STUB_EXIT=3
  [ "$status" -eq 3 ]
  [ "$(cat "$SAVED")" = '{"run": 1}' ]
}

@test "код выхода второго запуска сохраняется, отчёт первого остаётся" {
  wrap
  wrap STUB_EXIT=1
  [ "$status" -eq 1 ]
  [ "$(cat "$SAVED")" = '{"run": 1}' ]
}

@test "отчёта нет: обёртка не падает сверх кода тестов" {
  wrap STUB_NO_REPORT=1
  [ "$status" -eq 0 ]
  wrap STUB_NO_REPORT=1 STUB_EXIT=2
  [ "$status" -eq 2 ]
}

@test "без пути для отчёта — ошибка, тесты не запускаются" {
  cd "$WS"
  run env PATH="$BIN:$PATH" bash "$ACTION/wrap.sh"
  [ "$status" -ne 0 ]
  [ ! -e "$STUB_LOG" ]
}

@test "path.sh отдаёт абсолютный путь к существующему wrap.sh" {
  export GITHUB_OUTPUT="$TMP/output"
  : > "$GITHUB_OUTPUT"
  run bash "$ACTION/path.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value script)" = "$ACTION/wrap.sh" ]
  [ -f "$(output_value script)" ]
}

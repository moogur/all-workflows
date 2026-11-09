#!/usr/bin/env bats
# Тесты для .github/actions/test-summary/test-summary.sh: что попадает в
# $GITHUB_STEP_SUMMARY по отчётам `go test -json`, jest и vitest.
# Фикстуры в tests/fixtures/test-summary/ сняты с настоящих запусков: go — 4 пакета
# (ok: 3 пройдено и 2 пропущено, подтесты; bad: 1 пройден и 3 упало, включая подтест;
# nobuild: не собрался; notests: без тестовых файлов), jest и vitest — три файла
# (a: пройден, упал, пропущен и todo; b: пройден; c: не запустился).

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/test-summary/test-summary.sh"
  FIXTURES="$ROOT/tests/fixtures/test-summary"
  TMP="$(mktemp -d)"
  PROJECT="$(cd "$TMP" && pwd -P)/project"
  mkdir -p "$PROJECT"
  export GITHUB_STEP_SUMMARY="$TMP/summary.md"
  : > "$GITHUB_STEP_SUMMARY"
}

teardown() {
  rm -rf "$TMP"
}

# Запускает скрипт из каталога проекта: jest/vitest пишут абсолютные пути, и скрипт срезает каталог запуска.
summarize() {
  cd "$PROJECT"
  run env FORMAT="$1" REPORT="$2" bash "$SCRIPT"
}

# Кладёт фикстуру jest/vitest в temp, подставляя каталог проекта вместо @ROOT@; печатает путь.
jest_report() {
  sed "s#@ROOT@#$PROJECT#g" "$FIXTURES/$1.json" > "$TMP/report.json"
  echo "$TMP/report.json"
}

# Отрицание, которое роняет тест: голый `! cmd` посреди теста errexit не ловит.
not() {
  ! "$@"
}

# Текст между <details> и </details>.
details_block() {
  sed -n '/^<details>/,/^<\/details>/p' "$GITHUB_STEP_SUMMARY"
}

# Раздел "Упавшие тесты": от его заголовка до <details> или конца сводки.
failed_block() {
  sed -n '/^### Упавшие тесты/,$p' "$GITHUB_STEP_SUMMARY" | sed '/^<details>/,$d'
}

# --- go ---------------------------------------------------------------------

@test "go: заголовок с итогами пройдено, упало, пропущено" {
  summarize go "$FIXTURES/go.json"
  [ "$status" -eq 0 ]
  grep -qxF '## Тесты: пройдено 4, упало 4, пропущено 2' "$GITHUB_STEP_SUMMARY"
}

@test "go: таблица по пакетам, подтесты считаются как тесты" {
  summarize go "$FIXTURES/go.json"
  grep -qxF '| Пакет | Пройдено | Упало | Пропущено |' "$GITHUB_STEP_SUMMARY"
  grep -qxF '| `example.com/demo/ok` | 3 | 0 | 2 |' "$GITHUB_STEP_SUMMARY"
  grep -qxF '| `example.com/demo/bad` | 1 | 3 | 0 |' "$GITHUB_STEP_SUMMARY"
}

@test "go: упавшие тесты перечислены по имени, подтест тоже" {
  summarize go "$FIXTURES/go.json"
  grep -qxF '### Упавшие тесты (4)' "$GITHUB_STEP_SUMMARY"
  failed_block | grep -qxF -- '- `example.com/demo/bad` — `TestBroken`'
  failed_block | grep -qxF -- '- `example.com/demo/bad` — `TestParent/child`'
  failed_block | grep -qxF -- '- `example.com/demo/bad` — `TestParent`'
}

@test "go: пакет, не собравшийся и без событий тестов, показан упавшим" {
  summarize go "$FIXTURES/go.json"
  grep -qxF '| `example.com/demo/nobuild` | 0 | 1 | 0 |' "$GITHUB_STEP_SUMMARY"
  failed_block | grep -qF -- '- `example.com/demo/nobuild` — пакет завершился с ошибкой'
}

@test "go: пакет без тестовых файлов в сводку не попадает" {
  summarize go "$FIXTURES/go.json"
  not grep -qF 'notests' "$GITHUB_STEP_SUMMARY"
}

@test "go: пропущенные тесты перечислены внутри details, а не среди упавших" {
  summarize go "$FIXTURES/go.json"
  details_block | grep -qxF '<summary>Пропущенные тесты (2)</summary>'
  details_block | grep -qxF -- '- `example.com/demo/ok` — `TestSkipMe`'
  details_block | grep -qxF -- '- `example.com/demo/ok` — `TestGroup/two`'
  failed_block | not grep -qF 'TestSkipMe'
}

@test "go: пакет упал, хотя все его тесты прошли — считается упавшим" {
  printf '%s\n' '{"Action":"pass","Package":"p/a","Test":"TestOne"}' '{"Action":"fail","Package":"p/a"}' > "$TMP/report.json"
  summarize go "$TMP/report.json"
  grep -qxF '## Тесты: пройдено 1, упало 1, пропущено 0' "$GITHUB_STEP_SUMMARY"
  grep -qxF '| `p/a` | 1 | 1 | 0 |' "$GITHUB_STEP_SUMMARY"
}

@test "go: строки потока, не являющиеся JSON-объектом, пропускаются" {
  {
    echo 'go: downloading example.com/dep v1.0.0'
    echo '42'
    cat "$FIXTURES/go.json"
  } > "$TMP/report.json"
  summarize go "$TMP/report.json"
  [ "$status" -eq 0 ]
  grep -qxF '## Тесты: пройдено 4, упало 4, пропущено 2' "$GITHUB_STEP_SUMMARY"
}

@test "go: всё прошло — нет ни списка упавших, ни details" {
  printf '%s\n' '{"Action":"pass","Package":"p/a","Test":"TestOne"}' '{"Action":"pass","Package":"p/a"}' > "$TMP/report.json"
  summarize go "$TMP/report.json"
  grep -qxF '## Тесты: пройдено 1, упало 0, пропущено 0' "$GITHUB_STEP_SUMMARY"
  not grep -qF 'Упавшие тесты' "$GITHUB_STEP_SUMMARY"
  not grep -qF '<details>' "$GITHUB_STEP_SUMMARY"
}

@test "go: ни одного теста — сводка это говорит, таблицы нет" {
  printf '%s\n' '{"Action":"skip","Package":"p/a"}' > "$TMP/report.json"
  summarize go "$TMP/report.json"
  grep -qxF '## Тесты: пройдено 0, упало 0, пропущено 0' "$GITHUB_STEP_SUMMARY"
  grep -qF 'Ни одного теста не запущено.' "$GITHUB_STEP_SUMMARY"
  not grep -qF '| Пакет |' "$GITHUB_STEP_SUMMARY"
}

@test "go: длинный список пропущенных обрезается, остаток считается" {
  for i in $(seq 1 201); do
    printf '{"Action":"skip","Package":"p/a","Test":"TestSkip%s"}\n' "$i"
  done > "$TMP/report.json"
  summarize go "$TMP/report.json"
  grep -qxF '## Тесты: пройдено 0, упало 0, пропущено 201' "$GITHUB_STEP_SUMMARY"
  details_block | grep -qxF -- '- … и ещё 1'
  details_block | grep -qF 'TestSkip200'
  details_block | not grep -qF 'TestSkip201'
}

@test "сводка дописывается к уже имеющейся, а не затирает её" {
  echo 'Предыдущий шаг' > "$GITHUB_STEP_SUMMARY"
  summarize go "$FIXTURES/go.json"
  [ "$(head -n1 "$GITHUB_STEP_SUMMARY")" = 'Предыдущий шаг' ]
  grep -qF '## Тесты:' "$GITHUB_STEP_SUMMARY"
}

# --- jest и vitest ------------------------------------------------------------

@test "jest: заголовок с итогами, pending и todo считаются пропущенными" {
  summarize jest "$(jest_report jest)"
  [ "$status" -eq 0 ]
  grep -qxF '## Тесты: пройдено 2, упало 2, пропущено 2' "$GITHUB_STEP_SUMMARY"
}

@test "jest: таблица по файлам с путями относительно каталога запуска" {
  summarize jest "$(jest_report jest)"
  grep -qxF '| Файл | Пройдено | Упало | Пропущено |' "$GITHUB_STEP_SUMMARY"
  grep -qxF '| `t/a.test.js` | 1 | 1 | 2 |' "$GITHUB_STEP_SUMMARY"
  grep -qxF '| `t/b.test.js` | 1 | 0 | 0 |' "$GITHUB_STEP_SUMMARY"
  not grep -qF "$PROJECT" "$GITHUB_STEP_SUMMARY"
}

@test "jest: упавший тест назван полным именем, не запустившийся файл показан упавшим" {
  summarize jest "$(jest_report jest)"
  failed_block | grep -qxF -- '- `t/a.test.js` — `math breaks`'
  grep -qxF '| `t/c.test.js` | 0 | 1 | 0 |' "$GITHUB_STEP_SUMMARY"
  failed_block | grep -qF -- '- `t/c.test.js` — файл не запустился'
}

@test "jest: пропущенные и todo перечислены внутри details" {
  summarize jest "$(jest_report jest)"
  details_block | grep -qxF '<summary>Пропущенные тесты (2)</summary>'
  details_block | grep -qxF -- '- `t/a.test.js` — `math skipped one`'
  details_block | grep -qxF -- '- `t/a.test.js` — `math later`'
}

@test "vitest: тот же формат разбирается так же, статус skipped считается пропущенным" {
  summarize jest "$(jest_report vitest)"
  [ "$status" -eq 0 ]
  grep -qxF '## Тесты: пройдено 2, упало 2, пропущено 2' "$GITHUB_STEP_SUMMARY"
  grep -qxF '| `t/a.test.js` | 1 | 1 | 2 |' "$GITHUB_STEP_SUMMARY"
  failed_block | grep -qF -- '- `t/c.test.js` — файл не запустился'
}

@test "jest: файл без тестов, не упавший, в таблицу не попадает" {
  echo '{"testResults":[{"name":"'"$PROJECT"'/empty.test.js","status":"passed","assertionResults":[]}]}' > "$TMP/report.json"
  summarize jest "$TMP/report.json"
  grep -qF 'Ни одного теста не запущено.' "$GITHUB_STEP_SUMMARY"
  not grep -qF 'empty.test.js' "$GITHUB_STEP_SUMMARY"
}

@test "jest: символ | в имени файла экранируется, чтобы не рвать таблицу" {
  echo '{"testResults":[{"name":"'"$PROJECT"'/a|b.test.js","status":"passed","assertionResults":[{"fullName":"x","status":"passed"}]}]}' > "$TMP/report.json"
  summarize jest "$TMP/report.json"
  grep -qxF '| `a\|b.test.js` | 1 | 0 | 0 |' "$GITHUB_STEP_SUMMARY"
}

# --- отчёта нет ---------------------------------------------------------------

@test "отчёта нет: сводка так и говорит, код выхода 0" {
  summarize go "$TMP/missing.json"
  [ "$status" -eq 0 ]
  grep -qxF '## Тесты: отчёт не найден' "$GITHUB_STEP_SUMMARY"
  grep -qF "$TMP/missing.json" "$GITHUB_STEP_SUMMARY"
}

@test "пустой отчёт: то же сообщение, код выхода 0" {
  : > "$TMP/empty.json"
  summarize jest "$TMP/empty.json"
  [ "$status" -eq 0 ]
  grep -qxF '## Тесты: отчёт не найден' "$GITHUB_STEP_SUMMARY"
}

@test "jest: отчёт не JSON — сообщение вместо падения, код выхода 0" {
  echo '{"testResults": [' > "$TMP/broken.json"
  summarize jest "$TMP/broken.json"
  [ "$status" -eq 0 ]
  grep -qxF '## Тесты: отчёт не разобран' "$GITHUB_STEP_SUMMARY"
}

# --- вход ---------------------------------------------------------------------

@test "неизвестный формат — ошибка, сводка не пишется" {
  summarize junit "$FIXTURES/go.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown format: junit"* ]]
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
}

@test "без REPORT — ошибка" {
  run env -u REPORT FORMAT=go bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"REPORT is required"* ]]
}

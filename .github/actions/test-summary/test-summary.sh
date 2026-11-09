#!/usr/bin/env bash
# Пишет в $GITHUB_STEP_SUMMARY итоги тестов из отчёта (Markdown, по-русски).
# Вход (env): FORMAT (go|jest), REPORT (путь к отчёту), GITHUB_STEP_SUMMARY.
# Отчёта нет, он пуст или не разбирается — в сводку пишется об этом, код выхода 0:
# тесты могли упасть раньше, чем записали отчёт, и сводка не должна маскировать их падение своим.
set -euo pipefail

format="${FORMAT:?FORMAT is required}"
report="${REPORT:?REPORT is required}"
summary="${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY is required}"
dir="$(dirname "${BASH_SOURCE[0]}")"

normalize() {
  case "$format" in
    go) jq -nR -f "$dir/go.jq" "$report" ;;
    jest) jq --arg root "$PWD/" -f "$dir/jest.jq" "$report" ;;
  esac
}

note() {
  printf '## Тесты: %s\n\n%s\n' "$1" "$2" >> "$summary"
}

case "$format" in
  go | jest) ;;
  *) echo "test-summary: unknown format: $format (expected go or jest)" >&2; exit 1 ;;
esac

if [[ ! -s "$report" ]]; then
  note "отчёт не найден" "Файл отчёта \`$report\` отсутствует или пуст: тесты могли завершиться до его записи."
  exit 0
fi

if ! normalized=$(normalize); then
  note "отчёт не разобран" "Файл отчёта \`$report\` не удалось прочитать как \`$format\`."
  exit 0
fi

jq -r -f "$dir/render.jq" <<< "$normalized" >> "$summary"

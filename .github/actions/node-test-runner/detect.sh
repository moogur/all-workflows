#!/usr/bin/env bash
# Определяет раннер тестов по package.json в текущем каталоге: vitest в dependencies
# или devDependencies — vitest, иначе jest — jest, иначе раннер не определён.
# Вход (env): RUNNER_TEMP, GITHUB_OUTPUT.
# Выход: строки "format", "args", "report" в файл $GITHUB_OUTPUT. format и args пусты,
# если раннера нет; format у vitest тоже jest: его JSON-репортер совместим с jest --json.
set -euo pipefail

report="${RUNNER_TEMP:?RUNNER_TEMP is required}/test-report.json"

runner=$(jq -r '
  ((.dependencies // {}) + (.devDependencies // {})) as $deps
  | if $deps | has("vitest") then "vitest"
    elif $deps | has("jest") then "jest"
    else "" end' package.json)

case "$runner" in
  # default и github-actions сохраняют обычный вывод и аннотации: явный --reporter отключает те, что
  # vitest включает сам, а json-репортер без них заменил бы консольный вывод.
  vitest) format=jest args="--reporter=default --reporter=github-actions --reporter=json --outputFile.json=$report" ;;
  jest) format=jest args="--json --outputFile=$report" ;;
  *) format="" args="" ;;
esac

{
  echo "format=$format"
  echo "args=$args"
  echo "report=$report"
} >> "$GITHUB_OUTPUT"

#!/usr/bin/env bash
# Обёртка тестового скрипта для ArtiomTr/jest-coverage-report-action.
# Использование: wrap.sh <куда сохранить отчёт> [флаги jest...]
# На PR action гоняет тесты дважды той же командой: сначала на голове PR, потом на базе, и оба раза
# пишет report.json в текущий каталог — после второго запуска там отчёт базы. Обёртка копирует
# report.json в <куда сохранить отчёт> только после первого запуска (голова PR), каким бы он ни
# кончился; если отчёта в тот раз не появилось, базовый его не подменяет. Код выхода — как у тестов.
# Флаги (--ci --json --outputFile=report.json ...) добавляет сам action, обёртка пробрасывает их
# в `npm run test:coverage --`. Пути отчёта не должно быть "report.json" в имени: action по такой
# подстроке в команде считает скрипт уже настроенным и флаги не добавляет.
set -uo pipefail

saved="${1:?path to save the report to is required}"
shift

# Метка "первый запуск уже был" лежит рядом, а не в самом отчёте: отчёта может не быть.
marker="$saved.ran"
first=1
[[ -e "$marker" ]] && first=0

npm run test:coverage -- "$@"
code=$?

if ((first)); then
  : > "$marker"
  [[ -f report.json ]] && cp report.json "$saved"
fi

exit "$code"

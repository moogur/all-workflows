#!/usr/bin/env bash
# Выход: строка "script=<абсолютный путь к wrap.sh>" в файл $GITHUB_OUTPUT.
# Путь нужен workflow'у: тот лежит в чужом репозитории, а скрипт — в каталоге этого action.
set -euo pipefail

echo "script=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wrap.sh" >> "$GITHUB_OUTPUT"

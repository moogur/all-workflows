#!/usr/bin/env bash
# Определяет формат версии: дата (dd.mm.yyyy, включая метки авто-сборки dd.mm.yyyy[-HHMM]-auto)
# или semver строго с префиксом v (vX.Y.Z); версия другого вида — ошибка.
# Вход (env): VERSION, GITHUB_OUTPUT.
# Выход: строка "format=date|semver" в файл $GITHUB_OUTPUT.
set -euo pipefail

version="${VERSION:?VERSION is required}"

# Дата первой: 14.03.2026 подходит и под регулярку semver без префикса.
if [[ "$version" =~ ^[0-9]{2}\.[0-9]{2}\.[0-9]{4}(-[0-9]{4})?(-auto)?$ ]]; then
  format='date'
elif [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  format='semver'
else
  echo "Version '$version' is neither a date (dd.mm.yyyy) nor a semver tag (vX.Y.Z)" >&2
  exit 1
fi

echo "format=${format}" >> "$GITHUB_OUTPUT"

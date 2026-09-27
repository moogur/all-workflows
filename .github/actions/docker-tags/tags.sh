#!/usr/bin/env bash
# Формирует список тегов docker-образа по версии сборки; формат определяет action tag-format.
# Дата (dd.mm.yyyy, метка авто-сборки dd.mm.yyyy[-HHMM]-auto) — версия как есть + latest;
# semver (vX.Y.Z) — лестница vX.Y.Z, vX.Y, vX, latest.
# Вход (env): IMAGE, VERSION, FORMAT (date|semver, от tag-format), GITHUB_OUTPUT.
# Выход: строка "tags=<image>:<tag> ..." в файл $GITHUB_OUTPUT.
set -euo pipefail

image="${IMAGE:?IMAGE is required}"
version="${VERSION:?VERSION is required}"
format="${FORMAT:?FORMAT is required}"

case "$format" in
  date)
    tags=("$version" 'latest')
    ;;
  semver)
    IFS='.' read -r major minor patch <<< "${version#v}"
    tags=("v${major}.${minor}.${patch}" "v${major}.${minor}" "v${major}" 'latest')
    ;;
  *)
    # Внутренний контракт с tag-format: сюда попадать не должно.
    echo "Unknown FORMAT '$format'" >&2
    exit 1
    ;;
esac

refs=()
for tag in "${tags[@]}"; do
  refs+=("${image}:${tag}")
done

echo "tags=${refs[*]}" >> "$GITHUB_OUTPUT"

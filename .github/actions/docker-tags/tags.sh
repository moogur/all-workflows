#!/usr/bin/env bash
# Формирует список тегов docker-образа по версии сборки.
# Вход (env): IMAGE, VERSION, FORMAT_MODE (date|semver, по умолчанию date), GITHUB_OUTPUT.
# Выход: строка "tags=<image>:<tag> ..." в файл $GITHUB_OUTPUT.
set -euo pipefail

image="${IMAGE:?IMAGE is required}"
version="${VERSION:?VERSION is required}"
mode="${FORMAT_MODE:-date}"

case "$mode" in
  date)
    tags=("$version" 'latest')
    ;;
  semver)
    if [[ ! "$version" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
      echo "Version '$version' is not a semver tag (expected vX.Y.Z) for format_mode=semver" >&2
      exit 1
    fi
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[3]}"
    tags=("v${major}.${minor}.${patch}" "v${major}.${minor}" "v${major}" 'latest')
    ;;
  *)
    echo "Unknown format_mode: '$mode' (expected 'date' or 'semver')" >&2
    exit 1
    ;;
esac

refs=()
for tag in "${tags[@]}"; do
  refs+=("${image}:${tag}")
done

echo "tags=${refs[*]}" >> "$GITHUB_OUTPUT"

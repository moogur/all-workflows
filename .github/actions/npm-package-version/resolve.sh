#!/usr/bin/env bash
# Определяет опубликованные npm-пакеты ("имя@версия" на файл package.json) —
# формат см. в lib/npm.sh. Приватные пакеты (private: true) в список не попадают.
# Вход (env): FILES (пути к package.json, по одному на строку), GITHUB_OUTPUT.
# Выход: многострочная строка "packages" в файл $GITHUB_OUTPUT (может быть пустой,
#   если все переданные пакеты приватные — вызывающий workflow сам решает, ошибка ли это).
set -euo pipefail
# shellcheck source=lib/npm.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/npm.sh"

files="${FILES:?FILES is required}"

packages=''
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  ref=$(npm_package_ref "$file")
  [[ -n "$ref" ]] || continue
  packages+="${ref}"$'\n'
done <<< "$files"

# Многострочный output: делимитер со временем в наносекундах.
delimiter="packages_$(date +%s%N)"
{
  echo "packages<<${delimiter}"
  printf '%s' "$packages"
  echo "$delimiter"
} >> "$GITHUB_OUTPUT"

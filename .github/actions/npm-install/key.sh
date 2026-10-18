#!/usr/bin/env bash
# Считает ключ кэша node_modules: ОС + версия Node + sha256 lock-файла.
# Вход (env): LOCK_FILE — путь к lock-файлу. Выход: key, path, dir в $GITHUB_OUTPUT.
# path — список каталогов node_modules (по одному на строку): корневой и по одному на
# каждый workspace из package.json, где npm кладёт неподнятые зависимости.
set -euo pipefail

lock="${LOCK_FILE:-package-lock.json}"

if [ ! -f "$lock" ]; then
  echo "::error::Lock-файл не найден: $lock" >&2
  exit 1
fi

node_version="$(node --version)"
hash="$(shasum -a 256 "$lock" | cut -d' ' -f1)"
dir="$(dirname "$lock")"

paths="${dir}/node_modules"

if [ -f "${dir}/package.json" ]; then
  patterns="$(jq -r '(.workspaces // []) | (if type == "array" then . else .packages // [] end) | .[]' "${dir}/package.json")"
  while IFS= read -r pattern; do
    case "$pattern" in "" | "!"*) continue ;; esac
    # Шаблон раскрывается относительно каталога lock-файла; без совпадений — пусто.
    shopt -s nullglob
    for ws in "${dir}"/${pattern}; do
      [ -d "$ws" ] && paths+=$'\n'"${ws}/node_modules"
    done
    shopt -u nullglob
  done <<< "$patterns"
fi

{
  echo "key=${RUNNER_OS}-node_modules-${node_version}-${hash}"
  echo "path<<NPM_INSTALL_PATH_EOF"
  echo "$paths"
  echo "NPM_INSTALL_PATH_EOF"
  echo "dir=${dir}"
} >> "$GITHUB_OUTPUT"

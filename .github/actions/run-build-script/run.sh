#!/usr/bin/env bash
# Проверяет путь к пользовательскому скрипту сборки и выполняет его через source.
# Вход (env): FILE_PATH, GITHUB_WORKSPACE (по умолчанию — текущий каталог).
# Скрипт намеренно исполняется в этой же оболочке (как раньше `. <file_path>`), поэтому
# путь не доверяется: только относительный, без сегментов "..", обычный файл, и после
# разыменования симлинков он остаётся внутри workspace.
set -euo pipefail

path="${FILE_PATH:-}"
workspace="$(cd "${GITHUB_WORKSPACE:-.}" && pwd -P)"

fail() {
  echo "run-build-script: $1" >&2
  exit 1
}

[[ -n $path ]] || fail "file_path is empty"
[[ $path != /* ]] || fail "file_path must be relative to the repository root"
[[ /$path/ != */../* ]] || fail "file_path must not contain '..' segments"
[[ -f $path ]] || fail "file_path is not an existing regular file: $path"

# -f разыменовывает симлинк: проверяем настоящее расположение файла.
real="$(realpath "$path")"
[[ $real == "$workspace"/* ]] || fail "file_path resolves outside the workspace: $path"

# "./" — иначе source ищет имя без слэша в PATH, а не в репозитории.
# Пользовательский скрипт не рассчитан на -u/pipefail; поведение прежнее: только -e.
set +u +o pipefail
# shellcheck disable=SC1090
. "./$path"

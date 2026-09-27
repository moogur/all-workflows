#!/usr/bin/env bash
# Дописывает в тело релиза (файл от release-notes) готовый markdown-блок:
# используется docker-release (блок про образ) и npm-релизами (блок про пакет).
# Вход (env): NOTES_FILE (существующий файл), EXTRA_NOTES (markdown, непустой —
#   пустая строка не запускает шаг вовсе, см. action.yml).
set -euo pipefail

notes_file="${NOTES_FILE:?NOTES_FILE is required}"
extra_notes="${EXTRA_NOTES:?EXTRA_NOTES is required}"

if [[ ! -f "$notes_file" ]]; then
  echo "Notes file '${notes_file}' not found" >&2
  exit 1
fi

{
  echo
  printf '%s\n' "$extra_notes"
} >> "$notes_file"

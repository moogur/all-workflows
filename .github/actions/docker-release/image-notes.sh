#!/usr/bin/env bash
# Дописывает в тело релиза (файл от release-notes) блок про опубликованный docker-образ:
# команду docker pull и список всех тегов сборки.
# Вход (env): NOTES_FILE (существующий файл), TAGS (через пробел, "<образ>:<тег>" —
#   формат docker-tags), VERSION (версия сборки), GITHUB_SERVER_URL, GITHUB_REPOSITORY.
set -euo pipefail

notes_file="${NOTES_FILE:?NOTES_FILE is required}"
version="${VERSION:?VERSION is required}"
read -ra refs <<< "${TAGS:?TAGS is required}"

if [[ ! -f "$notes_file" ]]; then
  echo "Notes file '${notes_file}' not found" >&2
  exit 1
fi

# Образ у всех ссылок один и тот же; сам путь образа двоеточий не содержит
# (см. docker-image/resolve.sh), поэтому тег — это всё после последнего ':'.
image="${refs[0]%:*}"

tag_list=''
for ref in "${refs[@]}"; do
  tag_list+="${tag_list:+, }\`${ref##*:}\`"
done

{
  echo
  echo '## 🐳 Docker image'
  echo
  echo '```bash'
  echo "docker pull ${image}:${version}"
  echo '```'
  echo
  echo "Tags: ${tag_list}"

  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    echo
    echo "**Packages**: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/packages"
  fi
} >> "$notes_file"

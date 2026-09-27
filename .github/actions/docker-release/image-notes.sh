#!/usr/bin/env bash
# Строит markdown-блок про опубликованный docker-образ (команда docker pull и
# список всех тегов сборки) и печатает его в $GITHUB_OUTPUT (notes) — action.yml
# передаёт его в github-release как extra_notes, а не дописывает в файл сам.
# Разбор ссылок "<образ>:<тег>" — lib/docker.sh.
# Вход (env): TAGS (через пробел, "<образ>:<тег>" — формат docker-tags),
#   VERSION (версия сборки), GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_OUTPUT.
set -euo pipefail
# shellcheck source=lib/docker.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/docker.sh"

version="${VERSION:?VERSION is required}"
read -ra refs <<< "${TAGS:?TAGS is required}"

# Образ у всех ссылок один и тот же.
image=$(docker_ref_image "${refs[0]}")

tag_list=''
for ref in "${refs[@]}"; do
  tag_list+="${tag_list:+, }\`$(docker_ref_tag "$ref")\`"
done

block=$(
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
)

# Многострочный output: делимитер со временем в наносекундах — блок не содержит
# ничего похожего на "notes_<timestamp>".
delimiter="notes_$(date +%s%N)"
{
  echo "notes<<${delimiter}"
  printf '%s\n' "$block"
  echo "$delimiter"
} >> "$GITHUB_OUTPUT"

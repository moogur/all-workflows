#!/usr/bin/env bash
# Определяет версию сборки и имя образа — форматы см. в lib/version.sh, lib/docker.sh.
# Версия — тег, инициировавший запуск. Сборка без тега (расписание, ручной запуск)
# всегда идёт датной меткой авто-сборки, поэтому и в semver-репозитории она не
# перепишет релизные vX.Y.Z другим содержимым.
# Пользователь образа: GITHUB_USER, а если он пуст — владелец репозитория (REPOSITORY_OWNER),
# а не актор: образ лежит в пространстве владельца, кто бы ни запушил тег.
# Вход (env): GITHUB_USER (необяз.), REPOSITORY_OWNER, REPOSITORY_NAME, REF_TYPE, REF_NAME, GITHUB_OUTPUT.
# Выход: строки "version=", "image=", "user=" в файл $GITHUB_OUTPUT.
set -euo pipefail
lib="$(dirname "${BASH_SOURCE[0]}")/../../../lib"
# shellcheck source=lib/version.sh
source "$lib/version.sh"
# shellcheck source=lib/docker.sh
source "$lib/docker.sh"

github_user="${GITHUB_USER:-${REPOSITORY_OWNER:?GITHUB_USER or REPOSITORY_OWNER is required}}"
repository_name="${REPOSITORY_NAME:?REPOSITORY_NAME is required}"

if [[ "${REF_TYPE:-}" == 'tag' ]]; then
  version="${REF_NAME:?REF_NAME is required for a tag build}"
else
  version=$(version_auto_label)
fi

# ПРИМЕЧАНИЕ: docker.pkg.github.com устарел; см. docs/modernization.md.
image=$(docker_image_name "$github_user" "$repository_name")

{
  echo "version=${version}"
  echo "image=${image}"
  echo "user=${github_user}"
} >> "$GITHUB_OUTPUT"

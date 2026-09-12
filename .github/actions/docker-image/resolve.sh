#!/usr/bin/env bash
# Определяет версию сборки, формат тегов и имя образа.
# Версия — тег, инициировавший запуск. Сборка без тега (расписание, ручной запуск)
# всегда идёт как dd.mm.yyyy-HHMM-auto в формате date, даже в semver-репозитории:
# иначе плановая пересборка переписала бы релизные vX.Y.Z другим содержимым.
# Время в метке — чтобы две сборки за сутки не затёрли друг друга (UTC).
# Вход (env): GITHUB_USER, REPOSITORY_NAME, FORMAT_MODE (по умолчанию date),
#   REF_TYPE, REF_NAME, GITHUB_OUTPUT.
# Выход: строки "version=", "format_mode=", "image=" в файл $GITHUB_OUTPUT.
set -euo pipefail

github_user="${GITHUB_USER:?GITHUB_USER is required}"
repository_name="${REPOSITORY_NAME:?REPOSITORY_NAME is required}"

if [[ "${REF_TYPE:-}" == 'tag' ]]; then
  version="${REF_NAME:?REF_NAME is required for a tag build}"
  format_mode="${FORMAT_MODE:-date}"
else
  version=$(date -u +'%d.%m.%Y-%H%M-auto')
  format_mode='date'
fi

# ПРИМЕЧАНИЕ: docker.pkg.github.com устарел; см. docs/modernization.md.
image="docker.pkg.github.com/${github_user}/${repository_name}/${repository_name}"

{
  echo "version=${version}"
  echo "format_mode=${format_mode}"
  echo "image=${image}"
} >> "$GITHUB_OUTPUT"

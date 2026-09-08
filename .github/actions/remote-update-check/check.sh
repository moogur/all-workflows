#!/usr/bin/env bash
# Считывает маркер свежести внешнего репозитория.
# Вход (env): REPOSITORY_URL, CHECK_TYPE (commit|tag, по умолчанию commit),
# REPOSITORY_BRANCH (для commit, по умолчанию master), GITHUB_OUTPUT.
# Выход: строка "value=<...>" в файл $GITHUB_OUTPUT.
set -euo pipefail

url="${REPOSITORY_URL:?REPOSITORY_URL is required}"
check_type="${CHECK_TYPE:-commit}"
branch="${REPOSITORY_BRANCH:-master}"

case "$check_type" in
  commit)
    # Время последнего коммита ветки: тянем только её верхушку.
    temp_repository=$(mktemp -d)
    git clone --quiet --depth=1 --single-branch -b "$branch" "$url" "$temp_repository"
    value=$(git -C "$temp_repository" log -1 --format=%ct)
    rm -rf "$temp_repository"
    ;;
  tag)
    # Самый свежий тег по дате создания. Сортировать по имени нельзя: она врёт
    # на любых неверсионных тегах — среди дат «максимум» это 26.05.2023, потому
    # что 26 > 14, а год в сравнение не попадает.
    # ls-remote дат не отдаёт, поэтому клонируем — но без блобов, только рефы.
    temp_repository=$(mktemp -d)
    git clone --quiet --bare --filter=blob:none "$url" "$temp_repository"
    value=$(git -C "$temp_repository" for-each-ref \
      --sort=-creatordate --count=1 --format='%(refname:short)' refs/tags)
    rm -rf "$temp_repository"

    if [[ -z "$value" ]]; then
      echo "No tags found in '$url'" >&2
      exit 1
    fi
    ;;
  *)
    echo "Unknown type: '$check_type' (expected 'commit' or 'tag')" >&2
    exit 1
    ;;
esac

echo "value=${value}" >> "$GITHUB_OUTPUT"

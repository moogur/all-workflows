#!/usr/bin/env bash
# Публикует GitHub-релиз по тегу: создаёт новый или обновляет уже существующий,
# затем прикладывает ассеты. Перезапуск job'а по тому же тегу не падает.
# Вход (env): TAG, RELEASE_TITLE (необяз.), NOTES_FILE (необяз.),
#   ASSETS (необяз., пути через пробел), GH_TOKEN.
set -euo pipefail

tag="${TAG:?TAG is required}"
title="${RELEASE_TITLE:-}"
notes_file="${NOTES_FILE:-}"

if [[ -n "$notes_file" && ! -f "$notes_file" ]]; then
  echo "Notes file '${notes_file}' not found" >&2
  exit 1
fi

# Обновляем только то, что передали явно: в режиме drafter тело и заголовок
# уже проставил release-drafter, и перетирать их нечем и незачем.
edit_args=()
[[ -z "$title" ]] || edit_args+=(--title "$title")
[[ -z "$notes_file" ]] || edit_args+=(--notes-file "$notes_file")

if gh release view "$tag" >/dev/null 2>&1; then
  if [[ "${#edit_args[@]}" -gt 0 ]]; then
    gh release edit "$tag" "${edit_args[@]}"
    echo "Release '${tag}' updated"
  else
    echo "Release '${tag}' already exists, nothing to update"
  fi
else
  # При создании флаги обязательны: без --notes gh в неинтерактивном режиме не работает,
  # пустое тело — это поведение релиза без changelog.
  create_args=(--title "${title:-$tag}")
  if [[ -n "$notes_file" ]]; then
    create_args+=(--notes-file "$notes_file")
  else
    create_args+=(--notes '')
  fi

  gh release create "$tag" "${create_args[@]}"
  echo "Release '${tag}' created"
fi

read -ra assets <<< "${ASSETS:-}"
if [[ "${#assets[@]}" -gt 0 ]]; then
  # --clobber: перезапуск заменяет ассет, а не падает на уже загруженном.
  gh release upload "$tag" "${assets[@]}" --clobber
  echo "Assets uploaded: ${assets[*]}"
fi

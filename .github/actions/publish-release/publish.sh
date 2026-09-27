#!/usr/bin/env bash
# Публикует GitHub-релиз по тегу: создаёт новый или обновляет уже существующий,
# затем прикладывает ассеты. Перезапуск job'а по тому же тегу не падает, как и
# гонка параллельных job'ов матрицы за один и тот же тег (см. ниже).
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

# Обновляем только то, что передали явно: пустой вход значит «нечем перетирать»
# (например, повторный запуск github-release без изменений в теле/заголовке).
edit_args=()
[[ -z "$title" ]] || edit_args+=(--title "$title")
[[ -z "$notes_file" ]] || edit_args+=(--notes-file "$notes_file")

if gh release view "$tag" >/dev/null 2>&1; then
  if [[ "${#edit_args[@]}" -gt 0 ]]; then
    # Удалённый и заново запушенный тег превращает свой релиз в draft — снимаем при любой правке.
    gh release edit "$tag" "${edit_args[@]}" --draft=false
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

  if gh release create "$tag" "${create_args[@]}"; then
    echo "Release '${tag}' created"
  elif gh release view "$tag" >/dev/null 2>&1; then
    # Гонка параллельных job'ов матрицы: релиз появился между проверкой и созданием —
    # это не ошибка, доделываем как edit (пустые edit_args — победивший job уже всё проставил).
    echo "Release '${tag}' created concurrently by another job, updating instead" >&2
    if [[ "${#edit_args[@]}" -gt 0 ]]; then
      gh release edit "$tag" "${edit_args[@]}" --draft=false
    fi
  else
    echo "Release '${tag}' creation failed and still doesn't exist" >&2
    exit 1
  fi
fi

read -ra assets <<< "${ASSETS:-}"
if [[ "${#assets[@]}" -gt 0 ]]; then
  # --clobber: перезапуск заменяет ассет, а не падает на уже загруженном.
  gh release upload "$tag" "${assets[@]}" --clobber
  echo "Assets uploaded: ${assets[*]}"
fi

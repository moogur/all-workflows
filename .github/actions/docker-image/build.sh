#!/usr/bin/env bash
# Собирает образ со всеми тегами. Версия приложения уходит в ARG_APP_VERSION,
# остальные build-arg'и приходят списком "KEY=VALUE" (по одному на строку).
# Вход (env): TAGS (через пробел), VERSION, BUILD_ARGS (необяз.), CONTEXT (по умолчанию .).
set -euo pipefail

version="${VERSION:?VERSION is required}"
context="${CONTEXT:-.}"

read -ra tags <<< "${TAGS:?TAGS is required}"
if [[ "${#tags[@]}" -eq 0 ]]; then
  echo 'TAGS is empty' >&2
  exit 1
fi

arguments=(--build-arg "ARG_APP_VERSION=${version}")

while IFS= read -r pair; do
  [[ -n "$pair" ]] || continue
  arguments+=(--build-arg "$pair")
done <<< "${BUILD_ARGS:-}"

for tag in "${tags[@]}"; do
  arguments+=(-t "$tag")
done

docker build "${arguments[@]}" "$context"

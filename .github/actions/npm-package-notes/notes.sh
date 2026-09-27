#!/usr/bin/env bash
# Строит markdown-блок "как поставить" для опубликованных npm-пакетов: одна
# команда npm install на каждую строку PACKAGES. Один пакет (publish_package) или
# несколько (deploy_for_lerna) — формат один и тот же. Печатается в $GITHUB_OUTPUT
# (notes) — action.yml передаёт его в github-release как extra_notes.
# Вход (env): PACKAGES ("имя@версия" по одной на строку), GITHUB_OUTPUT.
set -euo pipefail

packages="${PACKAGES:?PACKAGES is required}"

# Пустых строк в PACKAGES быть не должно (например, весь набор пакетов приватный) —
# без этой проверки релиз молча вышел бы с пустым блоком команд.
grep -q '[^[:space:]]' <<< "$packages" || {
  echo "PACKAGES has no non-empty entries" >&2
  exit 1
}

block=$(
  echo '## 📦 npm package'
  echo
  echo '```bash'
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    echo "npm install ${pkg}"
  done <<< "$packages"
  echo '```'
)

# Многострочный output: делимитер со временем в наносекундах — блок не содержит
# ничего похожего на "notes_<timestamp>".
delimiter="notes_$(date +%s%N)"
{
  echo "notes<<${delimiter}"
  printf '%s\n' "$block"
  echo "$delimiter"
} >> "$GITHUB_OUTPUT"

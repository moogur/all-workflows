# shellcheck shell=bash
#
# Идентификатор опубликованного npm-пакета: "имя@версия" — то, что принимает
# `npm install`. Берётся из package.json; приватные пакеты (private: true)
# в список публикаций не попадают.

# npm_package_ref <package.json> — "имя@версия" из файла; для приватного пакета —
# пустая строка (вызывающий код сам решает, пропустить её или считать ошибкой).
npm_package_ref() {
  local file="$1"
  jq -r 'select(.private != true) | "\(.name)@\(.version)"' "$file"
}

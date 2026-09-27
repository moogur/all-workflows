# shellcheck shell=bash
#
# "Последний тег" везде значит последний по дате создания (--sort=-creatordate),
# никогда по имени: репозитории смешивают датные (dd.mm.yyyy) и semver (vX.Y.Z)
# теги, и сортировка по имени на датных тегах врёт — среди дат «максимум» это
# 26.05.2023, потому что 26 > 14, а год в сравнение не попадает.

# tags_latest_n <n> [репозиторий] — n последних тегов, от самого свежего, по одному
# на строку; репозиторий по умолчанию — текущая директория.
tags_latest_n() {
  local n="$1" repo="${2:-.}"
  git -C "$repo" for-each-ref --sort=-creatordate --count="$n" --format='%(refname:short)' refs/tags
}

# tags_previous <тег> [репозиторий] — тег, соседний с указанным по дате создания
# (более старый); пустая строка, если указанный тег самый старый или не существует.
tags_previous() {
  local current="$1" repo="${2:-.}"
  git -C "$repo" for-each-ref --sort=-creatordate --format='%(refname:short)' refs/tags \
    | awk -v current="$current" 'found { print; exit } $0 == current { found = 1 }'
}

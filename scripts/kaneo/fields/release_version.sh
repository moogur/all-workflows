# shellcheck shell=bash
#
# Функция поля release_version (схема: "Version": "release_version"): дописывает
# версию последнего релиза в список через запятую. Контракт функций полей — docs/kaneo.md.

# shellcheck source=lib/tags.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/tags.sh"
# shellcheck source=lib/version.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/version.sh"

# kaneo_merge_versions <текущее значение поля> <версия> — печатает новое значение: версия
# (поле пустое) или "<текущее>, <версия>". Код 1, если версия в списке уже есть
# (сравнение по целому элементу списка, не по подстроке: 1.2 не входит в 1.2.3).
kaneo_merge_versions() {
  local current=$1 version=$2 item
  local -a items

  if [[ -z "$current" ]]; then
    printf '%s' "$version"
    return 0
  fi

  IFS=',' read -r -a items <<< "$current"
  for item in "${items[@]}"; do
    item=${item#"${item%%[![:space:]]*}"}
    item=${item%"${item##*[![:space:]]}"}
    if [[ "$item" == "$version" ]]; then
      return 1
    fi
  done
  printf '%s, %s' "$current" "$version"
}

# kaneo_field_release_version — новое значение поля из KANEO_FIELD_VALUE и версии последнего
# тега (по дате создания, без префикса v); версия уже в списке — значение без изменений.
# Нет тегов — сообщение в stderr и код 1.
kaneo_field_release_version() {
  local tag version
  tag=$(tags_latest_n 1) || tag=''
  if [[ -z "$tag" ]]; then
    echo "Kaneo: в репозитории нет тегов, версия релиза не определена" >&2
    return 1
  fi
  version=$(version_strip_prefix "$tag" v)
  kaneo_merge_versions "${KANEO_FIELD_VALUE:-}" "$version" || printf '%s' "${KANEO_FIELD_VALUE:-}"
}

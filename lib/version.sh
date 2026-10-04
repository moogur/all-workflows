# shellcheck shell=bash
#
# Формат версии сборки — ровно два варианта, версия другого вида отклоняется:
#   дата, dd.mm.yyyy (например, 14.03.2026), включая метки авто-сборки
#     dd.mm.yyyy-HHMM-auto и легаси dd.mm.yyyy-auto (без времени);
#   semver строго с префиксом v, vX.Y.Z (например, v1.0.0).
# Авто-сборка без тега (расписание, ручной запуск) всегда получает датную метку
# dd.mm.yyyy-HHMM-auto по UTC — время в метке, чтобы две сборки за сутки не затёрли
# друг друга.

# Повторное подключение в том же shell не должно падать на readonly (см. lib/commit.sh)
if [[ -z "${LIB_VERSION_LOADED:-}" ]]; then
  readonly LIB_VERSION_LOADED=1
  readonly VERSION_DATE_REGEX='^[0-9]{2}\.[0-9]{2}\.[0-9]{4}(-[0-9]{4})?(-auto)?$'
  readonly VERSION_SEMVER_REGEX='^v[0-9]+\.[0-9]+\.[0-9]+$'
fi

# version_format <версия> — печатает "date" или "semver" в stdout; версия другого
# вида — сообщение в stderr и ненулевой код. Дата проверяется первой: 14.03.2026
# подходит и под регулярку semver без префикса.
version_format() {
  local version="$1"

  if [[ "$version" =~ $VERSION_DATE_REGEX ]]; then
    echo 'date'
  elif [[ "$version" =~ $VERSION_SEMVER_REGEX ]]; then
    echo 'semver'
  else
    echo "Version '$version' is neither a date (dd.mm.yyyy) nor a semver tag (vX.Y.Z)" >&2
    return 1
  fi
}

# version_semver_parts <vX.Y.Z> — печатает "X Y Z" через пробел (без префикса v).
# Вход должен уже соответствовать VERSION_SEMVER_REGEX — сюда попадает после version_format.
version_semver_parts() {
  local version="$1" major minor patch
  IFS='.' read -r major minor patch <<< "${version#v}"
  echo "$major $minor $patch"
}

# version_auto_label — метка авто-сборки без тега: dd.mm.yyyy-HHMM-auto по UTC.
version_auto_label() {
  date -u +'%d.%m.%Y-%H%M-auto'
}

# version_strip_ref_prefix <ref> — снимает "refs/tags/" (если он есть).
version_strip_ref_prefix() {
  local ref="$1"
  echo "${ref#refs/tags/}"
}

# version_strip_prefix <версия> <префикс> — снимает произвольный префикс тега
# (например, "v" превращает v1.2.3 в 1.2.3); пустой префикс оставляет версию как есть.
version_strip_prefix() {
  local version="$1" prefix="$2"
  echo "${version#"$prefix"}"
}

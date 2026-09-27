#!/usr/bin/env bash
# Формирует список тегов docker-образа по версии сборки; формат определяет action
# tag-format, сама лестница тегов и склейка ссылок — lib/version.sh и lib/docker.sh.
# Дата (dd.mm.yyyy, метка авто-сборки dd.mm.yyyy[-HHMM]-auto) — версия как есть + latest;
# semver (vX.Y.Z) — лестница vX.Y.Z, vX.Y, vX, latest.
# Вход (env): IMAGE, VERSION, FORMAT (date|semver, от tag-format), GITHUB_OUTPUT.
# Выход: строка "tags=<image>:<tag> ..." в файл $GITHUB_OUTPUT.
set -euo pipefail
lib="$(dirname "${BASH_SOURCE[0]}")/../../../lib"
# shellcheck source=lib/version.sh
source "$lib/version.sh"
# shellcheck source=lib/docker.sh
source "$lib/docker.sh"

image="${IMAGE:?IMAGE is required}"
version="${VERSION:?VERSION is required}"
format="${FORMAT:?FORMAT is required}"

case "$format" in
  date)
    tags=("$version" 'latest')
    ;;
  semver)
    read -r major minor patch <<< "$(version_semver_parts "$version")"
    tags=("v${major}.${minor}.${patch}" "v${major}.${minor}" "v${major}" 'latest')
    ;;
  *)
    # Внутренний контракт с tag-format: сюда попадать не должно.
    echo "Unknown FORMAT '$format'" >&2
    exit 1
    ;;
esac

refs=()
for tag in "${tags[@]}"; do
  refs+=("$(docker_ref "$image" "$tag")")
done

echo "tags=${refs[*]}" >> "$GITHUB_OUTPUT"

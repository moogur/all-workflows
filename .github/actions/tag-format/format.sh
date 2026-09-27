#!/usr/bin/env bash
# Определяет формат версии — см. lib/version.sh.
# Вход (env): VERSION, GITHUB_OUTPUT.
# Выход: строка "format=date|semver" в файл $GITHUB_OUTPUT.
set -euo pipefail
# shellcheck source=lib/version.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/version.sh"

version="${VERSION:?VERSION is required}"
format=$(version_format "$version")

echo "format=${format}" >> "$GITHUB_OUTPUT"

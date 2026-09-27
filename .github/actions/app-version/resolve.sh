#!/usr/bin/env bash
# Определяет версию приложения из git-тега и снимает префикс — см. lib/version.sh.
# Вход (env): MODE (git|ref, по умолчанию git), PREFIX (по умолчанию v), GITHUB_REF, GITHUB_OUTPUT.
# Выход: строка "version=<...>" в файл $GITHUB_OUTPUT.
set -euo pipefail
# shellcheck source=lib/version.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/version.sh"

mode="${MODE:-git}"
prefix="${PREFIX-v}"

case "$mode" in
  git)
    raw_tag=$(git describe --tags --abbrev=0)
    ;;
  ref)
    raw_tag=$(version_strip_ref_prefix "${GITHUB_REF:?GITHUB_REF is required for mode=ref}")
    ;;
  *)
    echo "Unknown mode: '$mode' (expected 'git' or 'ref')" >&2
    exit 1
    ;;
esac

echo "version=$(version_strip_prefix "$raw_tag" "$prefix")" >> "$GITHUB_OUTPUT"

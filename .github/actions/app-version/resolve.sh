#!/usr/bin/env bash
# Определяет версию приложения из git-тега и снимает префикс.
# Вход (env): MODE (git|ref, по умолчанию git), PREFIX (по умолчанию v), GITHUB_REF, GITHUB_OUTPUT.
# Выход: строка "version=<...>" в файл $GITHUB_OUTPUT.
set -euo pipefail

mode="${MODE:-git}"
prefix="${PREFIX-v}"

case "$mode" in
  git)
    raw_tag=$(git describe --tags --abbrev=0)
    ;;
  ref)
    raw_tag="${GITHUB_REF#refs/tags/}"
    ;;
  *)
    echo "Unknown mode: '$mode' (expected 'git' or 'ref')" >&2
    exit 1
    ;;
esac

echo "version=${raw_tag#"$prefix"}" >> "$GITHUB_OUTPUT"

#!/usr/bin/env bash
# Считывает версию Node.js из engines.node в package.json (в текущем каталоге).
# Выход: строка "version=<...>" в файл $GITHUB_OUTPUT.
set -euo pipefail

version=$(jq -r '.engines.node // empty' package.json)

if [[ -z "$version" ]]; then
  echo "engines.node is not set in package.json" >&2
  exit 1
fi

echo "version=$version" >> "$GITHUB_OUTPUT"

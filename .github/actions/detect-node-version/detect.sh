#!/usr/bin/env bash
# Считывает версию Node.js из engines.node в package.json (в текущем каталоге).
# Выход: строка "version=<...>" в файл $GITHUB_OUTPUT.
set -euo pipefail

echo "version=$(jq -r '.engines.node' package.json)" >> "$GITHUB_OUTPUT"

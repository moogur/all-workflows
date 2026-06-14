#!/usr/bin/env bash
# Считывает версию Go из директивы go в go.mod (в текущем каталоге).
# Выход: строка "version=<...>" в файл $GITHUB_OUTPUT.
set -euo pipefail

go_version=$(grep -m1 '^go[[:space:]]' go.mod | sed 's/.*[[:space:]]//')
echo "version=$go_version" >> "$GITHUB_OUTPUT"

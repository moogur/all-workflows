#!/usr/bin/env bash
# Создаёт .npmrc для приватного scope @moogur в GitHub Packages (в текущем каталоге).
# Вход (env): NODE_AUTH_TOKEN.
set -euo pipefail

{
  echo "@moogur:registry=https://npm.pkg.github.com/"
  echo "//npm.pkg.github.com/:_authToken=${NODE_AUTH_TOKEN}"
} > .npmrc

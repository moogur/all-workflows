#!/usr/bin/env bash
# Логинится в реестр и пушит все теги образа.
# Вход (env): REGISTRY (по умолчанию docker.pkg.github.com), GITHUB_USER, TOKEN, TAGS (через пробел).
set -euo pipefail

registry="${REGISTRY:-docker.pkg.github.com}"
github_user="${GITHUB_USER:?GITHUB_USER is required}"
token="${TOKEN:?TOKEN is required}"

read -ra tags <<< "${TAGS:?TAGS is required}"

# --password-stdin: пароль не попадает в список процессов и в лог.
echo "$token" | docker login "$registry" -u "$github_user" --password-stdin

for tag in "${tags[@]}"; do
  docker push "$tag"
done

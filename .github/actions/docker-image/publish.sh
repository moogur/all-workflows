#!/usr/bin/env bash
# Логинится в реестр и пушит все теги образа. Реестр — из lib/docker.sh, там же, где имя образа.
# Вход (env): GITHUB_USER, TOKEN, TAGS (через пробел).
set -euo pipefail
lib="$(dirname "${BASH_SOURCE[0]}")/../../../lib"
# shellcheck source=lib/docker.sh
source "$lib/docker.sh"

github_user="${GITHUB_USER:?GITHUB_USER is required}"
token="${TOKEN:?TOKEN is required}"

read -ra tags <<< "${TAGS:?TAGS is required}"

# --password-stdin: пароль не попадает в список процессов и в лог.
echo "$token" | docker login "$DOCKER_REGISTRY" -u "$github_user" --password-stdin

for tag in "${tags[@]}"; do
  docker push "$tag"
done

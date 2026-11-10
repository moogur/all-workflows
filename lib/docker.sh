# shellcheck shell=bash
#
# Реестр и имя docker-образа: ghcr.io/<user>/<repo>/<repo>. Путь в два сегмента — как у пакетов,
# которые GitHub перенёс сюда из старого docker.pkg.github.com: образы на серверах не меняют имени.
# Ссылка на конкретный тег — "<образ>:<тег>"; сам путь образа двоеточий не содержит, поэтому тег —
# это всё после последнего ':'.

# Повторное подключение в том же shell не должно падать на readonly (см. lib/commit.sh)
if [[ -z "${LIB_DOCKER_LOADED:-}" ]]; then
  readonly LIB_DOCKER_LOADED=1
  readonly DOCKER_REGISTRY='ghcr.io'
fi

# docker_image_name <user> <repo> — полное имя образа без тега.
docker_image_name() {
  local user="$1" repo="$2"
  echo "${DOCKER_REGISTRY}/${user}/${repo}/${repo}"
}

# docker_ref <образ> <тег> — полная ссылка "<образ>:<тег>".
docker_ref() {
  local image="$1" tag="$2"
  echo "${image}:${tag}"
}

# docker_ref_image <ссылка> — часть до последнего ':'.
docker_ref_image() {
  local ref="$1"
  echo "${ref%:*}"
}

# docker_ref_tag <ссылка> — часть после последнего ':'.
docker_ref_tag() {
  local ref="$1"
  echo "${ref##*:}"
}

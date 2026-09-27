# shellcheck shell=bash
#
# Имя docker-образа в этом (устаревшем, см. docs/modernization.md) реестре GitHub
# Packages: docker.pkg.github.com/<user>/<repo>/<repo>. Ссылка на конкретный тег —
# "<образ>:<тег>"; сам путь образа двоеточий не содержит, поэтому тег — это всё
# после последнего ':'.

readonly DOCKER_LEGACY_REGISTRY='docker.pkg.github.com'

# docker_image_name <user> <repo> — полное имя образа без тега.
docker_image_name() {
  local user="$1" repo="$2"
  echo "${DOCKER_LEGACY_REGISTRY}/${user}/${repo}/${repo}"
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

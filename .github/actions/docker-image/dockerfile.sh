#!/usr/bin/env bash
# Кладёт в рабочую директорию Dockerfile и .dockerignore из этого репозитория.
# Пустой DOCKERFILE — у проекта свой Dockerfile, шаг ничего не делает.
# Вход (env): DOCKERFILE, DOCKERIGNORE (имена файлов в dockerfiles/), GITHUB_ACTION_PATH.
set -euo pipefail

dockerfile="${DOCKERFILE:-}"
dockerignore="${DOCKERIGNORE:-}"

if [[ -z "$dockerfile" ]]; then
  echo 'Using the project own Dockerfile'
  exit 0
fi

# Каталог экшена лежит внутри выкачанной копии all-workflows той же версии,
# что и сам экшен: .../<ref>/.github/actions/docker-image. Берём файлы оттуда —
# так Dockerfile всегда совпадает с версией вызванного workflow, без wget с master.
sources="${GITHUB_ACTION_PATH}/../../../dockerfiles"

# copy_from_repository <имя файла> <куда>
copy_from_repository() {
  local name="$1" target="$2"

  if [[ -f "${sources}/${name}" ]]; then
    cp "${sources}/${name}" "$target"
    echo "Copied ${name} from the action checkout"
    return 0
  fi

  # Запасной путь: раскладка выкачанного экшена изменилась — тянем с master,
  # как делалось раньше. Предупреждение, чтобы это было видно в логе.
  echo "::warning::${name} not found in the action checkout, falling back to master"
  wget -q -O "$target" "https://raw.githubusercontent.com/moogur/all-workflows/master/dockerfiles/${name}"
}

copy_from_repository "$dockerfile" ./Dockerfile
[[ -z "$dockerignore" ]] || copy_from_repository "$dockerignore" ./.dockerignore

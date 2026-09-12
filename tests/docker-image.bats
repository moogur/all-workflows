#!/usr/bin/env bats
# Тесты для скриптов .github/actions/docker-image/

setup() {
  load helpers
  ROOT="$(repo_root)"
  ACTION="$ROOT/.github/actions/docker-image"
  TMP="$(mktemp -d)"
  LOG="$TMP/docker.log"
  export GITHUB_OUTPUT="$TMP/output"
  : > "$GITHUB_OUTPUT"
}

teardown() {
  rm -rf "$TMP"
}

# Заглушка команды: пишет свои аргументы в лог.
make_stub() {
  local name="$1"
  mkdir -p "$TMP/bin"
  {
    echo '#!/usr/bin/env bash'
    echo "echo \"$name \$*\" >> '$LOG'"
    # docker login читает пароль из пайпа: не вычитаешь — пишущий получит EPIPE.
    # Вычитываем только на login: там stdin всегда пайп, а не терминал.
    echo '[[ "$1" == login ]] && cat >/dev/null 2>&1'
    echo 'exit 0'
  } > "$TMP/bin/$name"
  chmod +x "$TMP/bin/$name"
}

# ---------- resolve.sh ----------

@test "resolve: сборка по тегу берёт имя тега и заданный формат" {
  run env GITHUB_USER=moogur REPOSITORY_NAME=adminer FORMAT_MODE=semver \
    REF_TYPE=tag REF_NAME=v1.2.3 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$ACTION/resolve.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "v1.2.3" ]
  [ "$(output_value format_mode)" = "semver" ]
  [ "$(output_value image)" = "docker.pkg.github.com/moogur/adminer/adminer" ]
}

@test "resolve: сборка без тега идёт датной меткой и форматом date" {
  # Иначе плановая пересборка переписала бы релизные vX.Y.Z другим содержимым.
  run env GITHUB_USER=moogur REPOSITORY_NAME=adminer FORMAT_MODE=semver \
    REF_TYPE=branch REF_NAME=master GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$ACTION/resolve.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value format_mode)" = "date" ]
  [[ "$(output_value version)" =~ ^[0-9]{2}\.[0-9]{2}\.[0-9]{4}-[0-9]{4}-auto$ ]]
}

@test "resolve: без github_user завершается с ошибкой" {
  run env REPOSITORY_NAME=adminer REF_TYPE=tag REF_NAME=v1 GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$ACTION/resolve.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"GITHUB_USER"* ]]
}

# ---------- dockerfile.sh ----------

@test "dockerfile: пустой вход оставляет Dockerfile проекта" {
  run env DOCKERFILE='' bash -c "cd '$TMP' && bash '$ACTION/dockerfile.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/Dockerfile" ]
  [[ "$output" == *"project own Dockerfile"* ]]
}

@test "dockerfile: берётся из копии репозитория рядом с экшеном" {
  # Раскладка выкачанного экшена: <ref>/.github/actions/docker-image
  local fake="$TMP/fake/.github/actions/docker-image"
  mkdir -p "$fake" "$TMP/fake/dockerfiles" "$TMP/work"
  echo 'FROM scratch' > "$TMP/fake/dockerfiles/deploy_backend.dockerfile"
  echo 'node_modules' > "$TMP/fake/dockerfiles/.dockerignore"
  cp "$ACTION"/*.sh "$fake/"

  run env DOCKERFILE=deploy_backend.dockerfile DOCKERIGNORE=.dockerignore \
    GITHUB_ACTION_PATH="$fake" bash -c "cd '$TMP/work' && bash '$fake/dockerfile.sh'"
  [ "$status" -eq 0 ]
  [ "$(cat "$TMP/work/Dockerfile")" = "FROM scratch" ]
  [ "$(cat "$TMP/work/.dockerignore")" = "node_modules" ]
}

@test "dockerfile: без файла рядом с экшеном откатывается на master с предупреждением" {
  local fake="$TMP/fake/.github/actions/docker-image"
  mkdir -p "$fake" "$TMP/work"
  cp "$ACTION"/*.sh "$fake/"
  make_stub wget

  run env PATH="$TMP/bin:$PATH" DOCKERFILE=deploy_backend.dockerfile \
    GITHUB_ACTION_PATH="$fake" bash -c "cd '$TMP/work' && bash '$fake/dockerfile.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  grep -qF "dockerfiles/deploy_backend.dockerfile" "$LOG"
}

# ---------- build.sh ----------

@test "build: версия уходит в ARG_APP_VERSION, теги — в -t" {
  make_stub docker
  run env PATH="$TMP/bin:$PATH" TAGS='image:v1.2.3 image:latest' VERSION=v1.2.3 bash "$ACTION/build.sh"
  [ "$status" -eq 0 ]
  grep -qF -- "--build-arg ARG_APP_VERSION=v1.2.3" "$LOG"
  grep -qF -- "-t image:v1.2.3 -t image:latest ." "$LOG"
}

@test "build: дополнительные build-arg приходят построчно" {
  make_stub docker
  run env PATH="$TMP/bin:$PATH" TAGS='image:v1' VERSION=v1 \
    BUILD_ARGS=$'ARG_NODE_VERSION=18.16.0\nARG_GO_VERSION=1.27' bash "$ACTION/build.sh"
  [ "$status" -eq 0 ]
  grep -qF -- "--build-arg ARG_NODE_VERSION=18.16.0" "$LOG"
  grep -qF -- "--build-arg ARG_GO_VERSION=1.27" "$LOG"
}

@test "build: пустой список тегов — ошибка" {
  make_stub docker
  run env PATH="$TMP/bin:$PATH" TAGS='' VERSION=v1 bash "$ACTION/build.sh"
  [ "$status" -ne 0 ]
}

# ---------- publish.sh ----------

@test "publish: логин через stdin и пуш каждого тега" {
  make_stub docker
  run env PATH="$TMP/bin:$PATH" GITHUB_USER=moogur TOKEN=secret \
    TAGS='image:v1.2.3 image:latest' bash "$ACTION/publish.sh"
  [ "$status" -eq 0 ]
  grep -qF -- "login docker.pkg.github.com -u moogur --password-stdin" "$LOG"
  # Токен не должен попадать в аргументы процесса.
  run grep -cF "secret" "$LOG"
  [ "$status" -ne 0 ]
  grep -qF "push image:v1.2.3" "$LOG"
  grep -qF "push image:latest" "$LOG"
}

@test "publish: без токена завершается с ошибкой" {
  make_stub docker
  run env PATH="$TMP/bin:$PATH" GITHUB_USER=moogur TAGS='image:v1' bash "$ACTION/publish.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"TOKEN"* ]]
}

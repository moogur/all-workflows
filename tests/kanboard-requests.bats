#!/usr/bin/env bats
# Тесты обёртки execute_request в scripts/kanboard_requests.sh.
# curl подменяется заглушкой: проверяем флаги, тело запроса и поведение при сбое.

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/scripts/kanboard_requests.sh"
  TMP="$(mktemp -d)"
  CURL_LOG="$TMP/curl.log"
  export CURL_STDIN="$TMP/curl.stdin" CURL_USER="$TMP/curl.user"
  : > "$CURL_LOG"
}

teardown() {
  rm -rf "$TMP"
}

# Заглушка curl: пишет аргументы в лог, а конфиг со stdin (`--config -`) разбирает по правилам
# curl (в кавычках: \\ \" \n \r \t) и кладёт значение user в $CURL_USER.
# Затем печатает ответ и возвращает заданный код.
make_curl_stub() {
  local status="${1:-0}"
  local response="${2:-\{\"result\":true\}}"
  mkdir -p "$TMP/bin"
  {
    echo '#!/usr/bin/env bash'
    echo "printf '%s\\n' \"\$*\" >> '$CURL_LOG'"
    cat <<'STUB'
case " $* " in *" --config - "*) cat > "${CURL_STDIN:?}" ;; esac
if [[ -s ${CURL_STDIN:-/nonexistent} ]]; then
  IFS= read -r line < "$CURL_STDIN"
  line=${line#user = \"}
  line=${line%\"}
  decoded=
  while [[ -n $line ]]; do
    if [[ ${line:0:1} == '\' ]]; then
      case ${line:1:1} in
        n) decoded+=$'\n' ;; r) decoded+=$'\r' ;; t) decoded+=$'\t' ;; *) decoded+=${line:1:1} ;;
      esac
      line=${line:2}
    else
      decoded+=${line:0:1}
      line=${line:1}
    fi
  done
  printf '%s' "$decoded" > "$CURL_USER"
fi
STUB
    echo "echo '$response'"
    echo "exit $status"
  } > "$TMP/bin/curl"
  chmod +x "$TMP/bin/curl"
}

# Выполняет код после source библиотеки с подменённым curl и заполненными private_*.
sh_with_stub() {
  run env PATH="$TMP/bin:$PATH" bash -c \
    "source '$LIB'; private_url='https://kb.example'; private_auth_data='user:token'; private_task_id=42; $*"
}

@test "успешный запрос отдаёт ответ в stdout" {
  make_curl_stub 0 '{"result":777}'
  sh_with_stub "execute_request '{\"method\":\"getTask\"}'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == 777' >/dev/null
}

@test "запрос уходит с таймаутами и ретраями" {
  make_curl_stub 0
  sh_with_stub "execute_request '{}'"
  grep -qF -- "--connect-timeout 10" "$CURL_LOG"
  grep -qF -- "--max-time 30" "$CURL_LOG"
  grep -qF -- "--retry 3" "$CURL_LOG"
  grep -qF -- "--retry-connrefused" "$CURL_LOG"
  grep -qF -- "--retry-all-errors" "$CURL_LOG"
}

@test "HTTP-ошибки не выглядят успехом (-f)" {
  make_curl_stub 0
  sh_with_stub "execute_request '{}'"
  grep -qF -- "-fsS" "$CURL_LOG"
}

@test "запрос идёт на jsonrpc.php с авторизацией и телом" {
  make_curl_stub 0
  sh_with_stub "execute_request '{\"method\":\"getTask\"}'"
  grep -qF "https://kb.example/jsonrpc.php" "$CURL_LOG"
  [ "$(cat "$CURL_USER")" = "user:token" ]
  grep -qF '{"method":"getTask"}' "$CURL_LOG"
}

@test "недоступный Kanboard: ненулевой код и сообщение" {
  make_curl_stub 28
  sh_with_stub "execute_request '{}'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Kanboard request failed"* ]]
  [[ "$output" == *"https://kb.example/jsonrpc.php"* ]]
}

@test "функции запросов ходят через обёртку" {
  make_curl_stub 0 '{"result":{"id":42}}'
  sh_with_stub "request_for_get_info_task"
  [ "$status" -eq 0 ]
  # task_id по умолчанию берётся из private_task_id
  grep -qF '"task_id": 42' "$CURL_LOG"
  grep -qF -- "--retry 3" "$CURL_LOG"
}

# ---------- значения из окружения (без sed в исполняемый файл) ----------

# Как sh_with_stub, но private_* приходят только из env, как в kanboard.yml.
sh_with_env() {
  run env PATH="$TMP/bin:$PATH" \
    KANBOARD_URL='https://kb.example' KANBOARD_USER='user' KANBOARD_TOKEN='token' \
    KANBOARD_TASK_ID=42 KANBOARD_PROJECT_ID=7 KANBOARD_SWIMLANE_ID=3 \
    bash -c "source '$LIB'; $*"
}

@test "env: URL, user:token, task/project/swimlane читаются из окружения" {
  make_curl_stub 0
  sh_with_env "request_for_move_task 5"
  [ "$status" -eq 0 ]
  grep -qF "https://kb.example/jsonrpc.php" "$CURL_LOG"
  [ "$(cat "$CURL_USER")" = "user:token" ]
  grep -qF '"task_id": 42' "$CURL_LOG"
  grep -qF '"project_id": 7' "$CURL_LOG"
  grep -qF '"swimlane_id": 3' "$CURL_LOG"
}

@test "env: подстановка команды в KANBOARD_TASK_ID не выполняется и запрос не уходит" {
  make_curl_stub 0
  local marker="$TMP/pwned"
  run env PATH="$TMP/bin:$PATH" KANBOARD_URL='https://kb.example' \
    KANBOARD_TASK_ID="\$(touch $marker)" \
    bash -c "source '$LIB'; request_for_get_info_task"
  [ "$status" -ne 0 ]
  [ ! -e "$marker" ]
  [ ! -s "$CURL_LOG" ]
}

@test "env: подстановка команды в KANBOARD_URL и токен не выполняется при source" {
  local marker="$TMP/pwned"
  run env KANBOARD_URL="\$(touch $marker)" KANBOARD_TOKEN="\$(touch $marker)" \
    bash -c "source '$LIB'"
  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
}

@test "без окружения: запрос без task_id не уходит (нет id по умолчанию)" {
  make_curl_stub 0
  run env -u KANBOARD_TASK_ID PATH="$TMP/bin:$PATH" bash -c "source '$LIB'; request_for_get_info_task"
  [ "$status" -ne 0 ]
  [ ! -s "$CURL_LOG" ]
}

# ---------- учётные данные не попадают в argv ----------

@test "логин и токен идут через stdin-конфиг, а не аргументами curl" {
  make_curl_stub 0
  run env PATH="$TMP/bin:$PATH" KANBOARD_URL='https://kb.example' \
    KANBOARD_USER='alice' KANBOARD_TOKEN='s3cret-tok' \
    bash -c "source '$LIB'; execute_request '{}'"
  [ "$status" -eq 0 ]
  grep -qF -- "--config -" "$CURL_LOG"
  ! grep -qF "alice" "$CURL_LOG"
  ! grep -qF "s3cret-tok" "$CURL_LOG"
  ! grep -qE -- '(^| )-u( |$)|--user' "$CURL_LOG"
  grep -qxF 'user = "alice:s3cret-tok"' "$CURL_STDIN"
}

@test "прочие флаги curl сохранены вместе с конфигом" {
  make_curl_stub 0
  sh_with_stub "execute_request '{}'"
  grep -qF -- "-fsS" "$CURL_LOG"
  grep -qF -- "--retry-all-errors" "$CURL_LOG"
  grep -qF -- "--max-time 30" "$CURL_LOG"
}

@test "токен с кавычкой и обратным слэшем доходит до curl без искажений" {
  make_curl_stub 0
  local token='a"b\c\"d'
  run env PATH="$TMP/bin:$PATH" KANBOARD_URL='https://kb.example' \
    KANBOARD_USER='alice' KANBOARD_TOKEN="$token" \
    bash -c "source '$LIB'; execute_request '{}'"
  [ "$status" -eq 0 ]
  [ "$(cat "$CURL_USER")" = "alice:$token" ]
  # Конфиг остался одной строкой с одной директивой.
  [ "$(wc -l < "$CURL_STDIN")" -eq 1 ]
}

@test "перевод строки в токене не создаёт вторую директиву конфига" {
  make_curl_stub 0
  local token=$'abc\nurl = "https://evil.example"'
  run env PATH="$TMP/bin:$PATH" KANBOARD_URL='https://kb.example' \
    KANBOARD_USER='alice' KANBOARD_TOKEN="$token" \
    bash -c "source '$LIB'; execute_request '{}'"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CURL_STDIN")" -eq 1 ]
  [ "$(cat "$CURL_USER")" = "alice:$token" ]
}

@test "учётные данные не лежат в файле на диске: конфиг читается только из stdin" {
  make_curl_stub 0
  sh_with_stub "execute_request '{}'"
  ! grep -qE -- '(^| )(-K|--config) [^-]' "$CURL_LOG"
}

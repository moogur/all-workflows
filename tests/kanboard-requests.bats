#!/usr/bin/env bats
# Тесты обёртки execute_request в scripts/kanboard_requests.sh.
# curl подменяется заглушкой: проверяем флаги, тело запроса и поведение при сбое.

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/scripts/kanboard_requests.sh"
  TMP="$(mktemp -d)"
  CURL_LOG="$TMP/curl.log"
  : > "$CURL_LOG"
}

teardown() {
  rm -rf "$TMP"
}

# Заглушка curl: пишет аргументы в лог, печатает ответ и возвращает заданный код.
make_curl_stub() {
  local status="${1:-0}"
  local response="${2:-\{\"result\":true\}}"
  mkdir -p "$TMP/bin"
  {
    echo '#!/usr/bin/env bash'
    echo "printf '%s\\n' \"\$*\" >> '$CURL_LOG'"
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
  grep -qF "user:token" "$CURL_LOG"
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
  grep -qF "user:token" "$CURL_LOG"
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

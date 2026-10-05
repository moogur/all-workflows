#!/usr/bin/env bats
# Тесты обёртки execute_request и функций request_* в scripts/kaneo/requests.sh.
# curl подменяется заглушкой: проверяем флаги, метод, адрес, тело и поведение при сбое.

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/scripts/kaneo/requests.sh"
  TMP="$(mktemp -d)"
  CURL_LOG="$TMP/curl.log"
  export CURL_STDIN="$TMP/curl.stdin" CURL_AUTH="$TMP/curl.auth"
  : > "$CURL_LOG"
}

teardown() {
  rm -rf "$TMP"
}

# Заглушка curl: пишет аргументы в лог, а конфиг со stdin (`--config -`) разбирает по правилам
# curl (в кавычках: \\ \" \n \r \t) и кладёт значение заголовка Authorization в $CURL_AUTH.
# Затем печатает ответ и возвращает заданный код.
make_curl_stub() {
  local status="${1:-0}"
  local response="${2:-\{\"id\":\"tid1\"\}}"
  mkdir -p "$TMP/bin"
  {
    echo '#!/usr/bin/env bash'
    echo "printf '%s\\n' \"\$*\" >> '$CURL_LOG'"
    cat <<'STUB'
case " $* " in *" --config - "*) cat > "${CURL_STDIN:?}" ;; esac
if [[ -s ${CURL_STDIN:-/nonexistent} ]]; then
  IFS= read -r line < "$CURL_STDIN"
  line=${line#header = \"Authorization: Bearer }
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
  printf '%s' "$decoded" > "$CURL_AUTH"
fi
STUB
    echo "echo '$response'"
    echo "exit $status"
  } > "$TMP/bin/curl"
  chmod +x "$TMP/bin/curl"
}

# Выполняет код после source библиотеки; URL и токен приходят только из env, как в kaneo.yml.
sh_with_env() {
  run env PATH="$TMP/bin:$PATH" KANEO_URL='https://kaneo.example' KANEO_TOKEN='token' \
    bash -c "source '$LIB'; $*"
}

@test "успешный запрос отдаёт ответ в stdout" {
  make_curl_stub 0 '{"status":"todo"}'
  sh_with_env "execute_request GET /api/x"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "todo"' >/dev/null
}

@test "запрос уходит с таймаутами и ретраями" {
  make_curl_stub 0
  sh_with_env "execute_request GET /api/x"
  grep -qF -- "--connect-timeout 10" "$CURL_LOG"
  grep -qF -- "--max-time 30" "$CURL_LOG"
  grep -qF -- "--retry 3" "$CURL_LOG"
  grep -qF -- "--retry-delay 5" "$CURL_LOG"
  grep -qF -- "--retry-connrefused" "$CURL_LOG"
  grep -qF -- "--retry-all-errors" "$CURL_LOG"
}

@test "HTTP-ошибки не выглядят успехом (-f)" {
  make_curl_stub 0
  sh_with_env "execute_request GET /api/x"
  grep -qF -- "-fsS" "$CURL_LOG"
}

@test "метод и адрес: <url>/api/... с методом из аргумента" {
  make_curl_stub 0
  sh_with_env "execute_request PUT /api/task/status/tid1 '{\"status\":\"x\"}'"
  grep -qF -- "-X PUT" "$CURL_LOG"
  grep -qF "https://kaneo.example/api/task/status/tid1" "$CURL_LOG"
  grep -qF -- '-d {"status":"x"}' "$CURL_LOG"
  grep -qF -- "Content-Type: application/json" "$CURL_LOG"
}

@test "запрос без тела уходит без -d и Content-Type" {
  make_curl_stub 0
  sh_with_env "execute_request GET /api/x"
  ! grep -qF -- " -d " "$CURL_LOG"
  ! grep -qF -- "Content-Type" "$CURL_LOG"
}

@test "слэш в конце KANEO_URL не удваивается в адресе" {
  make_curl_stub 0
  run env PATH="$TMP/bin:$PATH" KANEO_URL='https://kaneo.example/' KANEO_TOKEN='token' \
    bash -c "source '$LIB'; execute_request GET /api/x"
  grep -qF "https://kaneo.example/api/x" "$CURL_LOG"
}

@test "недоступный Kaneo: ненулевой код и сообщение без токена" {
  make_curl_stub 28
  sh_with_env "execute_request GET /api/x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Kaneo request failed: GET /api/x"* ]]
  [[ "$output" != *"token"* ]]
}

# ---------- токен не попадает в argv ----------

@test "токен идёт через stdin-конфиг как Bearer, а не аргументом curl" {
  make_curl_stub 0
  run env PATH="$TMP/bin:$PATH" KANEO_URL='https://kaneo.example' KANEO_TOKEN='s3cret-tok' \
    bash -c "source '$LIB'; execute_request GET /api/x"
  [ "$status" -eq 0 ]
  grep -qF -- "--config -" "$CURL_LOG"
  ! grep -qF "s3cret-tok" "$CURL_LOG"
  ! grep -qiF "Authorization" "$CURL_LOG"
  grep -qxF 'header = "Authorization: Bearer s3cret-tok"' "$CURL_STDIN"
}

@test "токен с кавычкой и обратным слэшем доходит до curl без искажений" {
  make_curl_stub 0
  local token='a"b\c\"d'
  run env PATH="$TMP/bin:$PATH" KANEO_URL='https://kaneo.example' KANEO_TOKEN="$token" \
    bash -c "source '$LIB'; execute_request GET /api/x"
  [ "$status" -eq 0 ]
  [ "$(cat "$CURL_AUTH")" = "$token" ]
  [ "$(wc -l < "$CURL_STDIN")" -eq 1 ]
}

@test "перевод строки в токене не создаёт вторую директиву конфига" {
  make_curl_stub 0
  local token=$'abc\nurl = "https://evil.example"'
  run env PATH="$TMP/bin:$PATH" KANEO_URL='https://kaneo.example' KANEO_TOKEN="$token" \
    bash -c "source '$LIB'; execute_request GET /api/x"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CURL_STDIN")" -eq 1 ]
  [ "$(cat "$CURL_AUTH")" = "$token" ]
}

@test "конфиг curl читается только из stdin, а не из файла на диске" {
  make_curl_stub 0
  sh_with_env "execute_request GET /api/x"
  ! grep -qE -- '(^| )(-K|--config) [^-]' "$CURL_LOG"
}

# ---------- функции запросов: маршруты ----------

@test "request_get_task: GET /api/task/by-ticket-id/<номер>" {
  make_curl_stub 0
  sh_with_env "request_get_task GA-25"
  [ "$status" -eq 0 ]
  grep -qF "https://kaneo.example/api/task/by-ticket-id/GA-25" "$CURL_LOG"
  grep -qF -- "-X GET" "$CURL_LOG"
}

@test "request_move_task: PUT /api/task/status/<id> с телом {status}" {
  make_curl_stub 0
  sh_with_env "request_move_task tid1 in-progress"
  [ "$status" -eq 0 ]
  grep -qF -- "-X PUT" "$CURL_LOG"
  grep -qF "https://kaneo.example/api/task/status/tid1" "$CURL_LOG"
  grep -qF '"status": "in-progress"' "$CURL_LOG"
}

@test "request_get_project_fields: GET /api/custom-field/project/<id>" {
  make_curl_stub 0
  sh_with_env "request_get_project_fields pid1"
  grep -qF "https://kaneo.example/api/custom-field/project/pid1" "$CURL_LOG"
}

@test "request_get_task_fields: GET /api/custom-field/task/<id>" {
  make_curl_stub 0
  sh_with_env "request_get_task_fields tid1"
  grep -qF "https://kaneo.example/api/custom-field/task/tid1" "$CURL_LOG"
}

@test "request_set_field_value: PUT /api/custom-field/value с taskId, fieldId, value" {
  make_curl_stub 0
  sh_with_env "request_set_field_value tid1 fid1 1.2.3"
  grep -qF -- "-X PUT" "$CURL_LOG"
  grep -qF "https://kaneo.example/api/custom-field/value" "$CURL_LOG"
  grep -qF '"taskId": "tid1"' "$CURL_LOG"
  grep -qF '"fieldId": "fid1"' "$CURL_LOG"
  grep -qF '"value": "1.2.3"' "$CURL_LOG"
}

# ---------- небезопасные значения: запрос не уходит ----------

@test "request_get_task: номер не по формату не уходит в URL" {
  make_curl_stub 0
  sh_with_env "request_get_task 'GA-1/../x'"
  [ "$status" -ne 0 ]
  [ ! -s "$CURL_LOG" ]
}

@test "request_move_task: небезопасный id и пустой статус не уходят" {
  make_curl_stub 0
  sh_with_env "request_move_task 'a/b' x"
  [ "$status" -ne 0 ]
  sh_with_env "request_move_task tid1 ''"
  [ "$status" -ne 0 ]
  [ ! -s "$CURL_LOG" ]
}

@test "request_get_*_fields и request_set_field_value: небезопасный id не уходит" {
  make_curl_stub 0
  sh_with_env "request_get_project_fields 'p?x=1'"
  [ "$status" -ne 0 ]
  sh_with_env "request_get_task_fields ''"
  [ "$status" -ne 0 ]
  sh_with_env "request_set_field_value 't;id' fid1 v"
  [ "$status" -ne 0 ]
  [ ! -s "$CURL_LOG" ]
}

@test "подстановка команды в KANEO_URL и токене не выполняется при source" {
  local marker="$TMP/pwned"
  run env KANEO_URL="\$(touch $marker)" KANEO_TOKEN="\$(touch $marker)" \
    bash -c "source '$LIB'"
  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
}

@test "env: данные текущей задачи из окружения не читаются, на старте пусты" {
  run env KANEO_TASK_KEY=GA-25 KANEO_TASK_ID=tid1 KANEO_PROJECT_ID=pid1 KANEO_WORKSPACE_ID=wid1 \
    bash -c "source '$LIB'; echo \"[\$private_task_key\$private_task_id\$private_project_id\$private_workspace_id]\""
  [ "$output" = "[]" ]
}

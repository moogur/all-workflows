# shellcheck shell=bash disable=SC2034
# Часть private_* читает только messages.sh, подключаемый следом: shellcheck не видит
# этого через границу файлов.
#
# Библиотека запросов к Kaneo REST API (<host>/api/...).
# Подключается из scripts/kaneo/engine.sh (workflow kaneo.yml) через `source` прямо из чекаута all-workflows
# (поэтому здесь нет shebang, а указана директива shellcheck shell=bash).
# Значения private_* читаются из переменных окружения, которые задаёт шаг workflow
# (`env:`). Подставлять их в файл через sed нельзя: файл потом исполняется, и значение
# вида $(cmd) выполнилось бы на раннере вместе с секретами (docs/security.md, п. 8).

# shellcheck source=lib/commit.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/commit.sh"
# shellcheck source=lib/kaneo.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/kaneo.sh"

private_url=${KANEO_URL:-}
private_url=${private_url%/}                  # базовый URL Kaneo, запросы идут на <url>/api/...
private_token=${KANEO_TOKEN:-}                # API-ключ, уходит в curl через stdin-конфиг
# Текущая задача: заполняет engine (kaneo_use_task), читает messages.sh; из env не берётся.
private_task_key=''
private_task_id=''
private_project_id=''
private_workspace_id=''  # id рабочего пространства (для ссылки на задачу)

# require_kaneo_id <имя поля> <значение> — отказ (код 1, сообщение в stderr), если значение
# не id Kaneo. Само значение не печатаем: оно может быть недоверенным.
require_kaneo_id() {
  if ! kaneo_id_valid "$2"; then
    echo "Kaneo: $1 is not a valid id, request not built" >&2
    return 1
  fi
}

# --- Генераторы тела запроса (печатают JSON в stdout, JSON строит jq) ---

# generate_post_data_for_move_task <статус (slug колонки)>
generate_post_data_for_move_task() {
  if [[ -z "$1" ]]; then
    echo "Kaneo: status is empty, request not built" >&2
    return 1
  fi
  jq -n --arg status "$1" '{status: $status}'
}

# generate_post_data_for_set_field_value <id задачи> <id поля> <значение>
generate_post_data_for_set_field_value() {
  require_kaneo_id task_id "$1" && require_kaneo_id field_id "$2" || return 1
  jq -n --arg taskId "$1" --arg fieldId "$2" --arg value "$3" \
    '{taskId: $taskId, fieldId: $fieldId, value: $value}'
}

# --- Выполнение запросов (curl на <url>/api/...), печатают ответ в stdout ---

# curl_config_escape <строка> — экранирует строку для значения в кавычках в конфиге curl:
# \ и " ломали бы строку `header = "..."`, а перевод строки начал бы в конфиге новую директиву.
curl_config_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

# execute_request <метод> <путь> [тело JSON] — единая обёртка над curl. Kaneo живёт на
# самохостинге и бывает недоступен: без таймаутов запрос висел на TCP-коннекте дольше двух
# минут, без ретраев падал от короткой сетевой икоты, а без -f любой 5xx выглядел успехом.
# Ошибка идёт в stderr (в stdout только ответ — его читает вызывающий код).
# Токен идёт в curl конфигом через stdin (`--config -`): ни в argv (виден в списке
# процессов), ни в файле на диске его нет. Конфиг печатает builtin printf в pipe —
# heredoc/here-string в старом bash создаёт временный файл.
execute_request() {
  local method=$1 path=$2 data=${3:-}
  local response
  local -a args=(-fsS --config -
    --connect-timeout 10 --max-time 30
    --retry 3 --retry-delay 5 --retry-connrefused --retry-all-errors
    -X "$method")

  if [[ -n "$data" ]]; then
    args+=(-H 'Content-Type: application/json' -d "$data")
  fi

  if ! response=$(printf 'header = "Authorization: Bearer %s"\n' "$(curl_config_escape "$private_token")" \
    | curl "${args[@]}" "$private_url$path"); then
    echo "Kaneo request failed: $method $path" >&2
    return 1
  fi

  echo "$response"
}

# request_get_task <номер задачи GA-25> — данные задачи (id, projectId, workspaceId, status).
request_get_task() {
  if ! commit_task_key_valid "$1"; then
    echo "Kaneo: task key is not valid, request not built" >&2
    return 1
  fi
  execute_request GET "/api/task/by-ticket-id/$1"
}

# request_move_task <id задачи> <статус> — перенос задачи в колонку.
request_move_task() {
  local data
  require_kaneo_id task_id "$1" || return 1
  data=$(generate_post_data_for_move_task "$2") || return 1
  execute_request PUT "/api/task/status/$1" "$data"
}

# request_get_project_fields <id проекта> — определения пользовательских полей проекта.
request_get_project_fields() {
  require_kaneo_id project_id "$1" || return 1
  execute_request GET "/api/custom-field/project/$1"
}

# request_get_task_fields <id задачи> — значения полей задачи (только заполненные).
request_get_task_fields() {
  require_kaneo_id task_id "$1" || return 1
  execute_request GET "/api/custom-field/task/$1"
}

# request_set_field_value <id задачи> <id поля> <значение>
request_set_field_value() {
  local data
  data=$(generate_post_data_for_set_field_value "$1" "$2" "$3") || return 1
  execute_request PUT "/api/custom-field/value" "$data"
}

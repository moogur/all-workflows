# shellcheck shell=bash
#
# Библиотека функций для работы с Kanboard JSON-RPC API.
# Подключается workflow'ом kanboard.yml через `source` прямо из чекаута all-workflows
# (поэтому здесь нет shebang, а указана директива shellcheck shell=bash).
# Значения private_* читаются из переменных окружения, которые задаёт шаг workflow
# (`env:`). Подставлять их в файл через sed нельзя: файл потом исполняется, и значение
# вида $(cmd) выполнилось бы на раннере вместе с секретами (docs/security.md, п. 8).

# shellcheck source=lib/commit.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/commit.sh"

private_url=${KANBOARD_URL:-}                                 # базовый URL Kanboard (запросы идут на <url>/jsonrpc.php)
private_auth_data=${KANBOARD_USER:-}:${KANBOARD_TOKEN:-}      # "<user>:<token>" для curl -u
private_task_id=${KANBOARD_TASK_ID:-}                         # id текущей задачи (значение по умолчанию для функций)
private_project_id=${KANBOARD_PROJECT_ID:-}                   # id проекта (по умолчанию)
private_swimlane_id=${KANBOARD_SWIMLANE_ID:-}                 # id дорожки (по умолчанию)
private_file_path=./message.tmpl  # файл-отчёт, выводится в лог в конце workflow

# require_numeric_id <имя поля> <значение> — отказ (код 1, сообщение в stderr), если id не
# число. Само значение не печатаем: оно может быть недоверенным.
function require_numeric_id() {
  if ! commit_task_id_valid "$2"; then
    echo "Kanboard: $1 is not a numeric id, request not built" >&2
    return 1
  fi
}

# --- Генераторы тела JSON-RPC запроса (печатают JSON в stdout) ---
# Числовые поля проверяются до сборки; JSON строит jq, строки не склеиваются.
# При невалидном id — код 1 и пустой stdout.

function generate_post_data_for_move_task() {
  local column_id=$1
  local task_id=$2
  local position=$3
  local project_id=$4
  local swimlane_id=$5

  [[ -n $task_id ]] || task_id=$private_task_id
  [[ -n $position ]] || position=100
  [[ -n $project_id ]] || project_id=$private_project_id
  [[ -n $swimlane_id ]] || swimlane_id=$private_swimlane_id

  require_numeric_id column_id "$column_id" &&
    require_numeric_id task_id "$task_id" &&
    require_numeric_id position "$position" &&
    require_numeric_id project_id "$project_id" &&
    require_numeric_id swimlane_id "$swimlane_id" || return 1

  jq -n \
    --arg column_id "$column_id" --arg task_id "$task_id" --arg position "$position" \
    --arg project_id "$project_id" --arg swimlane_id "$swimlane_id" \
    '{jsonrpc: "2.0", id: 1, method: "moveTaskPosition", params: {
      project_id: ($project_id | tonumber),
      task_id: ($task_id | tonumber),
      column_id: ($column_id | tonumber),
      position: ($position | tonumber),
      swimlane_id: ($swimlane_id | tonumber)}}'
}

function generate_post_data_for_get_info_task() {
  local task_id=$1

  require_numeric_id task_id "$task_id" || return 1

  jq -n --arg task_id "$task_id" \
    '{jsonrpc: "2.0", id: 1, method: "getTask", params: {task_id: ($task_id | tonumber)}}'
}

function generate_post_data_for_get_metadata_task() {
  local task_id=$1

  require_numeric_id task_id "$task_id" || return 1

  jq -n --arg task_id "$task_id" \
    '{jsonrpc: "2.0", id: 1, method: "getTaskMetadataByName", params: {name: "App_version", task_id: ($task_id | tonumber)}}'
}

function generate_post_data_for_update_task_app_version() {
  local task_id=$1
  local app_version=$2

  require_numeric_id task_id "$task_id" || return 1

  jq -n --arg task_id "$task_id" --arg app_version "$app_version" \
    '{jsonrpc: "2.0", id: 1, method: "saveTaskMetadata", params: {task_id: ($task_id | tonumber), values: {App_version: $app_version}}}'
}

# --- Выполнение запросов (curl на <url>/jsonrpc.php), печатают ответ в stdout ---

# Единая обёртка над curl. Kanboard живёт на самохостинге и бывает недоступен:
# без таймаутов запрос висел на TCP-коннекте больше двух минут, без ретраев
# падал от короткой сетевой икоты, а без -f любой 5xx выглядел как успех.
# Ошибка идёт в stderr (в stdout только ответ — его читает вызывающий код).
function execute_request() {
  local data=$1
  local response

  if ! response=$(curl -fsS \
    --connect-timeout 10 --max-time 30 \
    --retry 3 --retry-delay 5 --retry-connrefused --retry-all-errors \
    -u "$private_auth_data" -d "$data" "$private_url/jsonrpc.php"); then
    echo "Kanboard request failed: $private_url/jsonrpc.php" >&2
    return 1
  fi

  echo "$response"
}

function request_for_move_task() {
  local column_id=$1
  local task_id=$2
  local position=$3
  local project_id=$4
  local swimlane_id=$5

  local data
  data=$(generate_post_data_for_move_task "$column_id" "$task_id" "$position" "$project_id" "$swimlane_id") || return 1
  execute_request "$data"
}

function request_for_get_info_task() {
  local task_id=$1

  if [[ -z $task_id ]]; then
    task_id=$private_task_id
  fi

  local data
  data=$(generate_post_data_for_get_info_task "$task_id") || return 1
  execute_request "$data"
}

function request_for_get_metadata_task() {
  local task_id=$1

  local data
  data=$(generate_post_data_for_get_metadata_task "$task_id") || return 1
  execute_request "$data"
}

function request_for_update_task_app_version() {
  local task_id=$1
  local app_version=$2

  local data
  data=$(generate_post_data_for_update_task_app_version "$task_id" "$app_version") || return 1
  execute_request "$data"
}

# --- Формирование человекочитаемого отчёта в $private_file_path (message.tmpl) ---
# result == "true" трактуется как успех, любое другое значение — как ошибка.

function save_message_header_in_file() {
  local result=$1

  if [[ "$result" == "true" ]]; then
    echo "SUCCESS" >> $private_file_path
  else
    echo "ERROR" >> $private_file_path
  fi

  echo "" >> $private_file_path
}

function save_task_link_in_file() {
  local task_id=$1

  echo "Link to the task - $private_url/?controller=TaskViewController&action=show&task_id=$task_id" >> $private_file_path
}

function save_separator_in_file() {
  if [[ -f $private_file_path ]]; then
    echo "----------" >> $private_file_path
  else
    touch $private_file_path
  fi
}

function save_raw_message_in_file() {
  local raw_message=$1
  local result=$2

  if [[ "$result" != "true" ]]; then
    echo "Raw error - '$raw_message'" >> $private_file_path
  fi
}

function save_message_in_file() {
  local column_name=$1
  local task_id=$2
  local raw_message=$3
  local result=$4

  if [[ $task_id == "-1" ]]; then
    task_id=$private_task_id
  fi

  save_separator_in_file
  save_message_header_in_file "$result"

  case $result in
    true)
      echo "The task with id $task_id has been successfully moved to the '$column_name' column" >> $private_file_path
      ;;

    false)
      echo "An error occurred when moving a task with id $task_id to the '$column_name' column" >> $private_file_path
      ;;

    *)
      echo "An unknown error occurred when moving the task from id $task_id to the '$column_name' column" >> $private_file_path
      ;;
  esac

  save_raw_message_in_file "$raw_message" "$result"
  save_task_link_in_file "$task_id"
}

function save_message_in_file_for_deploy_get_task_info_error() {
  local task_id=$1
  local raw_message=$2

  save_separator_in_file

  save_message_header_in_file
  echo "An error occurred while getting information about a task with id $task_id" >> $private_file_path
  save_raw_message_in_file "$raw_message"
  save_task_link_in_file "$task_id"
}

function save_message_in_file_for_add_app_version() {
  local task_id=$1
  local raw_message=$2
  local result=$3

  save_separator_in_file
  save_message_header_in_file "$result"

  case $result in
    true)
      echo "For a task with id $task_id, a version has been added" >> $private_file_path
      ;;

    false)
      echo "An error occurred when adding a version to a task with id $task_id" >> $private_file_path
      ;;

    *)
      echo "An unknown error occurred when adding a version to a task with id $task_id" >> $private_file_path
      ;;
  esac

  save_raw_message_in_file "$raw_message" "$result"
  save_task_link_in_file "$task_id"
}

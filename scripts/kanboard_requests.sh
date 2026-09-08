# shellcheck shell=bash
#
# Библиотека функций для работы с Kanboard JSON-RPC API.
# Скачивается workflow'ом kanboard.yml через wget и подключается через `source`
# (поэтому здесь нет shebang, а указана директива shellcheck shell=bash).
# Значения private_* подставляются в этот файл через sed перед использованием.

private_url=             # базовый URL инстанса Kanboard (запросы идут на <url>/jsonrpc.php)
private_auth_data=       # "<user>:<token>" для curl -u
private_task_id=         # id текущей задачи (значение по умолчанию для функций)
private_project_id=      # id проекта (по умолчанию)
private_swimlane_id=     # id дорожки (по умолчанию)
private_file_path=./message.tmpl  # файл-отчёт, выводится в лог в конце workflow

# --- Генераторы тела JSON-RPC запроса (печатают JSON в stdout) ---

function generate_post_data_for_move_task() {
  local column_id=$1
  local task_id=$2
  local position=$3
  local project_id=$4
  local swimlane_id=$5

  if [[ -z $task_id ]]; then
    task_id=$private_task_id
  fi

  if [[ -z $position ]]; then
    position=100
  fi

  if [[ -z $project_id ]]; then
    project_id=$private_project_id
  fi

  if [[ -z $swimlane_id ]]; then
    swimlane_id=$private_swimlane_id
  fi

  cat <<EOF
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "moveTaskPosition",
  "params": {
    "project_id": $project_id,
    "task_id": $task_id,
    "column_id": $column_id,
    "position": $position,
    "swimlane_id": $swimlane_id
  }
}
EOF
}

function generate_post_data_for_get_info_task() {
  local task_id=$1

  cat <<EOF
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "getTask",
  "params": {
    "task_id": $task_id
  }
}
EOF
}

function generate_post_data_for_get_metadata_task() {
  local task_id=$1

  cat <<EOF
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "getTaskMetadataByName",
  "params": {
    "name": "App_version",
    "task_id": $task_id
  }
}
EOF
}

function generate_post_data_for_update_task_app_version() {
  local task_id=$1
  local app_version=$2

  cat <<EOF
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "saveTaskMetadata",
  "params": {
    "task_id": $task_id,
    "values": {
      "App_version": "$app_version"
    }
  }
}
EOF
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

  execute_request "$(generate_post_data_for_move_task "$column_id" "$task_id" "$position" "$project_id" "$swimlane_id")"
}

function request_for_get_info_task() {
  local task_id=$1

  if [[ -z $task_id ]]; then
    task_id=$private_task_id
  fi

  execute_request "$(generate_post_data_for_get_info_task "$task_id")"
}

function request_for_get_metadata_task() {
  local task_id=$1

  execute_request "$(generate_post_data_for_get_metadata_task "$task_id")"
}

function request_for_update_task_app_version() {
  local task_id=$1
  local app_version=$2

  execute_request "$(generate_post_data_for_update_task_app_version "$task_id" "$app_version")"
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

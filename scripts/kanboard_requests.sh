private_url=
private_auth_data=
private_task_id=
private_project_id=
private_swimlane_id=

function generate_post_data_for_move_task() {
  local column_id=$1
  local task_id=$2
  local position=$3

  if [[-z $task_id ]];then
    task_id=$private_task_id
  fi

  if [[-z $position ]];then
    position=100
  fi

  cat <<EOF
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "moveTaskPosition",
  "params": {
    "project_id": $private_project_id,
    "task_id": $task_id,
    "column_id": $column_id,
    "position": $position,
    "swimlane_id": $private_swimlane_id
  }
}
EOF
}

function request_for_move_task() {
  local column_id=$1
  local task_id=$2
  local position=$3

  result=$(curl -u "$auth_data" -d "$(generate_post_data $column $task_id $position)" $url/jsonrpc.php)
  echo $result
}

function request_for_get_info_task() {
  local task_id=$1

  if [[-z $task_id ]];then
    task_id=$private_task_id
  fi

  result=$(curl -u "$auth_data" -d "{\"task_id\":$task_id}" $url/jsonrpc.php)
  echo $result
}

function generate_post_data_for_update_task_app_version() {
  local task_id=$1
  local app_version=$2

  cat <<EOF
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "updateTask",
  "params": {
    "task_id": $task_id,
    "metamagikkey_App_version": $app_version
  }
}
EOF
}

function request_for_update_task_app_version() {
  local task_id=$1
  local app_version=$2

  result=$(curl -u "$auth_data" -d "$(generate_post_data_for_update_task_app_version $task_id $app_version)" $url/jsonrpc.php)
  echo $result
}

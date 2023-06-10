private_url=
private_auth_data=
private_task_id=
private_project_id=
private_swimlane_id=
private_file_path=./message.tmpl

function generate_post_data_for_move_task() {
  local column_id=$1
  local task_id=$2
  local position=$3

  if [[-z $task_id ]];then
    task_id=$private_task_id
  fi

  if [[ -z $position ]];then
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

  if [[ -z $task_id ]];then
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
    "metamagikkey_App_version": "$app_version"
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

function save_message_header_in_file() {
  local result=$1

  if [[ $result == 'true' ]]; then
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

function save_message_in_file() {
  local column_name=$1
  local task_id=$2
  local result=$3

  if [[ $task_id == "-1" ]];then
    task_id=$private_task_id
  fi

  save_message_header_in_file $result

  case $result in
    true)
      echo "The task with id $task_id has been successfully moved to the '$column_name' column" >> $private_file_path
      ;;

    false)
      echo "An error occurred when moving a task with id $task_id to the '$column_name' column" >> $private_file_path
      ;;

    *)
      echo "An unknown error occurred when moving the task from id $task_id to the column" >> $private_file_path
      ;;
  esac

  save_task_link_in_file $task_id
}

function save_message_in_file_for_deploy_get_task_info_error() {
  local task_id=$1

  save_separator_in_file

  save_message_header_in_file
  echo "An error occurred while getting information about a task with id $task_id" >> $private_file_path
  save_task_link_in_file $task_id
}

function save_message_in_file_for_add_app_version() {
  local task_id=$1
  local result=$2

  save_separator_in_file

  save_message_header_in_file $result

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

  save_task_link_in_file $task_id
}

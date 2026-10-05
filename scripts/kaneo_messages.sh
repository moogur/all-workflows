# shellcheck shell=bash disable=SC2154
# private_* задаёт kaneo_requests.sh, подключаемый раньше: shellcheck не видит этого
# через границу файлов.
#
# Человекочитаемый отчёт в $private_file_path (message.tmpl), который workflow kaneo.yml
# выводит в лог последним шагом. Подключается после kaneo_requests.sh (private_url и
# id текущей задачи оттуда). Ответ API недоверенный: в отчёт он попадает только очищенным.

private_file_path=./message.tmpl

# Ссылка на задачу: короткая (/<slug>/task/GA-25) требует slug рабочего пространства,
# которого нет в ответе API, поэтому полный путь по id. Без id задачи (данные не получены) ссылки нет.
save_task_link_in_file() {
  if [[ -z "$private_task_id" || -z "$private_project_id" || -z "$private_workspace_id" ]]; then
    return 0
  fi
  echo "Link to the task - $private_url/dashboard/workspace/$private_workspace_id/project/$private_project_id/task/$private_task_id" >> "$private_file_path"
}

save_separator_in_file() {
  if [[ -f $private_file_path ]]; then
    echo "----------" >> "$private_file_path"
  else
    touch "$private_file_path"
  fi
}

# save_header_in_file <SUCCESS|ERROR|SKIPPED>
save_header_in_file() {
  echo "$1" >> "$private_file_path"
  echo "" >> "$private_file_path"
}

# save_raw_message_in_file <ответ> — оставляет буквы, цифры и безопасную пунктуацию, до 300
# символов: ответ может содержать перевод строки, а строка `::команда` в логе — это
# workflow-команда. Пустой ответ (запрос не удался) строки не даёт.
save_raw_message_in_file() {
  local raw
  raw=$(printf '%s' "$1" | tr -cd '[:alnum:] ._,:{}"/-' | head -c 300)
  if [[ -n "$raw" ]]; then
    echo "Raw error - '$raw'" >> "$private_file_path"
  fi
}

# save_result_in_file <true|false> <текст успеха> <текст ошибки> <ответ>
save_result_in_file() {
  local result=$1 success=$2 failure=$3 raw=$4

  save_separator_in_file
  if [[ "$result" == "true" ]]; then
    save_header_in_file SUCCESS
    echo "$success" >> "$private_file_path"
  else
    save_header_in_file ERROR
    echo "$failure" >> "$private_file_path"
    save_raw_message_in_file "$raw"
  fi
  save_task_link_in_file
}

# save_message_in_file <колонка> <номер задачи> <ответ> <true|false> — итог переноса.
save_message_in_file() {
  save_result_in_file "$4" \
    "The task $2 has been successfully moved to the '$1' column" \
    "An error occurred when moving the task $2 to the '$1' column" "$3"
}

# save_message_in_file_for_add_app_version <номер задачи> <ответ> <true|false>
save_message_in_file_for_add_app_version() {
  save_result_in_file "$3" \
    "For the task $1, a version has been added" \
    "An error occurred when adding a version to the task $1" "$2"
}

# save_message_in_file_for_get_task_error <номер задачи> — не удалось получить данные задачи.
save_message_in_file_for_get_task_error() {
  save_result_in_file false "" "An error occurred while getting information about the task $1" ""
}

# save_skip_message_in_file <колонка> <номер задачи> — перенос не нужен.
save_skip_message_in_file() {
  save_separator_in_file
  save_header_in_file SKIPPED
  echo "The task $2 was not moved to the '$1' column: its current column does not require a transition" >> "$private_file_path"
  save_task_link_in_file
}

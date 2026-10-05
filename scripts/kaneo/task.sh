# shellcheck shell=bash disable=SC2154,SC2034
# kaneo_tr_*, kaneo_rule_* задаёт engine.sh, request_*/save_* — requests.sh и messages.sh; private_*
# отсюда читают fields.sh и messages.sh: shellcheck не видит этого через границу файлов.
#
# Обработка одной задачи: данные из Kaneo -> первое правило с подходящим `from` -> перенос в `to` ->
# поля (fields.sh) только после успешного переноса. Подключается из engine.sh.

# kaneo_parse_task <ответ GET task> — кладёт id, проект, пространство и статус задачи в
# kaneo_task_*; код 1, если ответ не JSON, любой из id не проходит kaneo_id_valid или статус
# пуст. Статус только сравнивается со схемой и не идёт в URL, поэтому может быть не ASCII
# (slug колонки на кириллице), но в лог не печатается.
kaneo_parse_task() {
  local row
  row=$(jq -r '[.id, .projectId, .workspaceId, .status] | @tsv' <<< "$1" 2>/dev/null) || return 1
  # Пустое поле схлопнулось бы в IFS-табуляции и сдвинуло остальные, оставив пустым
  # последнее — статус; он тоже проверяется, так что сдвиг не проходит.
  IFS=$'\t' read -r kaneo_task_id kaneo_task_project_id kaneo_task_workspace_id kaneo_task_status <<< "$row"

  local value
  for value in "$kaneo_task_id" "$kaneo_task_project_id" "$kaneo_task_workspace_id"; do
    kaneo_id_valid "$value" || return 1
  done
  [[ -n "$kaneo_task_status" ]]
}

# kaneo_use_task <номер> <id> <проект> <пространство> — делает задачу текущей для отчёта.
kaneo_use_task() {
  private_task_key=$1
  private_task_id=$2
  private_project_id=$3
  private_workspace_id=$4
}

# kaneo_move — переносит текущую задачу (private_*) в kaneo_tr_to и пишет итог в отчёт.
# Код 0 только если статус в ответе совпал с целевым.
kaneo_move() {
  local response result
  response=$(request_move_task "$private_task_id" "$kaneo_tr_to") || response=''
  result=$(jq -r --arg status "$kaneo_tr_to" '.status == $status' <<< "$response" 2>/dev/null) || result=false
  save_message_in_file "$kaneo_tr_to" "$private_task_key" "$response" "$result"
  [[ "$result" == "true" ]]
}

# kaneo_process_task <номер задачи> — один проход по задаче; сбой одной задачи не роняет шаг.
kaneo_process_task() {
  local key=$1 info

  kaneo_use_task "" "" "" ""
  info=$(request_get_task "$key") || info=''
  if ! kaneo_parse_task "$info"; then
    save_message_in_file_for_get_task_error "$key"
    return 0
  fi
  kaneo_use_task "$key" "$kaneo_task_id" "$kaneo_task_project_id" "$kaneo_task_workspace_id"

  if ! kaneo_select_rule "$kaneo_task_status"; then
    save_skip_message_in_file "$(kaneo_rules_targets)" "$key"
    return 0
  fi
  if kaneo_move; then
    kaneo_fields_apply
  fi
}

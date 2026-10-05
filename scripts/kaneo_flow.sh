# shellcheck shell=bash
#
# Переходы задачи Kaneo по статусам (колонкам) для push/pr/merge. Подключается из
# kaneo.yml после чекаута all-workflows; deploy — в kaneo_deploy.sh. Всё приходит через
# env: KANEO_URL/KANEO_TOKEN, KANEO_STATUS_*, PROJECT_TYPE, CURRENT_STATUS и данные
# задачи из шага kaneo_prepare (KANEO_TASK_KEY/ID, KANEO_PROJECT_ID, KANEO_WORKSPACE_ID).

# shellcheck source=scripts/kaneo_requests.sh
source "$(dirname "${BASH_SOURCE[0]}")/kaneo_requests.sh"
# shellcheck source=scripts/kaneo_messages.sh
source "$(dirname "${BASH_SOURCE[0]}")/kaneo_messages.sh"
# shellcheck source=scripts/kaneo_task_id.sh
source "$(dirname "${BASH_SOURCE[0]}")/kaneo_task_id.sh"

# kaneo_parse_task <ответ GET task> — кладёт id, проект, пространство и статус задачи в
# kaneo_task_*; код 1, если ответ не JSON или любое из значений не проходит kaneo_id_valid
# (ответ недоверенный: дальше идут только проверенные значения).
kaneo_parse_task() {
  local row
  row=$(jq -r '[.id, .projectId, .workspaceId, .status] | @tsv' <<< "$1" 2>/dev/null) || return 1
  # Пустое поле схлопнулось бы в IFS-табуляции и сдвинуло остальные, оставив пустым
  # последнее — статус; он тоже проверяется, так что сдвиг не проходит.
  IFS=$'\t' read -r kaneo_task_id kaneo_task_project_id kaneo_task_workspace_id kaneo_task_status <<< "$row"

  local value
  for value in "$kaneo_task_id" "$kaneo_task_project_id" "$kaneo_task_workspace_id" "$kaneo_task_status"; do
    kaneo_id_valid "$value" || return 1
  done
}

# kaneo_use_task <номер> <id> <проект> <пространство> — делает задачу текущей для отчёта.
kaneo_use_task() {
  private_task_key=$1
  private_task_id=$2
  private_project_id=$3
  private_workspace_id=$4
}

# kaneo_prepare — шаг «Set variables»: номер задачи события -> данные задачи из Kaneo ->
# $GITHUB_OUTPUT. Kaneo не блокирует пайплайн: без номера или данных пишет строку в лог
# и ничего не выводит (следующие шаги пропускаются по пустому task_key). Недоверенные
# значения (номер из коммита, ответ API) в лог и вывод идут только проверенными.
kaneo_prepare() {
  local key info
  key=$(kaneo_task_key_for_event)

  if [[ -z "$key" ]]; then
    echo "Kaneo: в имени ветки/заголовке коммита нет номера задачи вида GA-123, шаги пропущены"
    return 0
  fi

  info=$(request_get_task "$key") || info=''
  if ! kaneo_parse_task "$info"; then
    echo "Kaneo: не удалось получить данные задачи $key, шаги пропущены"
    return 0
  fi

  {
    echo "task_key=${key}"
    echo "task_id=${kaneo_task_id}"
    echo "project_id=${kaneo_task_project_id}"
    echo "workspace_id=${kaneo_task_workspace_id}"
    echo "current_status=${kaneo_task_status}"
  } >> "$GITHUB_OUTPUT"

  echo "task_key $key"
  echo "current_status $kaneo_task_status"
}

# kaneo_require_statuses <событие> <статус>... — код 1 и строка в лог, если какой-то из
# нужных событию статусов не задан (для multi_branch их задаёт потребитель).
kaneo_require_statuses() {
  local event=$1 status
  shift
  for status in "$@"; do
    if [[ -z "$status" ]]; then
      echo "Kaneo: для события $event не заданы нужные kaneo_status_*, шаг пропущен"
      return 1
    fi
  done
}

# kaneo_move <метка колонки в отчёте> <целевой статус> — переносит текущую задачу
# (private_*) и пишет итог в отчёт; успех — статус в ответе совпал с целевым.
kaneo_move() {
  local label=$1 target=$2 response result
  response=$(request_move_task "$private_task_id" "$target") || response=''
  result=$(jq -r --arg status "$target" '.status == $status' <<< "$response" 2>/dev/null) || result=false
  save_message_in_file "$label" "$private_task_key" "$response" "$result"
}

# kaneo_on_push — в in progress, если задача ещё не там (и, для multi_branch, не в review).
kaneo_on_push() {
  local in_progress=${KANEO_STATUS_IN_PROGRESS:-} review=${KANEO_STATUS_REVIEW:-}
  local current=${CURRENT_STATUS:-}

  kaneo_require_statuses push "$in_progress" || return 0
  if [[ "$current" == "$in_progress" ]] \
    || [[ "${PROJECT_TYPE:-}" == "multi_branch" && -n "$review" && "$current" == "$review" ]]; then
    save_skip_message_in_file IN_PROGRESS "$private_task_key"
  else
    kaneo_move IN_PROGRESS "$in_progress"
  fi
}

# kaneo_on_pr — multi_branch: из in progress в review.
kaneo_on_pr() {
  local in_progress=${KANEO_STATUS_IN_PROGRESS:-} review=${KANEO_STATUS_REVIEW:-}

  kaneo_require_statuses pr "$in_progress" "$review" || return 0
  if [[ "${CURRENT_STATUS:-}" == "$in_progress" ]]; then
    kaneo_move REVIEW "$review"
  else
    save_skip_message_in_file REVIEW "$private_task_key"
  fi
}

# kaneo_on_merge — multi_branch: из review в merged.
kaneo_on_merge() {
  local review=${KANEO_STATUS_REVIEW:-} merged=${KANEO_STATUS_MERGED:-}

  kaneo_require_statuses merge "$review" "$merged" || return 0
  if [[ "${CURRENT_STATUS:-}" == "$review" ]]; then
    kaneo_move MERGED "$merged"
  else
    save_skip_message_in_file MERGED "$private_task_key"
  fi
}

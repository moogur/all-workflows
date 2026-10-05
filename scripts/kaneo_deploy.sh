# shellcheck shell=bash
#
# Событие deploy (multi_branch): задачи из коммитов между двумя последними тегами
# переносятся из merged в deploy, и в пользовательское поле App_version дописывается
# версия релиза. Подключается из kaneo.yml; остальное — в kaneo_flow.sh.

# shellcheck source=scripts/kaneo_flow.sh
source "$(dirname "${BASH_SOURCE[0]}")/kaneo_flow.sh"

KANEO_VERSION_FIELD=App_version

# id поля App_version по проектам; пустая строка — в проекте поля нет.
declare -gA kaneo_version_field_ids=()

# kaneo_merge_versions <текущее значение поля> <версия> — печатает новое значение: версия
# (поле пустое) или "<текущее>, <версия>". Код 1, если версия в списке уже есть
# (сравнение по целому элементу списка, не по подстроке: 1.2 не входит в 1.2.3).
kaneo_merge_versions() {
  local current=$1 version=$2 item
  local -a items

  if [[ -z "$current" ]]; then
    printf '%s' "$version"
    return 0
  fi

  IFS=',' read -r -a items <<< "$current"
  for item in "${items[@]}"; do
    item=${item#"${item%%[![:space:]]*}"}
    item=${item%"${item##*[![:space:]]}"}
    if [[ "$item" == "$version" ]]; then
      return 1
    fi
  done
  printf '%s, %s' "$current" "$version"
}

# kaneo_load_version_field <id проекта> — кладёт id поля App_version в kaneo_version_field_id
# (пусто, если поля нет; результат запоминается по проекту). Код 1 — запрос не удался или
# id не прошёл проверку.
kaneo_load_version_field() {
  local project=$1 definitions field_id

  if [[ -z "${kaneo_version_field_ids[$project]+set}" ]]; then
    definitions=$(request_get_project_fields "$project") || return 1
    field_id=$(jq -r --arg name "$KANEO_VERSION_FIELD" \
      'first(.[] | select(.name == $name) | .id) // ""' <<< "$definitions" 2>/dev/null) || return 1
    if [[ -n "$field_id" ]] && ! kaneo_id_valid "$field_id"; then
      return 1
    fi
    kaneo_version_field_ids[$project]=$field_id
  fi
  kaneo_version_field_id=${kaneo_version_field_ids[$project]}
}

# kaneo_stamp_version <версия> — дописывает версию в App_version текущей задачи. Без поля
# в проекте — строка в лог и выход; не удалось прочитать текущее значение — ошибка в отчёт
# без записи, чтобы не затереть уже стоящие версии.
kaneo_stamp_version() {
  local version=$1 values current merged response result

  if ! kaneo_load_version_field "$private_project_id"; then
    save_message_in_file_for_add_app_version "$private_task_key" "" false
    return 0
  fi
  if [[ -z "$kaneo_version_field_id" ]]; then
    echo "Kaneo: в проекте задачи $private_task_key нет поля $KANEO_VERSION_FIELD, версия не записана"
    return 0
  fi

  if ! values=$(request_get_task_fields "$private_task_id") \
    || ! current=$(jq -r --arg field "$kaneo_version_field_id" \
      'first(.[] | select(.fieldId == $field) | .value) // ""' <<< "$values" 2>/dev/null); then
    save_message_in_file_for_add_app_version "$private_task_key" "" false
    return 0
  fi

  if ! merged=$(kaneo_merge_versions "$current" "$version"); then
    return 0
  fi

  response=$(request_set_field_value "$private_task_id" "$kaneo_version_field_id" "$merged") || response=''
  result=$(jq -r --arg value "$merged" '.value == $value' <<< "$response" 2>/dev/null) || result=false
  save_message_in_file_for_add_app_version "$private_task_key" "$response" "$result"
}

# kaneo_deploy_task <номер задачи> <версия> — перенос одной задачи и запись версии.
kaneo_deploy_task() {
  local key=$1 version=$2 info

  kaneo_use_task "" "" "" ""
  info=$(request_get_task "$key") || info=''
  if ! kaneo_parse_task "$info"; then
    save_message_in_file_for_get_task_error "$key"
    return 0
  fi
  kaneo_use_task "$key" "$kaneo_task_id" "$kaneo_task_project_id" "$kaneo_task_workspace_id"

  if [[ "$kaneo_task_status" == "$KANEO_STATUS_MERGED" ]]; then
    kaneo_move DEPLOY "$KANEO_STATUS_DEPLOY"
  else
    save_skip_message_in_file DEPLOY "$key"
  fi
  kaneo_stamp_version "$version"
}

# kaneo_on_deploy — все задачи диапазона тегов. Нет нужных статусов или тегов — строка в лог.
kaneo_on_deploy() {
  local -a tags keys
  local version previous='' key

  kaneo_require_statuses deploy "${KANEO_STATUS_MERGED:-}" "${KANEO_STATUS_DEPLOY:-}" || return 0

  mapfile -t tags < <(kaneo_deploy_tags)
  if [[ "${#tags[@]}" -eq 0 ]]; then
    echo "Kaneo: в репозитории нет тегов, шаг пропущен"
    return 0
  fi
  version=$(kaneo_release_version "${tags[0]}")
  if [[ "${#tags[@]}" -eq 2 ]]; then
    previous=${tags[1]}
  fi

  mapfile -t keys < <(kaneo_deploy_task_keys "${tags[0]}" "$previous")
  for key in "${keys[@]}"; do
    kaneo_deploy_task "$key" "$version"
  done
}

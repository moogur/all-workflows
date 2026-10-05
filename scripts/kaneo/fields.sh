# shellcheck shell=bash disable=SC2154
# kaneo_tr_*, kaneo_task_* задают engine.sh и task.sh, request_*/save_* — requests.sh и
# messages.sh: shellcheck не видит этого через границу файлов.
#
# Пользовательские поля задачи после успешного переноса. Значение считает функция
# kaneo_field_<имя> из scripts/kaneo/fields/<имя>.sh (имя — из схемы): без аргументов,
# контекст — в KANEO_FIELD_VALUE, KANEO_TASK_KEY, KANEO_TASK_STATUS, KANEO_EVENT, новое
# значение — в stdout. Подключается из engine.sh. Своих функций kaneo_field_* здесь нет:
# имя из схемы не должно совпасть со служебной функцией. eval не используется.

KANEO_FIELDS_DIR=${KANEO_FIELDS_DIR:-$(dirname "${BASH_SOURCE[0]}")/fields}  # переопределяют только тесты

# Определения полей проекта (JSON), по одному запросу на проект за прогон.
declare -gA kaneo_project_definitions=()

# kaneo_fields_load_func <имя> — функция kaneo_field_<имя> определена; при необходимости
# подключает файл полей один раз. Код 1 и строка в лог при неверном имени или файле.
kaneo_fields_load_func() {
  local name=$1 file
  if ! kaneo_func_name_valid "$name"; then
    echo "Kaneo: имя функции поля в схеме не по формату, поле пропущено"
    return 1
  fi
  declare -F "kaneo_field_$name" > /dev/null && return 0

  file="$KANEO_FIELDS_DIR/$name.sh"
  if [[ ! -f "$file" ]]; then
    echo "Kaneo: нет файла функции поля fields/$name.sh, поле пропущено"
    return 1
  fi
  # shellcheck disable=SC1090
  source "$file"
  if ! declare -F "kaneo_field_$name" > /dev/null; then
    echo "Kaneo: fields/$name.sh не определяет kaneo_field_$name, поле пропущено"
    return 1
  fi
}

# kaneo_fields_load_definitions — определения полей проекта текущей задачи в кеше; запрос
# один на проект за прогон. Вызывается не в подоболочке, иначе кеш потерялся бы.
kaneo_fields_load_definitions() {
  local definitions
  if [[ -z "${kaneo_project_definitions[$private_project_id]+set}" ]]; then
    definitions=$(request_get_project_fields "$private_project_id") || return 1
    kaneo_project_definitions[$private_project_id]=$definitions
  fi
}

# kaneo_fields_definition_id <имя поля> — печатает id поля из кеша определений (пусто, если
# такого поля в проекте нет). Код 1 — ответ не разобрался или id не прошёл проверку.
kaneo_fields_definition_id() {
  local field_id
  field_id=$(jq -r --arg name "$1" 'first(.[] | select(.name == $name) | .id) // ""' \
    <<< "${kaneo_project_definitions[$private_project_id]}" 2>/dev/null) || return 1
  if [[ -n "$field_id" ]] && ! kaneo_id_valid "$field_id"; then
    return 1
  fi
  printf '%s' "$field_id"
}

# kaneo_fields_current_value <id поля> — печатает текущее значение поля у текущей задачи
# (пусто, если значения нет). Код 1 — не удалось прочитать.
kaneo_fields_current_value() {
  local values
  values=$(request_get_task_fields "$private_task_id") || return 1
  jq -r --arg field "$1" 'first(.[] | select(.fieldId == $field) | .value) // ""' <<< "$values" 2>/dev/null
}

# kaneo_fields_apply_one <имя поля> <имя функции> — одно поле текущей задачи. Всегда код 0:
# сбой поля не мешает остальным полям и задачам.
kaneo_fields_apply_one() {
  local name=$1 func=$2 field_id current new response result

  kaneo_fields_load_func "$func" || return 0
  if ! kaneo_fields_load_definitions || ! field_id=$(kaneo_fields_definition_id "$name"); then
    save_message_in_file_for_field "$name" "$private_task_key" "" false
    return 0
  fi
  if [[ -z "$field_id" ]]; then
    echo "Kaneo: в проекте задачи $private_task_key нет поля $name, поле пропущено"
    return 0
  fi
  # Не прочитали текущее значение — не пишем вслепую, чтобы не затереть стоящее.
  if ! current=$(kaneo_fields_current_value "$field_id"); then
    save_message_in_file_for_field "$name" "$private_task_key" "" false
    return 0
  fi

  if ! new=$(KANEO_FIELD_VALUE=$current KANEO_TASK_KEY=$private_task_key \
    KANEO_TASK_STATUS=$kaneo_task_status KANEO_EVENT=${EVENT_TYPE:-} "kaneo_field_$func"); then
    echo "Kaneo: функция поля $name завершилась с ошибкой, значение не записано"
    save_message_in_file_for_field "$name" "$private_task_key" "" false
    return 0
  fi
  if [[ "$new" == "$current" ]]; then
    echo "Kaneo: поле $name задачи $private_task_key не изменилось, запись не нужна"
    return 0
  fi

  response=$(request_set_field_value "$private_task_id" "$field_id" "$new") || response=''
  result=$(jq -r --arg value "$new" '.value == $value' <<< "$response" 2>/dev/null) || result=false
  save_message_in_file_for_field "$name" "$private_task_key" "$response" "$result"
}

# kaneo_fields_apply — все поля перехода (kaneo_tr_field_names/funcs) для текущей задачи.
kaneo_fields_apply() {
  local i
  for i in "${!kaneo_tr_field_names[@]}"; do
    kaneo_fields_apply_one "${kaneo_tr_field_names[i]}" "${kaneo_tr_field_funcs[i]}"
  done
}

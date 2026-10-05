# shellcheck shell=bash
#
# Движок интеграции с Kaneo: схема (scripts/kaneo/schemes.json) + событие -> переход задач
# по статусам и запись полей. Подключается из kaneo.yml после чекаута all-workflows; запуск —
# `kaneo_run`. Всё приходит через env: KANEO_URL/KANEO_TOKEN, KANEO_SCHEME, EVENT_TYPE,
# HEAD_REF (github.head_ref), GITHUB_REF_NAME. Kaneo не блокирует пайплайн: любой сбой —
# строка в лог/отчёт, код возврата 0. Ничего из схемы не исполняется через eval.

# shellcheck source=scripts/kaneo/requests.sh
source "$(dirname "${BASH_SOURCE[0]}")/requests.sh"
# shellcheck source=scripts/kaneo/messages.sh
source "$(dirname "${BASH_SOURCE[0]}")/messages.sh"
# shellcheck source=scripts/kaneo/task_key.sh
source "$(dirname "${BASH_SOURCE[0]}")/task_key.sh"
# shellcheck source=scripts/kaneo/task.sh
source "$(dirname "${BASH_SOURCE[0]}")/task.sh"
# shellcheck source=scripts/kaneo/fields.sh
source "$(dirname "${BASH_SOURCE[0]}")/fields.sh"

KANEO_SCHEMES_FILE=${KANEO_SCHEMES_FILE:-$(dirname "${BASH_SOURCE[0]}")/schemes.json}  # переопределяют только тесты

# Событие схемы (заполняет kaneo_load_transition): источник номера задач (task_key) и список
# правил по порядку схемы.
# kaneo_rule_to[i] — целевой статус правила i, kaneo_rule_from["i<TAB>статус"] — допустимые
# исходные статусы, kaneo_rule_field_* — поля правил (индекс правила, имя поля, функция).
kaneo_tr_key_source=''
kaneo_rule_to=()
declare -gA kaneo_rule_from=()
kaneo_rule_field_rule=()
kaneo_rule_field_names=()
kaneo_rule_field_funcs=()

# Сработавшее правило (заполняет kaneo_select_rule): целевой статус и его поля.
kaneo_tr_to=''
kaneo_tr_field_names=()
kaneo_tr_field_funcs=()

# Номера задач события (заполняет kaneo_collect_keys).
kaneo_keys=()

# kaneo_log_safe <строка> — строка для лога: недоверенный ввод без управляющих символов,
# чтобы `::команда` и перевод строки не стали workflow-командой.
kaneo_log_safe() {
  printf '%s' "$1" | tr -cd '[:alnum:]._-' | head -c 60
}

# kaneo_load_transition <схема> <событие> — читает переход из файла схем. Код 1 и строка в
# лог, если схемы или события в ней нет (или файл схем недоступен).
kaneo_load_transition() {
  local scheme=$1 event=$2 line tag first second rule=-1 tab=$'\t'
  local -a lines

  kaneo_tr_key_source=''
  kaneo_rule_to=() kaneo_rule_from=()
  kaneo_rule_field_rule=() kaneo_rule_field_names=() kaneo_rule_field_funcs=()

  mapfile -t lines < <(jq -r --arg s "$scheme" --arg e "$event" '
    if has($s) | not then "no_scheme"
    elif .[$s] | has($e) | not then "no_event"
    else .[$s][$e] as $event
      | "ok", "key\t\($event.task_key)",
        ($event.rules[] | "rule", "to\t\(.to)",
          (.from[] | "from\t\(.)"),
          ((.fields // {}) | to_entries[] | "field\t\(.key)\t\(.value)"))
    end' "$KANEO_SCHEMES_FILE" 2>/dev/null)

  case "${lines[0]:-}" in
    ok) ;;
    no_scheme)
      echo "Kaneo: схема '$(kaneo_log_safe "$scheme")' не найдена, шаг пропущен"
      return 1 ;;
    no_event)
      echo "Kaneo: событие '$(kaneo_log_safe "$event")' не используется в схеме '$(kaneo_log_safe "$scheme")', шаг пропущен"
      return 1 ;;
    *)
      echo "Kaneo: не удалось прочитать файл схем, шаг пропущен"
      return 1 ;;
  esac

  for line in "${lines[@]:1}"; do
    IFS=$'\t' read -r tag first second <<< "$line"
    case "$tag" in
      key) kaneo_tr_key_source=$first ;;
      rule) rule=$((rule + 1)) ;;
      to) kaneo_rule_to[rule]=$first ;;
      from) kaneo_rule_from[$rule$tab$first]=1 ;;
      field)
        kaneo_rule_field_rule+=("$rule")
        kaneo_rule_field_names+=("$first")
        kaneo_rule_field_funcs+=("$second") ;;
    esac
  done
}

# kaneo_select_rule <статус задачи> — первое правило, чей `from` содержит статус: кладёт его
# `to` и поля в kaneo_tr_*. Код 1, если ни одно правило не подошло.
kaneo_select_rule() {
  local status=$1 i j tab=$'\t'
  for i in "${!kaneo_rule_to[@]}"; do
    [[ -n "${kaneo_rule_from[$i$tab$status]+set}" ]] || continue
    kaneo_tr_to=${kaneo_rule_to[i]}
    kaneo_tr_field_names=() kaneo_tr_field_funcs=()
    for j in "${!kaneo_rule_field_rule[@]}"; do
      if [[ "${kaneo_rule_field_rule[j]}" == "$i" ]]; then
        kaneo_tr_field_names+=("${kaneo_rule_field_names[j]}")
        kaneo_tr_field_funcs+=("${kaneo_rule_field_funcs[j]}")
      fi
    done
    return 0
  done
  return 1
}

# kaneo_rules_targets — целевые статусы всех правил через «/» (для строки SKIPPED в отчёте).
kaneo_rules_targets() {
  local IFS=/
  printf '%s' "${kaneo_rule_to[*]}"
}

# kaneo_collect_keys <событие> — номера задач события в kaneo_keys по источнику `task_key`
# из схемы: tags — задачи из коммитов между двумя последними тегами, остальное — один номер.
kaneo_collect_keys() {
  local event=$1 key previous=''
  local -a tags

  kaneo_keys=()
  if [[ "$kaneo_tr_key_source" == "tags" ]]; then
    mapfile -t tags < <(kaneo_deploy_tags)
    if [[ "${#tags[@]}" -eq 0 ]]; then
      echo "Kaneo: в репозитории нет тегов, шаг пропущен"
      return 0
    fi
    if [[ "${#tags[@]}" -eq 2 ]]; then
      previous=${tags[1]}
    fi
    mapfile -t kaneo_keys < <(kaneo_deploy_task_keys "${tags[0]}" "$previous")
  else
    key=$(kaneo_task_key_by_source "$kaneo_tr_key_source" "$event") || key=''
    if [[ -n "$key" ]]; then
      kaneo_keys=("$key")
    fi
  fi
}

# kaneo_run — точка входа шага workflow.
kaneo_run() {
  local event=${EVENT_TYPE:-} key found=0

  kaneo_load_transition "${KANEO_SCHEME:-}" "$event" || return 0
  kaneo_collect_keys "$event"
  for key in "${kaneo_keys[@]}"; do
    [[ -n "$key" ]] || continue
    found=1
    kaneo_process_task "$key"
  done
  if [[ "$found" -eq 0 ]]; then
    echo "Kaneo: номера задач события нет (заголовок коммита, имя ветки, теги), шаг пропущен"
  fi
}

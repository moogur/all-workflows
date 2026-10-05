# shellcheck shell=bash
#
# Извлечение номера задачи Kaneo (GA-25) из контекста события Git для engine.sh. Сам
# разбор — в lib/commit.sh (commit_task_key) и lib/tags.sh; здесь — только то, откуда
# какой текст берётся. Подключается через `source` из engine.sh, поэтому lib ищем
# относительно самого файла.

# shellcheck source=lib/commit.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/commit.sh"
# shellcheck source=lib/tags.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/tags.sh"

# kaneo_task_key_from_last_commit [репозиторий] — номер задачи из заголовка последнего
# коммита. Невалидный номер — пусто (недоверенный ввод).
kaneo_task_key_from_last_commit() {
  local repo="${1:-.}"
  commit_task_key "$(git -C "$repo" log -1 --pretty=%B)"
}

# kaneo_task_key_from_ref <имя ветки или тега> — номер задачи из имени ветки/тега
# (GA-123-... / GA-123_...), иначе пусто.
kaneo_task_key_from_ref() {
  commit_task_key "$1"
}

# kaneo_task_key_by_source <commit|branch> <событие> — номер задачи события по источнику
# из схемы: commit — последний коммит; branch — ветка PR (HEAD_REF) для pr/merge, иначе
# имя ветки/тега запуска (GITHUB_REF_NAME). Неизвестный источник — пусто.
kaneo_task_key_by_source() {
  case "$1" in
    commit) kaneo_task_key_from_last_commit ;;
    branch)
      if [[ "$2" == "pr" || "$2" == "merge" ]]; then
        kaneo_task_key_from_ref "${HEAD_REF:-}"
      else
        kaneo_task_key_from_ref "${GITHUB_REF_NAME:-}"
      fi
      ;;
  esac
}

# kaneo_deploy_tags [репозиторий] — два последних тега по дате создания
# (текущий релиз и предыдущий), по одному на строку; предыдущего может не быть.
kaneo_deploy_tags() {
  local repo="${1:-.}"
  tags_latest_n 2 "$repo"
}

# kaneo_deploy_task_keys <текущий тег> <предыдущий тег, может быть пустым> [репозиторий] —
# уникальные номера задач из заголовков коммитов диапазона (вся история, если предыдущего
# тега нет), по одному на строку.
kaneo_deploy_task_keys() {
  local current="$1" previous="$2" repo="${3:-.}"
  local -a log_args=(--pretty=format:%s)
  if [[ -n "$previous" ]]; then
    log_args+=("${previous}..${current}")
  else
    log_args+=(--all)
  fi

  # mapfile, а не `while read` из process substitution: git log не добавляет
  # перевод строки после последней записи, и такой read молча теряет одну строку.
  local -a subjects
  mapfile -t subjects < <(git -C "$repo" log "${log_args[@]}")

  local subject key
  declare -A seen=()
  for subject in "${subjects[@]}"; do
    [[ -n "$subject" ]] || continue
    key=$(commit_task_key "$subject")
    [[ -n "$key" ]] || continue
    seen[$key]=1
  done

  for key in "${!seen[@]}"; do
    echo "$key"
  done
}

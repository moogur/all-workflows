# shellcheck shell=bash
#
# Извлечение номера задачи Kaneo (GA-25) и версии релиза из контекста события Git для
# workflow kaneo.yml. Сам разбор — в lib/commit.sh (commit_task_key), lib/tags.sh и
# lib/version.sh; здесь — только то, откуда какой текст берётся.
# Подключается через `source` из kaneo.yml, где рядом уже лежит чекаут этого
# репозитория (.all-workflows), поэтому lib ищем относительно самого файла.

# shellcheck source=lib/commit.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/commit.sh"
# shellcheck source=lib/tags.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/tags.sh"
# shellcheck source=lib/version.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/version.sh"

# kaneo_task_key_from_last_commit [репозиторий] — номер задачи из заголовка последнего
# коммита (single_branch). Невалидный номер — пусто (недоверенный ввод).
kaneo_task_key_from_last_commit() {
  local repo="${1:-.}"
  commit_task_key "$(git -C "$repo" log -1 --pretty=%B)"
}

# kaneo_task_key_from_ref <имя ветки или тега> — номер задачи из имени ветки/тега
# (GA-123-... / GA-123_...), иначе пусто.
kaneo_task_key_from_ref() {
  commit_task_key "$1"
}

# kaneo_task_key_for_event — номер задачи текущего события по PROJECT_TYPE, EVENT_TYPE,
# HEAD_REF (github.head_ref) и GITHUB_REF_NAME из окружения: single_branch — последний
# коммит; pr/merge — ветка PR; остальное — имя ветки/тега запуска.
kaneo_task_key_for_event() {
  if [[ "${PROJECT_TYPE:-}" == "single_branch" ]]; then
    kaneo_task_key_from_last_commit
  elif [[ "${EVENT_TYPE:-}" == "pr" || "${EVENT_TYPE:-}" == "merge" ]]; then
    kaneo_task_key_from_ref "${HEAD_REF:-}"
  else
    kaneo_task_key_from_ref "${GITHUB_REF_NAME:-}"
  fi
}

# kaneo_release_version <тег> — версия релиза из имени тега (снятие префикса v).
kaneo_release_version() {
  version_strip_prefix "$1" v
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

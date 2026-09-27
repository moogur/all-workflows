# shellcheck shell=bash
#
# Извлечение task_id (номер задачи Kanboard) и версии релиза из контекста события
# Git для workflow kanboard.yml. Сам разбор — в lib/commit.sh (commit_task_id_token)
# lib/tags.sh и lib/version.sh; здесь — только то, откуда какой текст берётся.
# Подключается через `source` из kanboard.yml, где рядом уже лежит чекаут этого
# репозитория (.all-workflows), поэтому lib ищем относительно самого файла.

# shellcheck source=lib/commit.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/commit.sh"
# shellcheck source=lib/tags.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/tags.sh"
# shellcheck source=lib/version.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/version.sh"

# kanboard_task_id_from_last_commit [репозиторий] — task_id из заголовка последнего
# коммита (single_branch: сообщение коммита содержит номер задачи).
kanboard_task_id_from_last_commit() {
  local repo="${1:-.}"
  commit_task_id_token "$(git -C "$repo" log -1 --pretty=%B)"
}

# kanboard_task_id_from_ref <имя ветки или тега> — task_id из имени ветки/тега
# (GA-123-... / GA-123_...): pr/merge (github.head_ref) и push в multi_branch (GITHUB_REF_NAME).
kanboard_task_id_from_ref() {
  commit_task_id_token "$1"
}

# kanboard_release_version <тег> — версия релиза из имени тега (снятие префикса v).
kanboard_release_version() {
  version_strip_prefix "$1" v
}

# kanboard_deploy_tags [репозиторий] — два последних тега по дате создания
# (текущий релиз и предыдущий), по одному на строку; предыдущего может не быть.
kanboard_deploy_tags() {
  local repo="${1:-.}"
  tags_latest_n 2 "$repo"
}

# kanboard_deploy_task_ids <текущий тег> <предыдущий тег, может быть пустым> [репозиторий] —
# уникальные task_id из заголовков коммитов диапазона (вся история, если предыдущего тега нет),
# по одному на строку.
kanboard_deploy_task_ids() {
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

  local subject task_id
  declare -A seen=()
  for subject in "${subjects[@]}"; do
    [[ -n "$subject" ]] || continue
    task_id=$(commit_task_id_token "$subject")
    [[ "$task_id" =~ ^[0-9]+$ ]] || continue
    seen[$task_id]=1
  done

  local id
  for id in "${!seen[@]}"; do
    echo "$id"
  done
}

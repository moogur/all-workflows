# shellcheck shell=bash disable=SC2034
# Регэкспы/карта/длина ниже читает только код, который подключает этот файл через
# `source` (release-notes/notes.sh, .husky/commit-msg) — shellcheck не видит этого
# через границу файлов и считает их неиспользуемыми.
#
# Формат заголовка коммита: "[PREFIX-N] type(scope): subject".
#   PREFIX — [A-Z][A-Z0-9]*, любой (потребители живут со своими: GA-123, IPB-456);
#   type — точное совпадение с COMMIT_TYPES (без подстрок вроде 'feat' ⊂ 'feature');
#   scope, subject — непустые, нижний регистр; subject не длиннее COMMIT_SUBJECT_MAX_LENGTH.
# Пример: [GA-557] feature(frontend): add deploy spa and pwa
#
# PR в git-истории (--first-parent): смёрженный кнопкой Merge — заголовок коммита
# "Merge pull request #N from ..."; сквошенный — subject коммита с суффиксом " (#N)".

readonly COMMIT_HEADER_REGEX='^\[([A-Z][A-Z0-9]*-[0-9]+)\][[:space:]]+([a-z]+)\(([^)]+)\):[[:space:]]+(.+)$'
readonly COMMIT_MERGE_PR_REGEX='^Merge pull request #([0-9]+) from '
readonly COMMIT_SQUASH_PR_REGEX='^(.*) \(#([0-9]+)\)$'
readonly COMMIT_SUBJECT_MAX_LENGTH=125
readonly COMMIT_TYPES=(feature bugfix ci config refactor test docs)

# type -> категория тела релиза (release-notes/notes.sh); нет записи — категория "other".
declare -A COMMIT_CATEGORY_OF=(
  [feature]=features
  [test]=features
  [bugfix]=fixes
  [docs]=docs
  [refactor]=maintenance
  [config]=configuration
  [ci]=configuration
)

# commit_type_allowed <type> — точное совпадение с COMMIT_TYPES.
commit_type_allowed() {
  local type="$1" candidate
  for candidate in "${COMMIT_TYPES[@]}"; do
    [[ "$type" == "$candidate" ]] && return 0
  done
  return 1
}

# commit_is_lowercase <значение> — значение совпадает со своей нижнерегистровой формой.
commit_is_lowercase() {
  local value="$1" lowered
  lowered=$(tr '[:upper:]' '[:lower:]' <<< "$value")
  [[ "$lowered" == "$value" ]]
}

# commit_task_id_token <текст> — «второе слово» первой строки текста после разбиения
# по '-', ']' и '_': номер задачи из заголовка коммита ("[GA-557] ..." -> 557) или из
# имени ветки/тега ("GA-557-..." / "GA-557_..." -> 557). Многострочный вход (тело
# коммита) не мешает: смотрим только первую строку. Используется kanboard.yml.
commit_task_id_token() {
  local text="$1"
  tr -- '-]_' '   ' <<< "$text" | awk '{print $2; exit}'
}

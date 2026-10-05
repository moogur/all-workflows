# shellcheck shell=bash disable=SC2034
# Формат id сущностей Kaneo (задача, проект, рабочее пространство, поле, колонка):
# непустая строка из букв, цифр, '_' и '-'. Ответ API недоверенный, поэтому только такие
# значения допускаются в URL запросов и в вывод шагов workflow.
# Номер задачи для поиска (GA-25) — отдельный формат, он в lib/commit.sh.

# Файл подключают несколько скриптов kaneo в одном shell: повторное присвоение readonly
# упало бы под bash -e (см. lib/commit.sh).
if [[ -z "${LIB_KANEO_LOADED:-}" ]]; then
  readonly LIB_KANEO_LOADED=1
  readonly KANEO_ID_REGEX='^[A-Za-z0-9_-]+$'
fi

# kaneo_id_valid <значение> — значение целиком соответствует формату id Kaneo.
kaneo_id_valid() {
  local LC_ALL=C # диапазоны A-Z/a-z в других локалях захватывают не-ASCII буквы
  [[ "$1" =~ $KANEO_ID_REGEX ]]
}

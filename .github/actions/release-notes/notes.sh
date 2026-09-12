#!/usr/bin/env bash
# Собирает тело GitHub-релиза из коммитов между текущим и предыдущим тегом.
# Заголовки разбираются по формату хука commit-msg ([<ПРЕФИКС>-123] type(scope): subject)
# и группируются по тем же категориям, что и .github/release-drafter.yml.
# Вход (env): TAG (по умолчанию тег из GITHUB_REF), PREVIOUS_TAG (пусто — считаем сами),
#   NOTES_FILE (пусто — $RUNNER_TEMP/release-notes.md), GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_OUTPUT.
# Выход: файл с телом релиза + строки "notes_file=", "previous_tag=", "commit_count=" в $GITHUB_OUTPUT.
set -euo pipefail

tag="${TAG:-${GITHUB_REF:-}}"
tag="${tag#refs/tags/}"
if [[ -z "$tag" || "$tag" == refs/* ]]; then
  echo "TAG is required (or GITHUB_REF must point to a tag)" >&2
  exit 1
fi

if ! git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  echo "Tag '${tag}' not found in the repository (checkout with fetch-depth: 0 is required)" >&2
  exit 1
fi

previous="${PREVIOUS_TAG:-}"
if [[ -z "$previous" ]]; then
  # Предыдущий тег — соседний по дате создания, а не по имени: сортировка по имени
  # врёт на датных тегах (среди них «максимум» — 26.05.2023, потому что 26 > 14).
  previous=$(git for-each-ref --sort=-creatordate --format='%(refname:short)' refs/tags \
    | awk -v current="$tag" 'found { print; exit } $0 == current { found = 1 }')
fi

# Нет предыдущего тега (первый релиз) — берём всю историю до текущего.
if [[ -n "$previous" ]]; then
  range="${previous}..${tag}"
else
  range="$tag"
fi

# Категории и их порядок — как в .github/release-drafter.yml; "Other" для всего,
# что не разобралось по формату коммита (старые коммиты, merge из веб-интерфейса).
category_order=(features fixes docs maintenance configuration other)
declare -A category_title=(
  [features]='🚀 New Features'
  [fixes]='🐞 Bugs Fixes'
  [docs]='📚 Documentation'
  [maintenance]='🧰 Maintenance'
  [configuration]='🛠 Configuration'
  [other]='🧩 Other'
)
declare -A category_of=(
  [feature]=features
  [test]=features
  [bugfix]=fixes
  [docs]=docs
  [refactor]=maintenance
  [config]=configuration
  [ci]=configuration
)

# Формат заголовка коммита из .husky/commit-msg. Префикс задачи любой: потребители
# живут со своими (GA-123, IPB-456). Регэксп — в переменной: в [[ ]] скобка внутри
# [^)] ломает разбор условного выражения.
subject_regexp='^\[([A-Z][A-Z0-9]*-[0-9]+)\][[:space:]]+([a-z]+)\(([^)]+)\):[[:space:]]*(.+)$'

declare -A entries=()
count=0

# Один проход по диапазону: короткий sha и заголовок через \x1f (в заголовке его быть не может).
# tformat — терминатор, а не разделитель: иначе теряется последний коммит без перевода строки.
while IFS=$'\x1f' read -r short_sha subject; do
  [[ -n "$short_sha" ]] || continue
  count=$((count + 1))

  if [[ "$subject" =~ $subject_regexp ]]; then
    category="${category_of[${BASH_REMATCH[2]}]:-other}"
    entry="- [${BASH_REMATCH[1]}] ${BASH_REMATCH[3]}: ${BASH_REMATCH[4]} (${short_sha})"
  else
    category='other'
    entry="- ${subject} (${short_sha})"
  fi

  entries[$category]+="${entry}"$'\n'
done < <(git log --no-merges --pretty=tformat:'%h%x1f%s' "$range")

notes_file="${NOTES_FILE:-${RUNNER_TEMP:-/tmp}/release-notes.md}"
mkdir -p "$(dirname "$notes_file")"

noun='commits'
[[ "$count" -eq 1 ]] && noun='commit'

{
  echo "# What's Changed"
  echo

  if [[ -n "$previous" ]]; then
    echo "**${count} ${noun}** since \`${previous}\`."
  else
    echo "**${count} ${noun}** in this release."
  fi

  for category in "${category_order[@]}"; do
    [[ -n "${entries[$category]:-}" ]] || continue
    echo
    echo "## ${category_title[$category]}"
    echo
    printf '%s' "${entries[$category]}"
  done

  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    repository_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}"
    echo
    if [[ -n "$previous" ]]; then
      echo "**Full Changelog**: ${repository_url}/compare/${previous}...${tag}"
    else
      echo "**Full Changelog**: ${repository_url}/commits/${tag}"
    fi
  fi
} > "$notes_file"

{
  echo "notes_file=${notes_file}"
  echo "previous_tag=${previous}"
  echo "commit_count=${count}"
} >> "$GITHUB_OUTPUT"

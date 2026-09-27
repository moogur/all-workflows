#!/usr/bin/env bash
# Собирает тело GitHub-релиза из локальной git-истории между текущим и предыдущим
# тегом — без обращений к GitHub API. Идём --first-parent, поэтому у каждого PR
# (смёрженного через кнопку Merge или сквошенного) ровно одна запись, а коммиты
# внутри его ветки в тело не попадают сами по себе.
# Merge pull request #N from <owner>/<branch>: заголовок PR — первая непустая
#   строка тела merge-коммита, разбирается тем же форматом commit-msg.
# Squash-коммит "... (#N)": то же самое, но заголовок — сам subject без суффикса.
# Любой другой коммит на first-parent линии (прямой пуш, ребейзнутый PR, слияние
#   без "Merge pull request", напр. "Merge branch ...") — запись по коммиту,
#   как раньше: заголовок по формату commit-msg или как есть, короткий sha.
# Вход (env): TAG (по умолчанию тег из GITHUB_REF), PREVIOUS_TAG (пусто — считаем сами),
#   NOTES_FILE (пусто — $RUNNER_TEMP/release-notes.md), GITHUB_SERVER_URL, GITHUB_REPOSITORY,
#   GITHUB_OUTPUT.
# Выход: файл с телом релиза + строки "notes_file=", "previous_tag=", "change_count=" в $GITHUB_OUTPUT.
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

# Категории и их порядок — по типу коммита ([TASK-1] type(scope): subject);
# "Other" — то, что не разобралось по этому формату.
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
merge_pr_regexp='^Merge pull request #([0-9]+) from '
squash_pr_regexp='^(.*) \(#([0-9]+)\)$'

# Разбирает заголовок (PR-заголовок либо subject коммита) по формату commit-msg
# в глобальные task/scope/subj/category; не подошло — category=other, matched=0
# (вызывающий сам решает, как оформить запись «как есть»).
parse_subject() {
  local text="$1"
  if [[ "$text" =~ $subject_regexp ]]; then
    task="${BASH_REMATCH[1]}"
    scope="${BASH_REMATCH[3]}"
    subj="${BASH_REMATCH[4]}"
    category="${category_of[${BASH_REMATCH[2]}]:-other}"
    matched=1
  else
    matched=0
    category='other'
  fi
}

# Строит запись по заголовку PR (общая часть merge- и squash-PR — отличаются только
# тем, откуда берётся заголовок) в глобальную entry; category выставляет parse_subject.
pr_entry() {
  local title="$1" number="$2"
  parse_subject "$title"
  if [[ "$matched" -eq 1 ]]; then
    entry="- [${task}] ${scope}: ${subj} (#${number})"
  else
    entry="- ${title} (#${number})"
  fi
}

declare -A entries=()
count=0

# Один проход --first-parent по диапазону: короткий sha, subject и body коммита,
# записи разделены %x1e (в теле коммита такого байта быть не может). Формат:
# без "tformat" — терминатор ставим сами через %x1e, иначе git добавит перенос
# строки между записями поверх нашего терминатора.
while IFS= read -r -d $'\x1e' record; do
  record="${record#$'\n'}"
  # Не через read: тело многострочное, а read остановился бы на первом переводе строки.
  short_sha="${record%%$'\x1f'*}"
  rest="${record#*$'\x1f'}"
  subject="${rest%%$'\x1f'*}"
  body="${rest#*$'\x1f'}"
  [[ -n "$short_sha" ]] || continue
  count=$((count + 1))

  if [[ "$subject" =~ $merge_pr_regexp ]]; then
    pr_number="${BASH_REMATCH[1]}"
    # Заголовок PR — первая непустая строка тела merge-коммита.
    pr_title=''
    while IFS= read -r pr_title; do
      [[ -z "$pr_title" ]] || break
    done <<< "$body"
    pr_entry "$pr_title" "$pr_number"
  elif [[ "$subject" =~ $squash_pr_regexp ]]; then
    pr_entry "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    parse_subject "$subject"
    if [[ "$matched" -eq 1 ]]; then
      entry="- [${task}] ${scope}: ${subj} (${short_sha})"
    else
      entry="- ${subject} (${short_sha})"
    fi
  fi

  entries[$category]+="${entry}"$'\n'
done < <(git log --first-parent --pretty=format:'%h%x1f%s%x1f%b%x1e' "$range")

notes_file="${NOTES_FILE:-${RUNNER_TEMP:-/tmp}/release-notes.md}"
mkdir -p "$(dirname "$notes_file")"

noun='changes'
[[ "$count" -eq 1 ]] && noun='change'

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
  echo "change_count=${count}"
} >> "$GITHUB_OUTPUT"

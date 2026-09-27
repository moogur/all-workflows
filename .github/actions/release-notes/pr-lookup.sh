#!/usr/bin/env bash
# Часть release-notes (sourced из notes.sh): для коммита определяет смёрженный PR
# через GitHub API и его категорию по меткам PR (type:feature/type:test → features,
# type:bugfix → fixes, type:docs → docs, type:refactor → maintenance,
# type:config/type:ci → configuration). Вход (env): GITHUB_REPOSITORY, GH_TOKEN (для gh).
# Нет одного из них или gh нет в PATH — merged_pr_for_commit ничего не ищет и не падает.
# shellcheck disable=SC2034  # pr_number/pr_title/pr_author/pr_category читает notes.sh

declare -gA pr_label_category=(
  [type:feature]=features
  [type:test]=features
  [type:bugfix]=fixes
  [type:docs]=docs
  [type:refactor]=maintenance
  [type:config]=configuration
  [type:ci]=configuration
)

gh_available=1
if [[ -z "${GITHUB_REPOSITORY:-}" || -z "${GH_TOKEN:-}" ]] || ! command -v gh >/dev/null 2>&1; then
  gh_available=0
fi

gh_warned=0
# Предупреждение печатается один раз за прогон, а не на каждый коммит.
warn_gh_once() {
  [[ "$gh_warned" -eq 0 ]] || return 0
  gh_warned=1
  echo "release-notes: PR lookup unavailable (${1}), falling back to commit entries" >&2
}

[[ "$gh_available" -eq 1 ]] || warn_gh_once 'no GH_TOKEN/GITHUB_REPOSITORY/gh'

# merged_pr_for_commit <полный sha> — определяет смёрженный PR коммита и пишет
# результат в глобальные pr_number/pr_title/pr_author/pr_category (pr_number
# пустой — PR нет, коммит запушен напрямую, gh недоступен, запрос не удался,
# либо ответ gh api пришёл не JSON'ом).
# Не через $(...): warn_gh_once должен считаться в текущей оболочке, а не в подшелле.
merged_pr_for_commit() {
  local full_sha="$1" pr_json pr_line label labels label_list
  pr_number=''
  pr_title=''
  pr_author=''
  pr_category=''

  [[ "$gh_available" -eq 1 ]] || return 0

  if ! pr_json=$(gh api "repos/${GITHUB_REPOSITORY}/commits/${full_sha}/pulls" 2>/dev/null); then
    warn_gh_once 'gh api failed'
    return 0
  fi

  # Один jq вместо четырёх: первый смёрженный PR и его поля одним проходом по JSON.
  # Провал (не JSON в ответе gh api) — тот же fallback на коммит, а не падение скрипта.
  if ! pr_line=$(jq -r '
    [.[] | select(.merged_at != null)][0] as $pr
    | if $pr == null then empty else
        [$pr.number, $pr.title, $pr.user.login, ([$pr.labels[].name] | join(","))] | @tsv
      end
  ' <<< "$pr_json" 2>/dev/null); then
    warn_gh_once 'unexpected gh api response'
    return 0
  fi

  [[ -n "$pr_line" ]] || return 0

  IFS=$'\t' read -r pr_number pr_title pr_author labels <<< "$pr_line"

  pr_category=other
  IFS=',' read -ra label_list <<< "$labels"
  for label in "${label_list[@]}"; do
    [[ -n "${pr_label_category[$label]:-}" ]] || continue
    pr_category="${pr_label_category[$label]}"
    break
  done
}

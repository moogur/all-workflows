#!/usr/bin/env bats
# Guard-тест версий сторонних actions: GitHub выводит из эксплуатации node20,
# и запуск на устаревшем мажоре сначала даёт предупреждение, а потом падает.
# Здесь фиксируются минимальные мажоры, работающие на node24.

setup() {
  load helpers
  ROOT="$(repo_root)"
}

@test "сторонние actions не откатываются на мажоры с node20" {
  declare -A minimal=(
    [actions/checkout]=7
    [actions/setup-go]=7
    [actions/setup-node]=7
    [actions/upload-artifact]=7
    [actions/download-artifact]=7
    [release-drafter/release-drafter]=7
  )

  local line file reference major action
  while IFS= read -r line; do
    file="${line%%:*}"
    reference="${line##*uses: }"   # owner/repo@vN
    major="${reference##*@v}"
    action="${reference%@v*}"
    [[ -n "${minimal[$action]:-}" ]] || continue
    [ "$major" -ge "${minimal[$action]}" ] \
      || { echo "$(basename "$file"): $action@v$major ниже минимального v${minimal[$action]}"; return 1; }
  done < <(grep -rnoE 'uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@v[0-9]+' "$ROOT/.github")
}

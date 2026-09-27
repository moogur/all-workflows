#!/usr/bin/env bats
# Тесты для .github/actions/release-notes/notes.sh

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/release-notes/notes.sh"
  TMP="$(mktemp -d)"
  REPO="$TMP/repo"
  NOTES="$TMP/notes.md"
  GH_FIXTURES="$TMP/prs"
  export GITHUB_OUTPUT="$TMP/output"
  : > "$GITHUB_OUTPUT"

  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t
  git -C "$REPO" config user.name t
}

teardown() {
  rm -rf "$TMP"
}

# commit <сообщение> [дата]
commit() {
  local message="$1" date="${2:-2024-01-01T00:00:00}"
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git -C "$REPO" commit -q --allow-empty -m "$message"
}

# tag <имя> [дата] — аннотированный тег: дата создания берётся из GIT_COMMITTER_DATE.
tag() {
  local name="$1" date="${2:-2024-01-01T00:00:00}"
  GIT_COMMITTER_DATE="$date" git -C "$REPO" tag -a "$name" -m "$name"
}

# run_notes <тег> [переменные окружения...]
run_notes() {
  local release_tag="$1"
  shift
  run env TAG="$release_tag" NOTES_FILE="$NOTES" GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=user/repo "$@" \
    bash -c "cd '$REPO' && bash '$SCRIPT'"
}

# Заглушка gh: "api repos/.../commits/<sha>/pulls" отвечает фикстурой
# "$GH_FIXTURES/<sha>.json" (её нет — пустой список, PR не найден).
make_gh_stub() {
  mkdir -p "$TMP/bin" "$GH_FIXTURES"
  {
    echo '#!/usr/bin/env bash'
    echo 'path="$2"'
    echo 'sha="${path#repos/*/commits/}"'
    echo 'sha="${sha%/pulls}"'
    echo 'fixture="$GH_FIXTURES/$sha.json"'
    echo '[[ -f "$fixture" ]] && cat "$fixture" || echo "[]"'
  } > "$TMP/bin/gh"
  chmod +x "$TMP/bin/gh"
}

# Заглушка gh, которая всегда падает — имитация недоступного API.
make_gh_stub_failing() {
  mkdir -p "$TMP/bin"
  {
    echo '#!/usr/bin/env bash'
    echo 'exit 1'
  } > "$TMP/bin/gh"
  chmod +x "$TMP/bin/gh"
}

# Заглушка gh, которая завершается успешно, но отвечает не JSON'ом (например, HTML-страница сбоя).
make_gh_stub_non_json() {
  mkdir -p "$TMP/bin"
  {
    echo '#!/usr/bin/env bash'
    echo 'echo "<html>Service Unavailable</html>"'
  } > "$TMP/bin/gh"
  chmod +x "$TMP/bin/gh"
}

# pr_fixture <sha> <номер> <заголовок> <автор> <метка>
pr_fixture() {
  local sha="$1" number="$2" title="$3" author="$4" label="$5"
  jq -n --arg n "$number" --arg t "$title" --arg a "$author" --arg l "$label" \
    '[{number: ($n|tonumber), title: $t, merged_at: "2024-01-01T00:00:00Z", user: {login: $a}, labels: [{name: $l}]}]' \
    > "$GH_FIXTURES/$sha.json"
}

# run_notes_gh <тег> — как run_notes, но с заглушкой gh на PATH и GH_TOKEN.
run_notes_gh() {
  local release_tag="$1"
  shift
  run env TAG="$release_tag" NOTES_FILE="$NOTES" GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=user/repo \
    GH_TOKEN=token GH_FIXTURES="$GH_FIXTURES" PATH="$TMP/bin:$PATH" "$@" \
    bash -c "cd '$REPO' && bash '$SCRIPT'"
}

# ---------- выбор предыдущего тега ----------

@test "предыдущий тег — соседний по дате создания, а не максимальный по имени" {
  commit 'init' 2023-05-26T10:00:00
  tag 26.05.2023 2023-05-26T10:00:00
  commit '[GA-1] feature(api): add endpoint' 2026-03-14T10:00:00
  commit '[GA-2] bugfix(api): fix endpoint' 2026-03-14T11:00:00
  tag 14.03.2026 2026-03-14T12:00:00

  run_notes 14.03.2026
  [ "$status" -eq 0 ]
  # По имени «максимумом» был бы 26.05.2023 (26 > 14) — тогда диапазон вышел бы пустым.
  [ "$(output_value previous_tag)" = "26.05.2023" ]
  [ "$(output_value commit_count)" = "2" ]
}

@test "PREVIOUS_TAG переопределяет автоопределение" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): one' 2024-01-02T10:00:00
  tag v1.1.0 2024-01-02T10:00:00
  commit '[GA-2] feature(api): two' 2024-01-03T10:00:00
  tag v1.2.0 2024-01-03T10:00:00

  run_notes v1.2.0 PREVIOUS_TAG=v1.0.0
  [ "$status" -eq 0 ]
  [ "$(output_value previous_tag)" = "v1.0.0" ]
  [ "$(output_value commit_count)" = "2" ]
}

@test "первый релиз: предыдущего тега нет, берётся вся история" {
  commit 'init' 2024-01-01T10:00:00
  commit '[GA-1] feature(api): add endpoint' 2024-01-02T10:00:00
  tag v1.0.0 2024-01-02T10:00:00

  run_notes v1.0.0
  [ "$status" -eq 0 ]
  [ "$(output_value previous_tag)" = "" ]
  [ "$(output_value commit_count)" = "2" ]
  grep -qF '**Full Changelog**: https://github.com/user/repo/commits/v1.0.0' "$NOTES"
  grep -qF '**2 commits** in this release.' "$NOTES"
}

# ---------- тело релиза ----------

@test "коммиты раскладываются по категориям релиза" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-557] feature(frontend): add deploy spa and pwa' 2024-01-02T10:00:00
  commit '[GA-558] bugfix(docker): keep date format' 2024-01-02T11:00:00
  commit '[GA-559] docs(readme): describe release' 2024-01-02T12:00:00
  commit '[GA-560] refactor(actions): extract script' 2024-01-02T13:00:00
  commit '[GA-561] ci(workflows): add yamllint' 2024-01-02T14:00:00
  tag v1.1.0 2024-01-02T15:00:00

  run_notes v1.1.0
  [ "$status" -eq 0 ]
  grep -qF '## 🚀 New Features' "$NOTES"
  grep -qF '## 🐞 Bugs Fixes' "$NOTES"
  grep -qF '## 📚 Documentation' "$NOTES"
  grep -qF '## 🧰 Maintenance' "$NOTES"
  grep -qF '## 🛠 Configuration' "$NOTES"
  grep -q '^- \[GA-557\] frontend: add deploy spa and pwa ([0-9a-f]\{7,\})$' "$NOTES"
}

@test "test попадает в New Features, config — в Configuration" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] test(actions): cover resolve' 2024-01-02T10:00:00
  commit '[GA-2] config(editor): set indent' 2024-01-02T11:00:00
  tag v1.1.0 2024-01-02T12:00:00

  run_notes v1.1.0
  [ "$status" -eq 0 ]
  # Категория идёт до своих записей, поэтому сравниваем порядок строк.
  features_line=$(grep -n '🚀 New Features' "$NOTES" | cut -d: -f1)
  test_line=$(grep -n 'GA-1' "$NOTES" | cut -d: -f1)
  configuration_line=$(grep -n '🛠 Configuration' "$NOTES" | cut -d: -f1)
  config_line=$(grep -n 'GA-2' "$NOTES" | cut -d: -f1)
  [ "$features_line" -lt "$test_line" ]
  [ "$test_line" -lt "$configuration_line" ]
  [ "$configuration_line" -lt "$config_line" ]
}

@test "префикс задачи может быть любым: потребители живут со своими" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[IPB-572] refactor(src): развести ответственности' 2024-01-02T10:00:00
  tag v1.1.0 2024-01-02T11:00:00

  run_notes v1.1.0
  [ "$status" -eq 0 ]
  grep -qF '## 🧰 Maintenance' "$NOTES"
  grep -q '^- \[IPB-572\] src: развести ответственности ([0-9a-f]\{7,\})$' "$NOTES"
}

@test "коммит не по формату попадает в Other как есть" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit 'Update README.md' 2024-01-02T10:00:00
  tag v1.1.0 2024-01-02T11:00:00

  run_notes v1.1.0
  [ "$status" -eq 0 ]
  grep -qF '## 🧩 Other' "$NOTES"
  grep -q '^- Update README.md ([0-9a-f]\{7,\})$' "$NOTES"
}

@test "слияния в тело не попадают" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  git -C "$REPO" checkout -q -b feature
  commit '[GA-1] feature(api): add endpoint' 2024-01-02T10:00:00
  git -C "$REPO" checkout -q master 2>/dev/null || git -C "$REPO" checkout -q main
  GIT_AUTHOR_DATE=2024-01-03T10:00:00 GIT_COMMITTER_DATE=2024-01-03T10:00:00 \
    git -C "$REPO" merge -q --no-ff -m 'Merge branch feature' feature
  tag v1.1.0 2024-01-03T11:00:00

  run_notes v1.1.0
  [ "$status" -eq 0 ]
  [ "$(output_value commit_count)" = "1" ]
  run grep -cF 'Merge branch feature' "$NOTES"
  [ "$status" -ne 0 ]
}

@test "число коммитов в единственном числе и ссылка на сравнение" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] bugfix(api): fix endpoint' 2024-01-02T10:00:00
  tag v1.1.0 2024-01-02T11:00:00

  run_notes v1.1.0
  [ "$status" -eq 0 ]
  [ "$(output_value commit_count)" = "1" ]
  grep -qF '**1 commit** since `v1.0.0`.' "$NOTES"
  grep -qF '**Full Changelog**: https://github.com/user/repo/compare/v1.0.0...v1.1.0' "$NOTES"
}

@test "тег без новых коммитов даёт пустое тело без категорий" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  tag v1.0.1 2024-01-02T10:00:00

  run_notes v1.0.1
  [ "$status" -eq 0 ]
  [ "$(output_value commit_count)" = "0" ]
  run grep -cF '## ' "$NOTES"
  [ "$status" -ne 0 ]
}

# ---------- ошибки ----------

@test "неизвестный тег завершается с ошибкой и подсказкой про историю" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00

  run_notes v9.9.9
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
  [[ "$output" == *"fetch-depth"* ]]
}

@test "без TAG и GITHUB_REF завершается с ошибкой" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00

  run env NOTES_FILE="$NOTES" GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    bash -c "cd '$REPO' && bash '$SCRIPT'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"TAG is required"* ]]
}

@test "GITHUB_REF используется, когда TAG не задан" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): add endpoint' 2024-01-02T10:00:00
  tag v1.1.0 2024-01-02T11:00:00

  run env GITHUB_REF=refs/tags/v1.1.0 NOTES_FILE="$NOTES" GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    bash -c "cd '$REPO' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$(output_value previous_tag)" = "v1.0.0" ]
}

# ---------- автоопределение PR ----------

@test "коммит смёрженного PR даёт запись PR, категория по метке" {
  make_gh_stub
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): add endpoint' 2024-01-02T10:00:00
  pr_fixture "$(git -C "$REPO" rev-parse HEAD)" 42 'Add cool endpoint' alice type:feature
  tag v1.1.0 2024-01-02T11:00:00

  run_notes_gh v1.1.0
  [ "$status" -eq 0 ]
  grep -qF '## 🚀 New Features' "$NOTES"
  grep -qF -- '- Add cool endpoint (#42) @alice' "$NOTES"
  run grep -cF 'GA-1' "$NOTES"
  [ "$status" -ne 0 ]   # запись по PR, а не по формату коммита
}

@test "несколько коммитов одного PR дают одну запись (дедуп по номеру)" {
  make_gh_stub
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): part one' 2024-01-02T10:00:00
  pr_fixture "$(git -C "$REPO" rev-parse HEAD)" 42 'Add cool endpoint' alice type:feature
  commit '[GA-1] feature(api): part two' 2024-01-02T11:00:00
  pr_fixture "$(git -C "$REPO" rev-parse HEAD)" 42 'Add cool endpoint' alice type:feature
  tag v1.1.0 2024-01-02T12:00:00

  run_notes_gh v1.1.0
  [ "$status" -eq 0 ]
  [ "$(output_value commit_count)" = "2" ]   # оба коммита посчитаны
  [ "$(grep -cF '#42' "$NOTES")" -eq 1 ]     # но запись в теле одна
}

@test "PR и прямой коммит вперемешку: у каждого своя запись" {
  make_gh_stub
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): via pr' 2024-01-02T10:00:00
  pr_fixture "$(git -C "$REPO" rev-parse HEAD)" 42 'Add cool endpoint' alice type:feature
  commit '[GA-2] bugfix(api): pushed directly' 2024-01-02T11:00:00
  tag v1.1.0 2024-01-02T12:00:00

  run_notes_gh v1.1.0
  [ "$status" -eq 0 ]
  grep -qF -- '- Add cool endpoint (#42) @alice' "$NOTES"
  grep -q '^- \[GA-2\] api: pushed directly ([0-9a-f]\{7,\})$' "$NOTES"
}

@test "gh недоступен: все коммиты падают в формат по коммитам, предупреждение одно" {
  make_gh_stub_failing
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): one' 2024-01-02T10:00:00
  commit '[GA-2] bugfix(api): two' 2024-01-02T11:00:00
  tag v1.1.0 2024-01-02T12:00:00

  run_notes_gh v1.1.0
  [ "$status" -eq 0 ]
  grep -q '^- \[GA-1\] api: one ([0-9a-f]\{7,\})$' "$NOTES"
  grep -q '^- \[GA-2\] api: two ([0-9a-f]\{7,\})$' "$NOTES"
  [ "$(grep -cF 'PR lookup unavailable' <<< "$output")" -eq 1 ]
}

@test "gh api отвечает не JSON'ом: коммиты падают в формат по коммитам, предупреждение одно" {
  make_gh_stub_non_json
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-1] feature(api): one' 2024-01-02T10:00:00
  commit '[GA-2] bugfix(api): two' 2024-01-02T11:00:00
  tag v1.1.0 2024-01-02T12:00:00

  run_notes_gh v1.1.0
  [ "$status" -eq 0 ]
  grep -q '^- \[GA-1\] api: one ([0-9a-f]\{7,\})$' "$NOTES"
  grep -q '^- \[GA-2\] api: two ([0-9a-f]\{7,\})$' "$NOTES"
  [ "$(grep -cF 'unexpected gh api response' <<< "$output")" -eq 1 ]
}

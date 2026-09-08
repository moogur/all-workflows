#!/usr/bin/env bats
# Тесты для .github/actions/remote-update-check/check.sh

setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/remote-update-check/check.sh"
  TMP="$(mktemp -d)"
  export GITHUB_OUTPUT="$TMP/output"
  : > "$GITHUB_OUTPUT"
}

teardown() {
  rm -rf "$TMP"
}

# Создаёт временный git-репозиторий с переданными тегами: по тегу на коммит,
# в порядке аргументов, с разнесёнными во времени датами коммитов — чтобы
# «самый свежий тег» был однозначным.
make_repo() {
  local repo="$TMP/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q -b master
  git -C "$repo" config user.email t@t
  git -C "$repo" config user.name t
  git -C "$repo" commit -q --allow-empty -m init
  local tag
  local timestamp=1700000000
  for tag in "$@"; do
    timestamp=$((timestamp + 3600))
    GIT_AUTHOR_DATE="@$timestamp" GIT_COMMITTER_DATE="@$timestamp" \
      git -C "$repo" commit -q --allow-empty -m "$tag"
    git -C "$repo" tag "$tag"
  done
  echo "$repo"
}

# ---------- type=commit ----------

@test "commit: возвращает время последнего коммита ветки" {
  repo=$(make_repo)
  expected=$(git -C "$repo" log -1 --format=%ct)
  run env REPOSITORY_URL="$repo" CHECK_TYPE=commit REPOSITORY_BRANCH=master GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value value)" = "$expected" ]
}

@test "commit: значение меняется после нового коммита" {
  repo=$(make_repo)
  run env REPOSITORY_URL="$repo" CHECK_TYPE=commit GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  before=$(output_value value)
  GIT_COMMITTER_DATE="@$((before + 60))" git -C "$repo" commit -q --allow-empty -m next
  : > "$GITHUB_OUTPUT"
  run env REPOSITORY_URL="$repo" CHECK_TYPE=commit GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value value)" = "$((before + 60))" ]
}

@test "commit: читает указанную ветку" {
  repo=$(make_repo)
  git -C "$repo" checkout -q -b release
  git -C "$repo" commit -q --allow-empty -m release-commit
  expected=$(git -C "$repo" log -1 --format=%ct release)
  git -C "$repo" checkout -q master
  run env REPOSITORY_URL="$repo" CHECK_TYPE=commit REPOSITORY_BRANCH=release GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value value)" = "$expected" ]
}

@test "type по умолчанию — commit" {
  repo=$(make_repo)
  expected=$(git -C "$repo" log -1 --format=%ct)
  run env REPOSITORY_URL="$repo" GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value value)" = "$expected" ]
}

# ---------- type=tag ----------

@test "tag: берёт самый свежий тег по дате, а не максимальный по имени" {
  # Именно этот кейс ломала версионная сортировка: среди датных тегов
  # «максимумом» оказывался 26.05.2023, потому что 26 > 14.
  repo=$(make_repo 26.05.2023 14.03.2026)
  run env REPOSITORY_URL="$repo" CHECK_TYPE=tag GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value value)" = "14.03.2026" ]
}

@test "tag: семверные теги — свежий выигрывает у старшего по номеру" {
  repo=$(make_repo v2.0.0 v1.9.0)
  run env REPOSITORY_URL="$repo" CHECK_TYPE=tag GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value value)" = "v1.9.0" ]
}

@test "tag: неверсионный тег тоже годится как маркер" {
  repo=$(make_repo v1.0.0 nightly)
  run env REPOSITORY_URL="$repo" CHECK_TYPE=tag GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value value)" = "nightly" ]
}

@test "tag: значение меняется после нового тега" {
  repo=$(make_repo v1.0.0)
  run env REPOSITORY_URL="$repo" CHECK_TYPE=tag GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$(output_value value)" = "v1.0.0" ]
  GIT_COMMITTER_DATE="@1800000000" git -C "$repo" commit -q --allow-empty -m next
  git -C "$repo" tag v1.0.1
  : > "$GITHUB_OUTPUT"
  run env REPOSITORY_URL="$repo" CHECK_TYPE=tag GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(output_value value)" = "v1.0.1" ]
}

# ---------- ошибки ----------

@test "tag: репозиторий без тегов завершается с ошибкой и сообщением" {
  repo=$(make_repo)
  run env REPOSITORY_URL="$repo" CHECK_TYPE=tag GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No tags found"* ]]
}

@test "неизвестный type завершается с ошибкой и сообщением" {
  repo=$(make_repo)
  run env REPOSITORY_URL="$repo" CHECK_TYPE=tags GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown type"* ]]
}

@test "без repository_url завершается с ошибкой" {
  run env GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "недоступный репозиторий завершается с ошибкой" {
  run env REPOSITORY_URL="$TMP/missing" CHECK_TYPE=tag GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

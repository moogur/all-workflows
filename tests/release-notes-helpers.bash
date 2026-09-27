# Общая обвязка тестов release-notes/notes.sh: временный git-репозиторий и запуск скрипта.
# shellcheck shell=bash disable=SC2034  # SCRIPT/NOTES читают тесты, run/load — функции bats
setup() {
  load helpers
  ROOT="$(repo_root)"
  SCRIPT="$ROOT/.github/actions/release-notes/notes.sh"
  TMP="$(mktemp -d)"
  REPO="$TMP/repo"
  NOTES="$TMP/notes.md"
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

# default_branch — имя ветки, на которую указывает HEAD (init создаёт master либо main
# в зависимости от глобального конфига git).
default_branch() {
  git -C "$REPO" branch --show-current
}

# merge_commit <ветка> <subject> <body> [дата] — реальный merge-коммит (--no-ff) с
# произвольным заголовком/телом: имя ветки в subject не обязано совпадать с реальным
# именем ветки, ровно как у настоящего "Merge pull request" от GitHub.
merge_commit() {
  local branch="$1" subject="$2" body="$3" date="${4:-2024-01-01T00:00:00}"
  git -C "$REPO" merge -q --no-ff --no-commit "$branch"
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git -C "$REPO" commit -q -m "$subject" -m "$body"
}

# run_notes <тег> [переменные окружения...]
run_notes() {
  local release_tag="$1"
  shift
  run env TAG="$release_tag" NOTES_FILE="$NOTES" GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=user/repo "$@" \
    bash -c "cd '$REPO' && bash '$SCRIPT'"
}

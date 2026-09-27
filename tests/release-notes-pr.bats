#!/usr/bin/env bats
# Тесты для .github/actions/release-notes/notes.sh: PR из локальной истории (--first-parent).

load release-notes-helpers

# ---------- PR из локальной истории (--first-parent) ----------

@test "смёрженный через кнопку GitHub PR даёт одну запись по заголовку PR, коммиты ветки не попадают по отдельности" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  base="$(default_branch)"

  git -C "$REPO" checkout -q -b feature
  commit '[GA-1] wip: first attempt' 2024-01-02T10:00:00
  commit '[GA-1] wip: second attempt' 2024-01-02T11:00:00
  git -C "$REPO" checkout -q "$base"
  merge_commit feature 'Merge pull request #12 from user/feature' \
    '[GA-10] feature(api): add cool endpoint' 2024-01-02T12:00:00
  tag v1.1.0 2024-01-02T13:00:00

  run_notes v1.1.0
  [ "$status" -eq 0 ]
  [ "$(output_value change_count)" = "1" ]
  grep -qF '## 🚀 New Features' "$NOTES"
  grep -qF -- '- [GA-10] api: add cool endpoint (#12)' "$NOTES"
  run grep -cF 'wip' "$NOTES"
  [ "$status" -ne 0 ]   # коммиты внутри ветки PR не попадают в тело сами по себе
}

@test "описание PR в теле merge-коммита не попадает в запись" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  base="$(default_branch)"

  git -C "$REPO" checkout -q -b feature
  commit '[GA-1] wip: attempt' 2024-01-02T10:00:00
  git -C "$REPO" checkout -q "$base"
  merge_commit feature 'Merge pull request #12 from user/feature' \
    $'[GA-10] feature(api): add endpoint\n\nLong description\nof the PR' 2024-01-02T12:00:00
  tag v1.1.0 2024-01-02T13:00:00

  run_notes v1.1.0
  [ "$status" -eq 0 ]
  grep -qF -- '- [GA-10] api: add endpoint (#12)' "$NOTES"
  run grep -cF 'Long description' "$NOTES"
  [ "$status" -ne 0 ]
}

@test "заголовок смёрженного PR не по формату commit-msg — попадает в Other как есть" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  base="$(default_branch)"

  git -C "$REPO" checkout -q -b feature
  commit 'wip' 2024-01-02T10:00:00
  git -C "$REPO" checkout -q "$base"
  merge_commit feature 'Merge pull request #7 from user/feature' \
    'Add a cool endpoint' 2024-01-02T11:00:00
  tag v1.1.0 2024-01-02T12:00:00

  run_notes v1.1.0
  [ "$status" -eq 0 ]
  grep -qF '## 🧩 Other' "$NOTES"
  grep -qF -- '- Add a cool endpoint (#7)' "$NOTES"
}

@test "сквошенный PR-коммит (заголовок с суффиксом #N) разбирается тем же форматом" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  commit '[GA-2] bugfix(x): y (#13)' 2024-01-02T10:00:00
  tag v1.1.0 2024-01-02T11:00:00

  run_notes v1.1.0
  [ "$status" -eq 0 ]
  grep -qF '## 🐞 Bugs Fixes' "$NOTES"
  grep -qF -- '- [GA-2] x: y (#13)' "$NOTES"
}

@test "PR и прямой коммит вперемешку: у каждого своя запись" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  base="$(default_branch)"

  git -C "$REPO" checkout -q -b feature
  commit '[GA-1] wip' 2024-01-02T10:00:00
  git -C "$REPO" checkout -q "$base"
  merge_commit feature 'Merge pull request #12 from user/feature' \
    '[GA-10] feature(api): via pr' 2024-01-02T11:00:00
  commit '[GA-2] bugfix(api): pushed directly' 2024-01-02T12:00:00
  tag v1.1.0 2024-01-02T13:00:00

  run_notes v1.1.0
  [ "$status" -eq 0 ]
  [ "$(output_value change_count)" = "2" ]
  grep -qF -- '- [GA-10] api: via pr (#12)' "$NOTES"
  grep -q '^- \[GA-2\] api: pushed directly ([0-9a-f]\{7,\})$' "$NOTES"
}

@test "слияние без Merge pull request (Merge branch) — запись Other по короткому sha, без содержимого ветки" {
  commit 'init' 2024-01-01T10:00:00
  tag v1.0.0 2024-01-01T10:00:00
  base="$(default_branch)"

  git -C "$REPO" checkout -q -b chore
  commit '[GA-1] feature(api): add endpoint' 2024-01-02T10:00:00
  git -C "$REPO" checkout -q "$base"
  GIT_AUTHOR_DATE=2024-01-02T11:00:00 GIT_COMMITTER_DATE=2024-01-02T11:00:00 \
    git -C "$REPO" merge -q --no-ff -m "Merge branch 'chore'" chore
  tag v1.1.0 2024-01-02T12:00:00

  run_notes v1.1.0
  [ "$status" -eq 0 ]
  [ "$(output_value change_count)" = "1" ]
  grep -qF '## 🧩 Other' "$NOTES"
  grep -q "^- Merge branch 'chore' ([0-9a-f]\\{7,\\})\$" "$NOTES"
  run grep -cF 'GA-1' "$NOTES"
  [ "$status" -ne 0 ]   # содержимое смёрженной ветки не попадает в тело отдельной записью
}

#!/usr/bin/env bats
# Guard-тест: во всех workflow'ах и composite actions в теле `run:` нет `${{ }}`.
# Значения (inputs, github.*, outputs шагов, secrets) передаются через `env:` шага
# и используются в скрипте как "$VAR" (docs/security.md, п. 8). `if:`, `with:` и `env:`
# выражения не трогаются — проверяются только тела run.

setup() {
  load helpers
  ROOT="$(repo_root)"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# Печатает "файл:строка: текст" для каждой строки с ${{ внутри run: (блочного и однострочного).
# Блок run кончается на первой непустой строке с отступом не глубже ключа run.
scan_run_bodies() {
  awk '
    function indent(s) { match(s, /^ */); return RLENGTH }
    inrun && $0 ~ /[^ ]/ && indent($0) <= run_indent { inrun = 0 }
    inrun && /\$\{\{/ { print FILENAME ":" FNR ": " $0 }
    !inrun && /^[ -]*run:/ {
      rest = $0; sub(/^[ -]*run:[ ]*/, "", rest)
      run_indent = indent($0); if ($0 ~ /^ *- /) run_indent += 2
      if (rest ~ /^[|>][-+]?$/) inrun = 1
      else if (rest ~ /\$\{\{/) print FILENAME ":" FNR ": " $0
    }
  ' "$@"
}

@test "ни в одном workflow и action нет \${{ }} в теле run" {
  run scan_run_bodies "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/actions/*/action.yml
  [ -z "$output" ]
}

@test "проверка охватывает workflow'ы и actions (глоб не пустой)" {
  [ "$(ls "$ROOT"/.github/workflows/*.yml | wc -l)" -ge 10 ]
  [ "$(ls "$ROOT"/.github/actions/*/action.yml | wc -l)" -ge 10 ]
}

@test "сканер ловит \${{ }} в блочном run" {
  cat > "$TMP/bad.yml" <<'Y'
jobs:
  j:
    steps:
      - name: x
        run: |
          echo ok
          echo "${{ github.actor }}"
Y
  run scan_run_bodies "$TMP/bad.yml"
  [[ "$output" == *"bad.yml:7:"* ]]
}

@test "сканер ловит \${{ }} в однострочном run и в run после ключа в списке" {
  cat > "$TMP/bad.yml" <<'Y'
steps:
  - run: cp -r ${{ inputs.folder }}/. .
  - name: y
    run: echo ${{ inputs.x }}
Y
  run scan_run_bodies "$TMP/bad.yml"
  [[ "$output" == *"bad.yml:2:"* ]]
  [[ "$output" == *"bad.yml:4:"* ]]
}

@test "сканер не трогает env, with и if рядом с run" {
  cat > "$TMP/ok.yml" <<'Y'
steps:
  - name: z
    if: github.ref_type == 'tag'
    env:
      ACTOR: ${{ github.actor }}
    run: |
      echo "$ACTOR"
  - uses: some/action@v1
    with:
      token: ${{ secrets.GITHUB_TOKEN }}
Y
  run scan_run_bodies "$TMP/ok.yml"
  [ -z "$output" ]
}

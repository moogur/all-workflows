#!/usr/bin/env bats
# Guard-тесты входа check_target: Go-workflow запускает проверки проекта целью make из его Makefile.
# Вход необязателен и пуст по умолчанию, шаг выполняется только с непустым входом, значение идёт
# через env и до запуска make проверяется как имя цели — произвольную команду передать нельзя.

setup() {
  load helpers
  WF="$(repo_root)/.github/workflows/actions_for_push_go.yml"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# Тело run шага «Run project checks» как отдельный скрипт.
extract_step_script() {
  awk '
    /^ +- name:/ { inside = ($0 ~ /Run project checks/) }
    inside && /^ +run: \|/ { body = 1; next }
    body && /^ +- name:/ { exit }
    body && /^ +#/ { exit }
    body { sub(/^          /, ""); print }
  ' "$WF"
}

@test "вход check_target объявлен, не обязателен и по умолчанию пуст" {
  grep -qE '^ +check_target:' "$WF"
  grep -A4 -E '^ +check_target:' "$WF" | grep -qE '^ +required: false'
  grep -A4 -E "^ +check_target:" "$WF" | grep -qE "^ +default: ''"
}

@test "шаг проверок закрыт непустым check_target и берёт значение из env" {
  run awk '
    /^ +- name:/ { inside = ($0 ~ /Run project checks/) }
    inside && /if: "inputs\.check_target != '\'''\''"/ { gated = 1 }
    inside && /CHECK_TARGET: \$\{\{ inputs\.check_target \}\}/ { env = 1 }
    END { if (gated && env) print "ok" }
  ' "$WF"
  [ "$output" = "ok" ]
}

@test "проверки проекта идут до тестов" {
  run awk '
    /^ +- name:/ { step++ }
    /Run project checks/ { checks = step }
    /^ +- name: Run tests/ { tests = step }
    END { if (checks > 0 && checks < tests) print "ok" }
  ' "$WF"
  [ "$output" = "ok" ]
}

@test "имя цели запускает make с этой целью" {
  extract_step_script > "$TMP/step.sh"
  printf '#!/bin/sh\necho "STUB-MAKE $*"\n' > "$TMP/make" && chmod +x "$TMP/make"
  PATH="$TMP:$PATH" CHECK_TARGET=ci-check run bash "$TMP/step.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "STUB-MAKE ci-check" ]
}

@test "не имя цели отклоняется, make не запускается" {
  extract_step_script > "$TMP/step.sh"
  printf '#!/bin/sh\necho "STUB-MAKE $*"\n' > "$TMP/make" && chmod +x "$TMP/make"
  local bad
  for bad in 'lint; curl evil' 'lint && rm -rf /' '$(id)' '-f /tmp/x' 'Lint' 'lint test'; do
    PATH="$TMP:$PATH" CHECK_TARGET="$bad" run bash "$TMP/step.sh"
    [ "$status" -ne 0 ] || { echo "принято: $bad"; return 1; }
    [[ "$output" != *STUB-MAKE* ]] || { echo "make запущен для: $bad"; return 1; }
  done
}

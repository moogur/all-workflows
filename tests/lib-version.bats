#!/usr/bin/env bats
# Тесты для lib/version.sh: формат версии (дата/semver) и его разбор.
# Поведение action tag-format (env/GITHUB_OUTPUT) — в tests/tag-format.bats.

setup() {
  load helpers
  ROOT="$(repo_root)"
  LIB="$ROOT/lib/version.sh"
}

sh() {
  run bash -c "source '$LIB'; $*"
}

# ---------- version_format: дата ----------

@test "дата dd.mm.yyyy" {
  sh "version_format 14.03.2026"
  [ "$status" -eq 0 ]
  [ "$output" = "date" ]
}

@test "метка авто-сборки со временем" {
  sh "version_format 14.03.2026-0930-auto"
  [ "$status" -eq 0 ]
  [ "$output" = "date" ]
}

@test "старая метка авто-сборки без времени" {
  sh "version_format 14.03.2026-auto"
  [ "$status" -eq 0 ]
  [ "$output" = "date" ]
}

# ---------- version_format: semver ----------

@test "semver vX.Y.Z" {
  sh "version_format v1.2.3"
  [ "$status" -eq 0 ]
  [ "$output" = "semver" ]
}

@test "semver с нулями в разрядах" {
  sh "version_format v1.0.0"
  [ "$output" = "semver" ]
}

@test "semver с многозначными разрядами" {
  sh "version_format v10.29.106"
  [ "$output" = "semver" ]
}

# ---------- version_format: ошибки ----------

@test "semver без префикса v отклоняется" {
  sh "version_format 1.2.3"
  [ "$status" -ne 0 ]
  [[ "$output" == *"neither a date"* ]]
}

@test "предрелизный тег отклоняется" {
  sh "version_format v1.2.3-rc.1"
  [ "$status" -ne 0 ]
}

@test "неполная версия отклоняется" {
  sh "version_format v1.2"
  [ "$status" -ne 0 ]
}

@test "дата не в формате dd.mm.yyyy отклоняется" {
  sh "version_format 2026-03-14"
  [ "$status" -ne 0 ]
}

@test "произвольная строка отклоняется" {
  sh "version_format master"
  [ "$status" -ne 0 ]
}

# ---------- version_semver_parts ----------

@test "semver_parts: разбирает major minor patch" {
  sh "version_semver_parts v1.2.3"
  [ "$output" = "1 2 3" ]
}

@test "semver_parts: многозначные разряды" {
  sh "version_semver_parts v10.29.106"
  [ "$output" = "10 29 106" ]
}

# ---------- version_auto_label ----------

@test "auto_label: формат dd.mm.yyyy-HHMM-auto" {
  sh "version_auto_label"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{2}\.[0-9]{2}\.[0-9]{4}-[0-9]{4}-auto$ ]]
}

# ---------- version_strip_ref_prefix ----------

@test "strip_ref_prefix: снимает refs/tags/" {
  sh "version_strip_ref_prefix refs/tags/v1.2.3"
  [ "$output" = "v1.2.3" ]
}

@test "strip_ref_prefix: без префикса оставляет как есть" {
  sh "version_strip_ref_prefix v1.2.3"
  [ "$output" = "v1.2.3" ]
}

# ---------- version_strip_prefix ----------

@test "strip_prefix: снимает v по умолчанию" {
  sh "version_strip_prefix v1.2.3 v"
  [ "$output" = "1.2.3" ]
}

@test "strip_prefix: пустой префикс оставляет версию как есть" {
  sh "version_strip_prefix v1.2.3 ''"
  [ "$output" = "v1.2.3" ]
}

@test "strip_prefix: произвольный префикс release-" {
  sh "version_strip_prefix release-2.0 release-"
  [ "$output" = "2.0" ]
}

@test "strip_prefix: тег без искомого префикса остаётся без изменений" {
  sh "version_strip_prefix 1.2.3 v"
  [ "$output" = "1.2.3" ]
}

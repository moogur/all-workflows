# Приводит JSON-отчёт jest (его же пишет JSON-репортер vitest) к общему виду для render.jq.
# Вход: отчёт целиком, переменная $root — префикс (рабочий каталог со слэшем), который
# срезается с путей файлов. pending/skipped/todo/disabled считаются пропущенными.
def status:
  if . == "passed" then "passed"
  elif . == "failed" then "failed"
  elif IN("pending", "skipped", "todo", "disabled") then "skipped"
  else null end;

{
  label: "Файл",
  groups: [
    (.testResults // [])[]
    | ((.assertionResults // []) | map({name: .fullName, status: (.status | status)} | select(.status != null))) as $tests
    | {
        name: (.name | if startswith($root) then .[($root | length):] else . end),
        tests: $tests,
        # Файл не запустился (ошибка импорта, синтаксиса): отчёта по тестам нет, но статус failed.
        crash: (if .status == "failed" and ((.assertionResults // []) | length) == 0
                then "файл не запустился (ошибка загрузки, синтаксиса или в хуке)"
                else null end)
      }
    | select((.tests | length) > 0 or .crash != null)
  ] | sort_by(.name)
}

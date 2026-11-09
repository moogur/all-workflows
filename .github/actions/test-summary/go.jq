# Приводит поток событий `go test -json` (построчный JSON, читается через jq -nR)
# к общему виду для render.jq. Строки, не являющиеся JSON-объектом, пропускаются.
# Учитываются только итоговые события (pass/fail/skip): подтесты считаются как тесты,
# пакеты без тестовых файлов дают лишь пакетное событие skip и в сводку не попадают.
def terminal: .Action == "pass" or .Action == "fail" or .Action == "skip";
def status: {pass: "passed", fail: "failed", skip: "skipped"}[.];

reduce (inputs | fromjson? | objects | select(terminal and .Package != null)) as $e
  ({tests: [], packages: {}};
   if $e.Test != null
   then .tests += [{package: $e.Package, name: $e.Test, status: ($e.Action | status)}]
   else .packages[$e.Package] = $e.Action end)
| (.tests | group_by(.package) | map({key: .[0].package, value: .}) | from_entries) as $byPackage
| .packages as $packages
| ([$byPackage | keys[]] + [$packages | to_entries[] | select(.value == "fail") | .key] | unique) as $names
| {
    label: "Пакет",
    groups: [
      $names[] as $p
      | ($byPackage[$p] // []) as $tests
      | {
          name: $p,
          tests: ($tests | map({name, status})),
          # Пакет упал, а ни один тест не упал: сборка, TestMain, паника вне теста и т.п.
          crash: (if $packages[$p] == "fail" and ($tests | map(select(.status == "failed")) | length) == 0
                  then "пакет завершился с ошибкой, ни один тест не упал (сборка, TestMain, таймаут)"
                  else null end)
        }
    ]
  }

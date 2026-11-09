# Общий вид {label, groups: [{name, tests: [{name, status}], crash}]} -> Markdown (jq -r).
# Списки имён обрезаются: сводка шага ограничена 1 MiB.
def limit: 200;
def code: "`" + (tostring | gsub("[`\n\r]"; "'")) + "`";
def cell: tostring | gsub("\\|"; "\\|");
def count($s): map(select(.status == $s)) | length;
def item: "- " + (.group | code) + " — " + (if .note != null then .note else (.name | code) end);
def list: (.[:limit] | map(item)) + (if length > limit then ["- … и ещё \(length - limit)"] else [] end);

.label as $label
| (.groups | map(
    . + {
      passed: (.tests | count("passed")),
      failed: ((.tests | count("failed")) + (if .crash != null then 1 else 0 end)),
      skipped: (.tests | count("skipped"))
    })) as $rows
| [ $rows[] as $g | $g.name as $name
    | ($g.tests[] | select(.status == "failed") | {group: $name, name}),
      (select($g.crash != null) | {group: $name, note: $g.crash}) ] as $failed
| [ $rows[] as $g | $g.name as $name
    | $g.tests[] | select(.status == "skipped") | {group: $name, name} ] as $skipped
| ($rows | map(.passed) | add // 0) as $passed
| ($rows | map(.failed) | add // 0) as $failedCount
| ($rows | map(.skipped) | add // 0) as $skippedCount
| [ "## Тесты: пройдено \($passed), упало \($failedCount), пропущено \($skippedCount)", "" ]
  + (if ($rows | length) == 0 then ["Ни одного теста не запущено.", ""]
     else
       [ "| \($label) | Пройдено | Упало | Пропущено |", "| --- | ---: | ---: | ---: |" ]
       + ($rows | map("| \(.name | cell | code) | \(.passed) | \(.failed) | \(.skipped) |"))
       + [""]
     end)
  + (if ($failed | length) > 0
     then ["### Упавшие тесты (\($failed | length))", ""] + ($failed | list) + [""]
     else [] end)
  + (if ($skipped | length) > 0
     then ["<details>", "<summary>Пропущенные тесты (\($skipped | length))</summary>", ""] + ($skipped | list) + ["", "</details>", ""]
     else [] end)
| join("\n")

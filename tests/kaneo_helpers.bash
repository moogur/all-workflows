#!/usr/bin/env bash
# Общие хелперы bats-тестов kaneo-flow/kaneo-deploy: заглушка curl, отвечающая по маршруту
# "<МЕТОД> <путь>", и запуск кода скриптов в рабочем каталоге с message.tmpl.

# kaneo_stub_setup — создаёт $TMP/{bin,resp,work}, заглушку curl и окружение запуска.
# Заглушка пишет "<МЕТОД> <путь>" в $CALLS, тело запроса — в $BODIES, ответ берёт из
# файла $RESP/<маршрут с / и пробелами, заменёнными на _>; нет файла — как сбой curl (код 22).
kaneo_stub_setup() {
  CALLS="$TMP/calls"
  BODIES="$TMP/bodies"
  RESP="$TMP/resp"
  WORK="$TMP/work"
  GITHUB_OUTPUT="$TMP/output"
  export CALLS BODIES RESP GITHUB_OUTPUT
  mkdir -p "$TMP/bin" "$RESP" "$WORK"
  : > "$CALLS"
  : > "$BODIES"
  : > "$GITHUB_OUTPUT"

  cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
args=("$@")
method=GET
data=''
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    -X) method="${args[i + 1]}" ;;
    -d) data="${args[i + 1]}" ;;
  esac
done
cat > /dev/null
route="$method ${args[${#args[@]} - 1]#https://kaneo.example}"
echo "$route" >> "$CALLS"
if [[ -n "$data" ]]; then
  echo "$data" >> "$BODIES"
fi
file="$RESP/$(tr '/ ' '__' <<< "$route")"
if [[ -f "$file" ]]; then
  cat "$file"
else
  exit 22
fi
STUB
  chmod +x "$TMP/bin/curl"
}

# kaneo_respond "<МЕТОД> <путь>" <ответ> — задаёт ответ заглушки на маршрут.
kaneo_respond() {
  printf '%s' "$2" > "$RESP/$(tr '/ ' '__' <<< "$1")"
}

# kaneo_task_json <статус> [id] [проект] — ответ GET task.
kaneo_task_json() {
  jq -n --arg status "$1" --arg id "${2:-tid1}" --arg project "${3:-pid1}" \
    '{id: $id, projectId: $project, workspaceId: "wid1", status: $status}'
}

# kaneo_run <код> — выполняет код в $WORK после source скрипта $KANEO_SCRIPT (по умолчанию
# kaneo_flow.sh) под bash -e, как шаг workflow; результат — в $output/$status.
kaneo_run() {
  run env PATH="$TMP/bin:$PATH" KANEO_URL='https://kaneo.example' KANEO_TOKEN='tok' \
    bash -e -c "cd '$WORK' && source '$ROOT/scripts/${KANEO_SCRIPT:-kaneo_flow.sh}' && $*"
}

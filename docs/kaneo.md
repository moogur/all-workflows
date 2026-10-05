# Интеграция с Kaneo

Workflow [`kaneo.yml`](../.github/workflows/kaneo.yml) синхронизирует положение задачи на доске [Kaneo](https://github.com/usekaneo/kaneo) (self-hosted) с этапами разработки в Git: коммит, открытие PR, мерж, деплой. Работает из CI по REST API, без GitHub App Kaneo. Код разложен по скриптам, которые workflow получает через `actions/checkout` этого репозитория (запиненного к версии вызванного workflow) и подключает через `source`; секреты и id они читают из переменных окружения:

- [`scripts/kaneo_flow.sh`](../scripts/kaneo_flow.sh) — подготовка данных задачи и переходы push/pr/merge;
- [`scripts/kaneo_deploy.sh`](../scripts/kaneo_deploy.sh) — переход deploy и запись версии в поле `App_version`;
- [`scripts/kaneo_requests.sh`](../scripts/kaneo_requests.sh) — запросы к API; [`scripts/kaneo_messages.sh`](../scripts/kaneo_messages.sh) — отчёт `message.tmpl`;
- [`scripts/kaneo_task_id.sh`](../scripts/kaneo_task_id.sh) — откуда берутся номер задачи и версия релиза; сам формат (заголовок коммита, теги, id Kaneo) — в [`lib/`](../lib/) (см. [conventions.md](conventions.md#форматы)).

← Назад к [README](../README.md) · [Справочник workflow'ов](workflows.md)

> Kaneo заменил Kanboard: вызов меняется целиком (`kanboard.yml` → `kaneo.yml`, секреты `KANEO_*`, вместо списка `kanboard_columns` — именованные статусы).

## Как это работает

1. Workflow выкачивает `all-workflows` через `actions/checkout` (ref = `github.job_workflow_sha`, т.е. версия вызванного workflow) и подключает скрипты прямо оттуда. Значения в файлы **не подставляются** (никаких `sed`): шаг передаёт их через `env:` — `KANEO_URL`, `KANEO_TOKEN` (секреты), входы `kaneo_status_*`, `KANEO_TASK_KEY`, `KANEO_TASK_ID`, `KANEO_PROJECT_ID`, `KANEO_WORKSPACE_ID`, `CURRENT_STATUS` (выходы шага «Set variables»). Причина — [security.md, п. 8](security.md#8-инъекция-через-номер-задачи-и-sed-в-исполняемый-файл-в-kanboardyml--исправлено).
2. Номер задачи (`GA-25`) извлекается через `scripts/kaneo_task_id.sh` (функция `commit_task_key` из [`lib/commit.sh`](../lib/commit.sh): первая строка текста, разбитая по `-`, `[`, `]` и `_`; принимается только значение вида `PREFIX-N`) из:
   - **сообщения коммита** — для `single_branch` (`kaneo_task_key_from_last_commit`);
   - **имени ветки** (`github.head_ref` / `GITHUB_REF_NAME`) — для остальных случаев (`kaneo_task_key_from_ref`).
   Нет номера — шаги push/pr/merge пишут строку в лог и пропускаются, job не падает. То же, если Kaneo не ответил валидными данными задачи (id, проект, пространство, статус проверяются `kaneo_id_valid`).
   Это согласуется с форматом веток и коммитов `[GA-123] ...` (см. [conventions.md](conventions.md)).
3. Задача ищется по номеру (`GET /api/task/by-ticket-id/GA-25`), её текущий статус (slug колонки) сравнивается с входами и по таблице ниже задача переносится (`PUT /api/task/status/<id>`).
4. Итог каждого шага пишется в файл `message.tmpl` и выводится в лог на финальном шаге.

## Входные параметры

| Параметр | Обяз. | Значения | Описание |
| --- | --- | --- | --- |
| `project_type` | да | `single_branch` \| `multi_branch` | Модель ветвления проекта |
| `event_type` | да | `push` \| `pr` \| `merge` \| `deploy` | Текущее событие пайплайна |
| `kaneo_status_in_progress` | да | slug колонки | Колонка «в работе» |
| `kaneo_status_review` | нет (`''`) | slug колонки | Колонка «на ревью» (нужна `multi_branch`) |
| `kaneo_status_merged` | нет (`''`) | slug колонки | Колонка «смёржено» (нужна `multi_branch`) |
| `kaneo_status_deploy` | нет (`''`) | slug колонки | Колонка «задеплоено» (нужна `multi_branch`) |

Если нужный событию статус не задан, шаг пишет строку в лог и пропускается — job не падает.

## Секреты

| Секрет | Назначение |
| --- | --- |
| `KANEO_HOST` | Базовый URL инстанса Kaneo (API — `<host>/api/...`) |
| `KANEO_TOKEN` | API-ключ Kaneo (`Authorization: Bearer`) |

Ключ принадлежит пользователю Kaneo: ему нужен доступ к рабочему пространству проекта (чтение задач и полей, обновление задач).

## Логика переходов

Колонки адресуются slug'ами из входов:

| Событие | Тип проекта | Условие | Действие |
| --- | --- | --- | --- |
| `push` | любой | задача не в `in_progress` и (для `multi_branch`) не в `review` | переместить в `in_progress` |
| `pr` | `multi_branch` | задача в `in_progress` | переместить в `review` |
| `merge` | `multi_branch` | задача в `review` | переместить в `merged` |
| `deploy` | `multi_branch` | задача из диапазона между двумя последними тегами в `merged` | переместить в `deploy` и записать версию в поле `App_version` |

Если условие не выполнено, в отчёт пишется `SKIPPED`. На `push` переносится задача из **любой** другой колонки (список «рабочих» колонок больше не нужен).

При деплое workflow собирает номера задач из коммитов между двумя последними git-тегами (или из всех коммитов, если тег один; `kaneo_deploy_tags`/`kaneo_deploy_task_keys` в `scripts/kaneo_task_id.sh`, последние теги — по дате создания, [`lib/tags.sh`](../lib/tags.sh)), убирает дубликаты и для каждой задачи дописывает версию текущего релиза (снятие префикса `v` — [`lib/version.sh`](../lib/version.sh)) в пользовательское поле `App_version`:

- поле пустое — записывается версия; версия уже есть в списке (сравнение по целому элементу через запятую) — запись пропускается; иначе дописывается `, <версия>`;
- в Kaneo поле нужно завести в проекте вручную (тип `text`); без него шаг пишет строку в лог и идёт дальше;
- Kaneo отдаёт значения только заполненных полей (`GET /api/custom-field/task/<id>`), поэтому id поля берётся из определений проекта (`GET /api/custom-field/project/<id>`, один запрос на проект за прогон); запись — `PUT /api/custom-field/value`;
- не удалось прочитать текущее значение — запись не отправляется (чтобы не затереть уже стоящие версии), в отчёте `ERROR`.

## Запросы (`kaneo_requests.sh`)

Bash-библиотека функций поверх REST API Kaneo. Переменные `private_*` читаются из окружения (`KANEO_*`, см. выше) при `source`. Тело запросов строит `jq --arg`; id (задача, проект, поле) проверяет `kaneo_id_valid` ([`lib/kaneo.sh`](../lib/kaneo.sh): буквы, цифры, `_`, `-`), номер задачи — `commit_task_key_valid`: при невалидном значении запрос не строится и не уходит (код 1, сообщение в stderr без самого значения).

| Функция | Запрос |
| --- | --- |
| `request_get_task` | `GET /api/task/by-ticket-id/<номер>` |
| `request_move_task` | `PUT /api/task/status/<id>`, тело `{"status": "<slug>"}` |
| `request_get_project_fields` | `GET /api/custom-field/project/<id проекта>` |
| `request_get_task_fields` | `GET /api/custom-field/task/<id задачи>` |
| `request_set_field_value` | `PUT /api/custom-field/value`, тело `{"taskId","fieldId","value"}` |

Все они ходят через общую обёртку `execute_request`:

```bash
printf 'header = "Authorization: Bearer %s"\n' "$(curl_config_escape "$private_token")" | curl -fsS --config - \
  --connect-timeout 10 --max-time 30 \
  --retry 3 --retry-delay 5 --retry-connrefused --retry-all-errors \
  -X "$method" [-H 'Content-Type: application/json' -d "$data"] "$private_url$path"
```

Токен передаётся конфигом через stdin (`--config -`), а не аргументом: так его нет в списке процессов раннера и в файле на диске. `curl_config_escape` экранирует `\`, `"` и управляющие символы по правилам конфига curl ([security.md](security.md#2-передача-токена-в-docker-login--исправлено)).

Kaneo живёт на самохостинге и периодически может быть недоступен с раннеров GitHub. Что это меняет:

| Без защиты | С обёрткой |
| --- | --- |
| Запрос висел на TCP-коннекте до системного таймаута | `--connect-timeout 10`, `--max-time 30` |
| Короткая сетевая икота роняла шаг | три повтора с паузой 5 с (`--retry-connrefused`, `--retry-all-errors`) |
| Любой HTTP-5xx выглядел успехом: без `-f` curl возвращал 0 и пустое тело | `-f` — ненулевой код и строка `Kaneo request failed: <метод> <путь>` в stderr |

> Шаг workflow при этом **не падает**: недоступность трекера не блокирует деплой, но видна в логе и в отчёте (`ERROR`).

## Отчёт (`kaneo_messages.sh`)

Запись в `message.tmpl`, который выводится на шаге «Show result»: `save_message_in_file` (итог переноса), `save_message_in_file_for_add_app_version`, `save_message_in_file_for_get_task_error`, `save_skip_message_in_file` (перенос не нужен) и вспомогательные `save_header_in_file`, `save_task_link_in_file`, `save_separator_in_file`, `save_raw_message_in_file`.

Ответ API недоверенный, поэтому в отчёт он попадает очищенным: остаются буквы, цифры и пробел с `._,:{}"/-`, не больше 300 символов (иначе строка `::команда` из ответа стала бы workflow-командой в логе).

Ссылка на задачу — полный путь `<host>/dashboard/workspace/<workspaceId>/project/<projectId>/task/<taskId>`: короткая форма `<host>/<slug пространства>/task/GA-25` требует slug пространства, которого нет в ответе API.

## Пример вызова

```yaml
jobs:
  kaneo:
    uses: moogur/all-workflows/.github/workflows/kaneo.yml@master
    secrets: inherit
    with:
      project_type: 'multi_branch'
      event_type: 'push'
      kaneo_status_in_progress: 'in-progress'
      kaneo_status_review: 'in-review'
      kaneo_status_merged: 'merged'
      kaneo_status_deploy: 'deployed'
```

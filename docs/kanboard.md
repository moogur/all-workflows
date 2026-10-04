# Интеграция с Kanboard

Workflow [`kanboard.yml`](../.github/workflows/kanboard.yml) синхронизирует положение задачи на канбан-доске [Kanboard](https://kanboard.org/) с этапами разработки в Git: коммит, открытие PR, мерж, деплой. Вся работа с API вынесена в bash-библиотеку [`scripts/kanboard_requests.sh`](../scripts/kanboard_requests.sh), которую workflow получает через `actions/checkout` этого репозитория (запиненного к версии вызванного workflow) и подключает через `source`; секреты и id она читает из переменных окружения. Извлечение `task_id`/версии релиза из git — в [`scripts/kanboard_task_id.sh`](../scripts/kanboard_task_id.sh), той же копии репозитория; сам формат (заголовок коммита, теги) — в [`lib/`](../lib/) (см. [conventions.md](conventions.md#форматы)).

← Назад к [README](../README.md) · [Справочник workflow'ов](workflows.md)

## Как это работает

1. Workflow выкачивает `all-workflows` через `actions/checkout` (ref = `github.job_workflow_sha`, т.е. версия вызванного workflow) и подключает `kanboard_requests.sh` прямо оттуда. Значения в файл **не подставляются** (никаких `sed`): шаг передаёт их через `env:` — `KANBOARD_URL`, `KANBOARD_USER`, `KANBOARD_TOKEN` (секреты), `KANBOARD_TASK_ID`, `KANBOARD_PROJECT_ID`, `KANBOARD_SWIMLANE_ID` (выходы шага «Set variables»). Причина — [security.md, п. 8](security.md#8-инъекция-через-номер-задачи-и-sed-в-исполняемый-файл-в-kanboardyml--исправлено).
2. Номер задачи (`task_id`) извлекается через `scripts/kanboard_task_id.sh` (функция `commit_task_id` из [`lib/commit.sh`](../lib/commit.sh) — «второе слово» после разбиения по `-`, `]` и `_`, принимается только если оно целиком из цифр, `commit_task_id_valid`) из:
   - **сообщения коммита** — для `single_branch` (`kanboard_task_id_from_last_commit`);
   - **имени ветки** (`github.head_ref` / `GITHUB_REF_NAME`) — для PR/merge/deploy (`kanboard_task_id_from_ref`).
   Нет числового номера — шаги push/pr/merge пишут строку в лог и пропускаются, job не падает. То же для данных задачи, если Kanboard не ответил числовыми колонкой/проектом/дорожкой.
   Это согласуется с форматом веток и коммитов `[GA-123] ...` (см. [conventions.md](conventions.md)).
3. По текущей колонке задачи и типу события скрипт перемещает задачу методом Kanboard `moveTaskPosition`.
4. Итог каждого шага пишется в файл `message.tmpl` и выводится в лог на финальном шаге.

## Входные параметры

| Параметр | Обяз. | Значения | Описание |
| --- | --- | --- | --- |
| `kanboard_columns` | да | строка | Список id колонок слева направо через запятую |
| `project_type` | да | `single_branch` \| `multi_branch` | Модель ветвления проекта |
| `event_type` | да | `push` \| `pr` \| `merge` \| `deploy` | Текущее событие пайплайна |

## Секреты

| Секрет | Назначение |
| --- | --- |
| `KANBOARD_HOST` | Базовый URL инстанса Kanboard (используется как `<host>/jsonrpc.php`) |
| `KANBOARD_USER` | Логин для JSON-RPC API |
| `KANBOARD_TOKEN` | Токен/пароль для JSON-RPC API |

## Логика переходов

Колонки адресуются по индексу в массиве `kanboard_columns` (нумерация с нуля):

| Событие | Тип проекта | Условие | Действие |
| --- | --- | --- | --- |
| `push` | любой | задача в одной из «рабочих» колонок (не in-progress) | переместить в `[3]` — *in progress* |
| `pr` | `multi_branch` | задача в `[3]` | переместить в `[4]` — *in review* |
| `merge` | `multi_branch` | задача в `[4]` | переместить в `[5]` — *merged* |
| `deploy` | `multi_branch` | задачи из диапазона между двумя последними тегами в `[5]` | переместить в `[6]` — *deploy* и записать версию в метаданные задачи |

При деплое workflow собирает id задач из коммитов между двумя последними git-тегами (или из всех коммитов, если тег один; `kanboard_deploy_tags`/`kanboard_deploy_task_ids` в `scripts/kanboard_task_id.sh`, последние теги — по дате создания, [`lib/tags.sh`](../lib/tags.sh)), убирает дубликаты и для каждой задачи проставляет/дополняет метаданные `App_version` версией текущего релиза (снятие префикса `v` — [`lib/version.sh`](../lib/version.sh)).

## Скрипт `kanboard_requests.sh`

Bash-библиотека функций поверх [Kanboard JSON-RPC API](https://docs.kanboard.org/v1/api/). Переменные `private_*` читаются из окружения (`KANBOARD_*`, см. выше) при `source`. Генераторы собирают JSON через `jq --arg`, а числовые поля (задача, проект, колонка, дорожка, позиция) проверяет `commit_task_id_valid`: при нечисловом значении запрос не строится и не уходит (код 1, сообщение в stderr без самого значения).

**Генераторы тела запроса** (формируют JSON-RPC payload):

- `generate_post_data_for_move_task` — `moveTaskPosition`;
- `generate_post_data_for_get_info_task` — `getTask`;
- `generate_post_data_for_get_metadata_task` — `getTaskMetadataByName` (ключ `App_version`);
- `generate_post_data_for_update_task_app_version` — `saveTaskMetadata`.

**Выполнение запросов** (через `curl` на `<host>/jsonrpc.php`):

- `request_for_move_task` — переместить задачу;
- `request_for_get_info_task` — получить данные задачи (колонка, проект, swimlane);
- `request_for_get_metadata_task` — получить метаданные;
- `request_for_update_task_app_version` — обновить версию приложения в метаданных.

Все четыре ходят через общую обёртку `execute_request`:

```bash
curl -fsS --connect-timeout 10 --max-time 30 \
  --retry 3 --retry-delay 5 --retry-connrefused --retry-all-errors \
  -u "$private_auth_data" -d "$data" "$private_url/jsonrpc.php"
```

Kanboard живёт на самохостинге и периодически недоступен с раннеров GitHub. Что это меняет:

| Было | Стало |
| --- | --- |
| Запрос висел на TCP-коннекте до системного таймаута (наблюдали 135 с) | `--connect-timeout 10`, `--max-time 30` |
| Короткая сетевая икота роняла шаг | три повтора с паузой 5 с (`--retry-connrefused`, `--retry-all-errors`) |
| Любой HTTP-5xx выглядел успехом: без `-f` curl возвращал 0 и пустое тело | `-f` — ненулевой код и строка `Kanboard request failed: <url>` в stderr |

> Шаг workflow при этом **не падает**: вызывающий код не проверяет код возврата, поэтому недоступность трекера по-прежнему не блокирует деплой — но теперь она видна в логе, а не притворяется успехом. Если захочется, чтобы деплой явно не зависел от Kanboard, это отдельная правка (`continue-on-error` на job).

**Формирование отчёта** (запись в `message.tmpl`):

- `save_message_in_file`, `save_message_in_file_for_add_app_version`, `save_message_in_file_for_deploy_get_task_info_error` — человекочитаемые сообщения об успехе/ошибке;
- вспомогательные: `save_message_header_in_file`, `save_task_link_in_file`, `save_separator_in_file`, `save_raw_message_in_file`.

## Пример вызова

```yaml
jobs:
  kanboard:
    uses: moogur/all-workflows/.github/workflows/kanboard.yml@master
    secrets: inherit
    with:
      kanboard_columns: '1,2,3,4,5,6,7'
      project_type: 'multi_branch'
      event_type: 'push'
```

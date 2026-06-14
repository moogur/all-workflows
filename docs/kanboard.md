# Интеграция с Kanboard

Workflow [`kanboard.yml`](../.github/workflows/kanboard.yml) синхронизирует положение задачи на канбан-доске [Kanboard](https://kanboard.org/) с этапами разработки в Git: коммит, открытие PR, мерж, деплой. Вся работа с API вынесена в bash-библиотеку [`scripts/kanboard_requests.sh`](../scripts/kanboard_requests.sh), которую workflow получает через `actions/checkout` этого репозитория (запиненного к версии вызванного workflow) и подставляет в неё секреты.

← Назад к [README](../README.md) · [Справочник workflow'ов](workflows.md)

## Как это работает

1. Workflow выкачивает `kanboard_requests.sh` через `actions/checkout` репозитория `all-workflows` (ref = `github.job_workflow_sha`, т.е. версия вызванного workflow) и через `sed` подставляет в него хост, учётные данные и id задачи.
2. Номер задачи (`task_id`) извлекается из:
   - **сообщения коммита** — для `single_branch` (второе «слово» после разбиения по `-` и `]`);
   - **имени ветки** (`github.head_ref` / `GITHUB_REF_NAME`) — для PR/merge/deploy.
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

При деплое workflow собирает id задач из коммитов между двумя последними git-тегами (или из всех коммитов, если тег один), убирает дубликаты и для каждой задачи проставляет/дополняет метаданные `App_version` версией текущего релиза.

## Скрипт `kanboard_requests.sh`

Bash-библиотека функций поверх [Kanboard JSON-RPC API](https://docs.kanboard.org/v1/api/). Переменные `private_*` заполняются workflow'ом через `sed` перед использованием.

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

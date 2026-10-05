# Интеграция с Kaneo

Workflow [`kaneo.yml`](../.github/workflows/kaneo.yml) синхронизирует положение задачи на доске [Kaneo](https://github.com/usekaneo/kaneo) (self-hosted) с этапами разработки в Git: коммит, открытие PR, мерж, деплой. Работает из CI по REST API, без GitHub App Kaneo. Поведение задаёт **схема** — декларативный конечный автомат в [`scripts/kaneo/schemes.json`](../scripts/kaneo/schemes.json): потребитель выбирает схему по имени и передаёт событие. Код лежит в [`scripts/kaneo/`](../scripts/kaneo/); workflow получает его через `actions/checkout` этого репозитория (запиненного к версии вызванного workflow) и подключает через `source`; секреты и входы скрипты читают из переменных окружения:

- [`engine.sh`](../scripts/kaneo/engine.sh) — точка входа `kaneo_run`: читает схему, собирает номера задач, запускает обработку;
- [`task.sh`](../scripts/kaneo/task.sh) — одна задача: данные из Kaneo, выбор правила по статусу, перенос;
- [`fields.sh`](../scripts/kaneo/fields.sh) — запись пользовательских полей после переноса; функции значений — в [`fields/`](../scripts/kaneo/fields/);
- [`requests.sh`](../scripts/kaneo/requests.sh) — запросы к API; [`messages.sh`](../scripts/kaneo/messages.sh) — отчёт `message.tmpl`;
- [`task_key.sh`](../scripts/kaneo/task_key.sh) — откуда берётся номер задачи; сам формат (заголовок коммита, теги, id Kaneo) — в [`lib/`](../lib/) (см. [conventions.md](conventions.md#форматы)).

← Назад к [README](../README.md) · [Справочник workflow'ов](workflows.md)

> Kaneo заменил Kanboard. Вместо `project_type` и `kaneo_status_*` вход теперь один: имя схемы `kaneo_scheme` (колонки доски описаны в самой схеме).

## Как это работает

Один шаг workflow подключает `engine.sh` и вызывает `kaneo_run`. Значения в файлы **не подставляются** (никаких `sed`) и между шагами через `$GITHUB_OUTPUT` не передаются: шаг получает через `env:` только `KANEO_URL`, `KANEO_TOKEN` (секреты), `KANEO_SCHEME`, `EVENT_TYPE`, `HEAD_REF`. Причина — [security.md, п. 8](security.md#8-инъекция-через-номер-задачи-и-sed-в-исполняемый-файл-в-kanboardyml--исправлено).

1. Схема и событие ищутся в `schemes.json`. Нет схемы или событие в ней не определено — строка в лог, шаг завершается успешно: Kaneo никогда не блокирует пайплайн.
2. Номера задач (`GA-25`; `commit_task_key` из [`lib/commit.sh`](../lib/commit.sh): первая строка текста, разбитая по `-`, `[`, `]` и `_`; принимается только значение вида `PREFIX-N`) берутся по `task_key` события из схемы:
   - `commit` — заголовок последнего коммита;
   - `branch` — имя ветки PR (`github.head_ref`) для `pr`/`merge` и имя ветки/тега запуска (`GITHUB_REF_NAME`) для остальных событий;
   - `tags` — заголовки коммитов между двумя последними git-тегами (вся история, если тег один; `kaneo_deploy_tags`/`kaneo_deploy_task_keys`, теги — по дате создания, [`lib/tags.sh`](../lib/tags.sh)), без дублей.
   Любое событие может использовать любой источник. Нет номера (или тегов) — строка в лог, шаг пропускается.
3. Для каждой задачи: `GET /api/task/by-ticket-id/GA-25`; если текущий статус (slug колонки) входит в `from` первого подходящего правила события — `PUT /api/task/status/<id>` в `to`. Иначе в отчёт пишется `SKIPPED`, задача и её поля не трогаются. Данные задачи, не прошедшие проверку id (задача, проект, пространство), задачу пропускают с `ERROR` в отчёте.
4. Поля правила заполняются **только после успешного переноса** (см. ниже). Сбой одного поля не останавливает остальные поля и задачи.
5. Итог каждой задачи пишется в `message.tmpl` и выводится в лог на финальном шаге.

Статусы сравниваются с доверенным файлом схем, а не с ASCII-шаблоном: slug колонки может содержать кириллицу (его строит `toSlug` Kaneo). Статус из ответа API в лог не печатается; id, идущие в URL, проверяет `kaneo_id_valid`.

## Входные параметры

| Параметр | Обяз. | Значения | Описание |
| --- | --- | --- | --- |
| `kaneo_scheme` | да | имя схемы из `schemes.json` (`single` \| `single_ready` \| `multi`) | Схема переходов |
| `event_type` | да | `push` \| `pr` \| `merge` \| `deploy` | Текущее событие пайплайна |

## Секреты

| Секрет | Назначение |
| --- | --- |
| `KANEO_HOST` | Базовый URL инстанса Kaneo (API — `<host>/api/...`) |
| `KANEO_TOKEN` | API-ключ Kaneo (`Authorization: Bearer`) |

Ключ принадлежит пользователю Kaneo: ему нужен доступ к рабочему пространству проекта (чтение задач и полей, обновление задач).

## Файл схем

Схема — объект, ключи которого — события (`push`, `pr`, `merge`, `deploy`). Событие всегда объект с `task_key` и массивом `rules`; другой формы нет.

```json
{
  "<имя схемы>": {
    "<push | pr | merge | deploy>": {
      "task_key": "commit | branch | tags",
      "rules": [
        { "from": ["slug", "..."], "to": "slug", "fields": { "<поле Kaneo>": "<функция>" } }
      ]
    }
  }
}
```

- `task_key` — источник номеров задач события (см. «Как это работает», п. 2);
- `rules` — непустой список правил. Правила проверяются по порядку: срабатывает первое, чей `from` содержит текущий статус задачи (перенос в его `to`, затем его собственные `fields`); ни одно не подошло — `SKIPPED`;
- `from` — непустой список slug'ов колонок; `to` — целевая колонка;
- `fields` (необязательно) — «имя пользовательского поля в проекте Kaneo -> имя функции значения»;
- slug'и должны совпадать с колонками реальной доски; несовпадение проявится ошибкой при прогоне, а не при проверке схемы.

Пример события с двумя правилами:

```json
"push": {
  "task_key": "branch",
  "rules": [
    { "from": ["backlog", "todo"], "to": "in-progress" },
    { "from": ["hold"], "to": "review", "fields": { "Sprint": "current_sprint" } }
  ]
}
```

### Схемы

| Схема | Событие | `task_key` | `from` | `to` | Поля |
| --- | --- | --- | --- | --- | --- |
| `single` | `push` | `commit` | `backlog`, `todo`, `hold` | `in-progress` | — |
| `single` | `deploy` | `tags` | `in-progress` | `done` | `Version` |
| `single_ready` | `push` | `commit` | `backlog`, `todo`, `hold` | `in-progress` | — |
| `single_ready` | `deploy` | `tags` | `in-progress`, `ready` | `done` | `Version` |
| `multi` | `push` | `branch` | `backlog`, `todo`, `hold` | `in-progress` | — |
| `multi` | `pr` | `branch` | `in-progress` | `review` | — |
| `multi` | `merge` | `branch` | `review` | `merged` | — |
| `multi` | `deploy` | `tags` | `merged` | `done` | `Version` |

### Как добавить схему

1. Добавить в `schemes.json` объект схемы: события с `task_key` и `rules` (формат выше), slug'и — как на доске. Новое событие — новый ключ внутри схемы (из `push`, `pr`, `merge`, `deploy`).
2. Если нужны поля — добавить функцию (ниже).
3. Тест-страж [`tests/kaneo-schemes.bats`](../tests/kaneo-schemes.bats) проверит структуру, допустимые события и `task_key`, непустые `rules`, `from`/`to` и то, что каждая функция из `fields` существует.

## Поля и функции значений

Поле заполняется после успешного переноса, для каждой пары `"поле": "функция"` переданного правила:

1. имя функции должно подходить под `^[a-z_][a-z0-9_]*$` ([`lib/kaneo.sh`](../lib/kaneo.sh), `kaneo_func_name_valid`), иначе ошибка в лог и поле пропущено;
2. функция в shell называется `kaneo_field_<функция>` (префикс не даёт затенить команды вроде `date`). Если она не определена, подключается `scripts/kaneo/fields/<функция>.sh`; нет файла или функции в нём — ошибка, поле пропущено. Одна функция может обслуживать несколько полей и подключается один раз;
3. поле ищется по имени среди определений проекта задачи (`GET /api/custom-field/project/<id>`, один запрос на проект за прогон); нет такого поля — строка в лог, поле пропущено;
4. читается текущее значение (`GET /api/custom-field/task/<id>`; нет значения — пустая строка). Не удалось прочитать — ошибка, запись не отправляется (чтобы не затереть стоящее);
5. вызывается `kaneo_field_<функция>` **без аргументов**; контекст — в переменных окружения (таблица ниже), новое значение — в stdout;
6. значение равно текущему — запись не отправляется; иначе `PUT /api/custom-field/value`.

| Переменная | Значение |
| --- | --- |
| `KANEO_FIELD_VALUE` | текущее значение поля (пусто, если нет) |
| `KANEO_TASK_KEY` | номер задачи (`GA-25`) |
| `KANEO_TASK_STATUS` | статус задачи до переноса |
| `KANEO_EVENT` | событие (`push`/`pr`/`merge`/`deploy`) |

Контракт функции: stdout — новое значение целиком (заменить, дописать или оставить как есть решает функция); код возврата не 0 — ошибка в лог и отчёт, значение не пишется, остальные поля продолжаются. Движок не использует `eval`: имя функции проверяется по регулярному выражению и вызывается как обычная команда.

### Как добавить функцию значения

1. Создать `scripts/kaneo/fields/<имя>.sh`, имя — строчные латинские буквы, цифры, `_`.
2. Определить в нём `kaneo_field_<имя>`; общие форматы брать из `lib/` (версии — [`lib/version.sh`](../lib/version.sh), теги — [`lib/tags.sh`](../lib/tags.sh)), не переписывать их.
3. Указать `<имя>` в `fields` нужного перехода в `schemes.json`.
4. Покрыть тестом (пример — [`tests/kaneo-field-release-version.bats`](../tests/kaneo-field-release-version.bats)).

### `release_version`

Файл [`fields/release_version.sh`](../scripts/kaneo/fields/release_version.sh): берёт версию последнего тега (по дате создания, без префикса `v`) и дописывает её в значение через запятую. Пустое поле — только версия; версия уже есть в списке (сравнение по целому элементу после обрезки пробелов: `1.2` не входит в `1.2.3`) — значение без изменений; нет тегов — сообщение в stderr и код 1. В Kaneo поле `Version` нужно завести в проекте вручную (тип `text`).

## Запросы (`requests.sh`)

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

## Отчёт (`messages.sh`)

Запись в `message.tmpl`, который выводится на шаге «Show result»: `save_message_in_file` (итог переноса), `save_message_in_file_for_field` (итог записи поля), `save_message_in_file_for_get_task_error`, `save_skip_message_in_file` (перенос не нужен) и вспомогательные `save_header_in_file`, `save_task_link_in_file`, `save_separator_in_file`, `save_raw_message_in_file`.

Ответ API недоверенный, поэтому в отчёт он попадает очищенным: остаются буквы, цифры и пробел с `._,:{}"/-`, не больше 300 символов (иначе строка `::команда` из ответа стала бы workflow-командой в логе).

Ссылка на задачу — полный путь `<host>/dashboard/workspace/<workspaceId>/project/<projectId>/task/<taskId>`: короткая форма `<host>/<slug пространства>/task/GA-25` требует slug пространства, которого нет в ответе API.

## Пример вызова

```yaml
jobs:
  kaneo:
    uses: moogur/all-workflows/.github/workflows/kaneo.yml@master
    secrets: inherit
    with:
      kaneo_scheme: 'multi'
      event_type: 'push'
```

Пути Kaneo, которые используются (их нужно пропустить через haproxy): `/api/task/by-ticket-id/`, `/api/task/status/`, `/api/custom-field/`.

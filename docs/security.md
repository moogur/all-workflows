# Безопасность

Замечания по безопасности переиспользуемых workflow'ов. Это справочный материал «для сведения» — критичных уязвимостей нет, но при расширении использования стоит держать пункты в голове.

← Назад к [README](../README.md)

## 1. Недоверенный код из Pull Request

[pr_annotation.yml](../.github/workflows/pr_annotation.yml) — единственный workflow, который исполняет код из Pull Request: `npm ci` запускает lifecycle-скрипты (`postinstall` и т. п.), а шаг покрытия — тесты проекта. Форк здесь ни при чём: workflow всегда выполняется **в базовом репозитории**, на его раннере и в его окружении, а из форка приходит только код.

**Что видит такой запуск.** Меньше, чем кажется. На событие `pull_request` из форка GitHub не передаёт секреты: `secrets.*` пустые, `secrets: inherit` ничего не наследует, а `GITHUB_TOKEN` принудительно понижается до read-only независимо от блока `permissions` — то есть `pull-requests: write` и `checks: write` у `pr_annotation` не действуют и аннотации всё равно не публикуются. Для публичного репозитория первый запуск от нового контрибьютора вдобавок требует ручного подтверждения.

**Что оставалось доступным.** Файл `.npmrc`, который создаёт [`npm-auth`](actions.md#npm-auth) из `GITHUB_TOKEN`. На публичном репозитории read-only токен бесполезен, на приватном им можно вычитать исходники и пакеты приватного scope.

**Закрыто двумя шагами:**
- job не стартует на PR из форка — `if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`; на форковом PR он в любом случае не мог выполнить свою работу из-за read-only токена;
- `.npmrc` удаляется сразу после `npm ci`, до запуска тестов, а стороннему action передан `skip-step: install`, чтобы он не пытался ставить зависимости уже без авторизации.

Оба правила закреплены guard-тестом [tests/pr-annotation.bats](../tests/pr-annotation.bats).

**Настоящая граница доверия — PR из ветки самого репозитория.** Такие запуски получают секреты полностью, и защищает их только то, что пушить ветки может лишь обладатель write-доступа.

> **`pull_request_target` использовать нельзя.** Он выполняется в контексте базовой ветки **с полным набором секретов и write-токеном**; связка с `actions/checkout` по `github.event.pull_request.head.sha` и последующей установкой зависимостей отдаёт все секреты автору PR. Если отчёт по форковым PR когда-нибудь понадобится — сборка на `pull_request` без секретов, публикация результата отдельным workflow по `workflow_run`.

> Права `GITHUB_TOKEN` заданы явно в каждом workflow (таблица — в [conventions.md](conventions.md#права-github_token)); для `pr_annotation` это `contents: read`, `packages: read`, `pull-requests: write`, `checks: write`. Набор прав не ограничивает доступ к секретам репозитория — только то, что может сам токен.

## 2. Передача токена в `docker login` — исправлено

Раньше токен уходил аргументом командной строки (`docker login ... -p <token>`) и мог попасть в список процессов раннера. Теперь логин выполняет action [`docker-image`](actions.md#docker-image) через `--password-stdin`.

**Осталось на будущее:** [`docker/login-action`](https://github.com/docker/login-action) при переезде на `ghcr.io` (см. [modernization.md](modernization.md)).

**Тот же принцип для `curl`.** `execute_request` в интеграции с Kanboard раньше передавал `curl -u user:token` аргументом — пара была видна в списке процессов. Kanboard заменён Kaneo; теперь [`execute_request` в `requests.sh`](../scripts/kaneo/requests.sh) держит тот же приём: `header = "Authorization: Bearer …"` уходит в `curl --config -` через stdin (builtin `printf` в pipe: here-doc в старом bash создаёт временный файл), так что секрета нет ни в argv, ни на диске. `\`, `"`, перевод строки, `\r` и табуляция экранируются по правилам конфига curl (`curl_config_escape`), поэтому токен с кавычкой не ломает строку и не может добавить свою директиву. Остальные секреты идут через `env:` (`GH_TOKEN` для `gh`, `NODE_AUTH_TOKEN` для `.npmrc`); других мест, где секрет передавался бы аргументом процесса, нет. Тесты — [kaneo-requests.bats](../tests/kaneo-requests.bats).

## 3. Загрузка ресурсов в рантайме с `master`

Dockerfile'ы и composite actions подтягиваются по ссылке на ветку `master`. Любое изменение в `master` мгновенно влияет на всех потребителей, а версия вызванного workflow не привязана к версии скачиваемого ресурса.

**Риск:** компрометация или ошибочный коммит в `master` немедленно распространяется на все пайплайны (supply-chain).

**Рекомендация:** пинить ресурсы и сторонние actions к тегу или SHA. Подробнее — в [modernization.md](modernization.md).

> Закрыто для собственного CI: [ci.yml](../.github/workflows/ci.yml) больше не исполняет `bash <(curl ... /main/scripts/download-actionlint.bash)`. Релиз actionlint скачивается по фиксированной версии и сверяется с записанным рядом `sha256`, так что компрометация ветки `main` стороннего репозитория ничего не даёт.

> Частично закрыто: [kaneo.yml](../.github/workflows/kaneo.yml) (раньше kanboard.yml) берёт скрипты через `actions/checkout`, запиненный к `github.job_workflow_sha`, а Dockerfile'ы [`docker-image`](actions.md#docker-image) копирует из копии репозитория рядом с экшеном — обе ссылки на `master` в рантайме ушли. Осталась ссылка `@master` в самих `uses:`.

## 4. Пин сторонних actions

Сторонние actions пинятся по тегам (`@v7`, `@v2`); архивные release-actions по `@master` / `@main` больше не используются.

**Рекомендация:** для повышения уровня безопасности пинить сторонние actions по полному SHA коммита; как минимум — не использовать `@master`/`@main` у сторонних зависимостей.

## 5. Инъекция через `github.head_ref` в `kanboard.yml` — исправлено

Раньше `${{ github.head_ref }}` подставлялся прямо в тело inline-скрипта (`kanboard.yml`, заменён [kaneo.yml](../.github/workflows/kaneo.yml), шаг «Set variables»). Имя ветки задаёт автор PR, поэтому ветка вида `GA-1'; <команда>; '` выполняла произвольный код на раннере.

Теперь значение приходит переменной окружения и берётся в кавычки:

```yaml
env:
  HEAD_REF: ${{ github.head_ref }}
run: |
  task_id=`echo "$HEAD_REF" | ...`
```

Вместе с этим из CI и `Makefile` снят `-ignore 'is potentially untrusted'` — проверка actionlint проходит без него ([testing.md](testing.md)).

## 6. `.npmrc` с токеном в слое сборки

[`deploy_backend.dockerfile`](../dockerfiles/deploy_backend.dockerfile) копирует `.npmrc` внутрь образа (`COPY package.json package-lock.json .npmrc ./`), а файл содержит `_authToken`. В **финальный** образ токен не попадает — сборка многоступенчатая, наружу копируется только `dist`, — но он остаётся в слоях builder-стадии и в кэше сборки раннера.

**Рекомендация:** пробрасывать токен секрет-маунтом BuildKit (`RUN --mount=type=secret,id=npmrc ...`) либо удалять `.npmrc` тем же слоем, что и установка (`RUN npm ci && rm -f .npmrc`). Для `full_deploy.dockerfile` то же самое с `.npmrc` в `frontend/`.

## 7. Секреты, используемые workflow'ами

Полный перечень секретов и их назначение — в [conventions.md](conventions.md#секреты). Передавайте их через `secrets: inherit` либо явным списком и не логируйте значения.

## 8. Инъекция через номер задачи и `sed` в исполняемый файл в `kanboard.yml` — исправлено

Раньше шаг «Set variables» (в `kanboard.yml`, заменён `kaneo.yml`) брал `task_id` из заголовка последнего коммита (`single_branch`) или из имени ветки и подставлял его командой `sed -i "s|private_task_id=|private_task_id=$task_id|" ./requests.sh`; затем `. ./requests.sh` исполнял файл. Значение никто не проверял, поэтому заголовок вида `[GA-$(curl${IFS}...)] ...` превращался в строку `private_task_id=$(curl ...)` и выполнялся на раннере — когда `KANBOARD_USER`/`KANBOARD_TOKEN` уже были вписаны в тот же файл, а секреты — в окружении. Заголовок коммита может задать любой, у кого есть право push. Тот же приём (`sed` в исполняемый файл) использовался для `KANBOARD_HOST`, пары `user:token`, а также `project_id` и `swimlane_id` из ответа Kanboard API.

Исправлено двумя слоями (после замены Kanboard на Kaneo те же свойства держит [kaneo.yml](../.github/workflows/kaneo.yml)):
- **Валидация.** Формат номера задачи (`^[A-Z][A-Z0-9]*-[0-9]+$`) живёт только в [`lib/commit.sh`](../lib/commit.sh): `commit_task_key_valid` и `commit_task_key`, которая отдаёт номер только если он валиден, иначе пусто (раньше — числовой `commit_task_id_valid`/`commit_task_id`, удалены). Формат id Kaneo (`^[A-Za-z0-9_-]+$`) — только в [`lib/kaneo.sh`](../lib/kaneo.sh). Её используют все пути — push/pr/merge и deploy. Без валидного номера шаги пишут строку в лог (само значение не печатается) и пропускаются без ошибки: Kaneo не блокирует пайплайн.
- **Нет подстановки в файл.** Скрипты [`scripts/kaneo/**/*.sh`](../scripts/) подключаются прямо из чекаута `all-workflows` (копия и все `sed -i` удалены) и читают `KANEO_URL`, `KANEO_TOKEN`, `KANEO_SCHEME`, `EVENT_TYPE`, `HEAD_REF` из окружения. Секреты и входы приходят в шаг через `env:`; данные задачи между шагами больше не передаются (один шаг, `GITHUB_OUTPUT` не используется), а id из ответа API перед использованием в URL проверяет `kaneo_id_valid`. Статус колонки из ответа только сравнивается со схемой и в лог не печатается. Имя функции поля из схемы проверяется `kaneo_func_name_valid` и вызывается как команда, `eval` нет. Тело запроса строит `jq --arg`, id проверяются до сборки URL; при небезопасном значении запрос не уходит. Ответ API попадает в отчёт `message.tmpl` только очищенным и усечённым до 300 символов — строка `::команда` из ответа не станет workflow-командой. Входы `inputs.*` тоже переданы через `env:`, в `run:` нет `${{ }}`.

Закреплено тестами [kaneo-workflow.bats](../tests/kaneo-workflow.bats) (нет `sed`/копии, секреты только в `env:`), [lib-commit.bats](../tests/lib-commit.bats), [lib-kaneo.bats](../tests/lib-kaneo.bats), [kaneo-task-id.bats](../tests/kaneo-task-id.bats), [kaneo.bats](../tests/kaneo.bats), [kaneo-requests.bats](../tests/kaneo-requests.bats), [kaneo-flow.bats](../tests/kaneo-flow.bats), [kaneo-messages.bats](../tests/kaneo-messages.bats) (вредоносные заголовки, ветки и ответы API не дают номера/вывода, маркер-файл не создаётся).

**Проверка остальных workflow'ов — закрыто.** Других `sed` в исполняемый файл нет. Раньше `${{ }}` оставались внутри `run:` для значений, которые задаёт вызывающий репозиторий или сам workflow: `inputs.goos/goarch/projectname/folder` ([go_build_with_artifacts.yml](../.github/workflows/go_build_with_artifacts.yml), а `inputs.folder` — ещё и в [actions_for_push.yml](../.github/workflows/actions_for_push.yml), [actions_for_push_go.yml](../.github/workflows/actions_for_push_go.yml), [pr_annotation.yml](../.github/workflows/pr_annotation.yml)), `inputs.file_path` ([deploy_for_build_application.yml](../.github/workflows/deploy_for_build_application.yml), его же `source`'или), `steps.version.outputs.version` ([release_frontend.yml](../.github/workflows/release_frontend.yml)), `github.actor` ([deploy_for_lerna.yml](../.github/workflows/deploy_for_lerna.yml), [publish_package.yml](../.github/workflows/publish_package.yml)). Теперь каждое значение приходит через `env:` шага и используется в скрипте в кавычках (`"$FOLDER"`, `"$PROJECTNAME"`, `"$GIT_ACTOR"`). В [deploy_for_full_app.yml](../.github/workflows/deploy_for_full_app.yml) `steps.*.outputs.version` стоят в `with: build_args`, а не в `run:`; `build_args` читает `docker-image` из `env:`, так что менять там нечего.

**`deploy_for_build_application.yml`** намеренно исполняет скрипт, выбранный вызывающим. Путь теперь проходит проверку в action [`run-build-script`](actions.md#run-build-script) (`run.sh`, путь через `env:`) до `source`: он должен быть относительным, без сегментов `..`, указывать на существующий обычный файл, который после разыменования симлинков лежит внутри workspace; иначе шаг падает с понятным сообщением. Запись `. ./<путь>` с `./` не даёт оболочке искать имя в `PATH`.

**Правило закреплено guard-тестом** [no-expressions-in-run.bats](../tests/no-expressions-in-run.bats): ни в одном workflow и `action.yml` в теле `run:` (блочном и однострочном) нет `${{ }}`; `if:`, `with:` и `env:` разрешены. Тест проверяет и сам сканер на плохих и хороших примерах. Проверка пути — [run-build-script.bats](../tests/run-build-script.bats).

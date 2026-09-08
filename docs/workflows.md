# Справочник по workflow'ам

Подробное описание каждого переиспользуемого workflow: входные параметры (`inputs`), используемые секреты (`secrets`) и переменные (`vars`), а также основные шаги. Все workflow'ы объявлены как `on: workflow_call` и предназначены для вызова через `uses` из других репозиториев.

← Назад к [README](../README.md)

## Общие моменты

- **`concurrency`** — почти все workflow'ы группируют запуски по `${{ github.workflow }}-${{ github.ref }}` (а где есть параметр `folder` — ещё и по нему) с `cancel-in-progress: true`. Это значит, что новый запуск отменяет предыдущий незавершённый для той же ветки/папки.
- **Версия Node.js** извлекается из `package.json` (`jq '.engines.node'`).
- **Версия Go** извлекается из `go.mod` (строка `go ...`).
- **Приватный npm-реестр** `@moogur` настраивается на `https://npm.pkg.github.com/` с авторизацией через `secrets.GITHUB_TOKEN`.
- **Параметр `folder`** (там, где он есть) позволяет запускать пайплайн для подпапки монорепозитория — её содержимое копируется в корень рабочей директории перед сборкой.
- **Общие шаги** (определение версии Node/Go, npm-аутентификация, версия приложения по тегу) вынесены в [composite actions](actions.md) и подключаются как `uses: moogur/all-workflows/.github/actions/<name>@master`.

---

## CI / проверки кода

### `actions_for_push.yml` — Lint, build, test (Node.js)

Базовый CI для Node.js-проекта.

**Входные параметры:**

| Параметр | Тип | Обяз. | По умолчанию | Описание |
| --- | --- | --- | --- | --- |
| `skip_tests` | string | нет | `'false'` | Пропустить шаг тестов |
| `folder` | string | нет | `'.'` | Рабочая папка (для монорепозиториев) |

**Секреты:** `GITHUB_TOKEN` (установка зависимостей из приватного реестра).

**Шаги:** checkout → подготовка папки → setup-node (определение версии + кэш npm) → npm-auth → `npm ci` → `npm run lint` → `npm run build` → `npm run test:coverage` (если `skip_tests != 'true'`).

### `actions_for_push_go.yml` — Lint, build, test (Go)

Базовый CI для Go-проекта.

**Входные параметры:** `skip_tests` (`'false'`), `folder` (`'.'`) — как выше.

**Шаги:** checkout → подготовка папки → определение версии Go → setup-go → `go mod verify` → `go build -v ./...` → `go vet ./...` → `staticcheck ./...` → `golint ./...` → `go test -race -vet=off ./...` (если `skip_tests != 'true'`).

### `pr_annotation.yml` — Аннотации покрытия Jest

Запускает тесты Jest и публикует отчёт о покрытии прямо в Pull Request с аннотациями упавших тестов (используется [`ArtiomTr/jest-coverage-report-action`](https://github.com/ArtiomTr/jest-coverage-report-action)).

**Входные параметры:** `skip_tests` (`'false'`), `folder` (`'.'`).

**Секреты:** `GITHUB_TOKEN`.

**Шаги:** checkout → подготовка папки → setup-node (с кэшем npm) → npm-auth → `npm ci` → action покрытия с `test-script: npm run test:coverage`.

### `pr_annotation_go.yml` — Аннотации тестов Go (заготовка)

Подготавливает окружение Go для аннотаций тестов в PR. На текущий момент шаг запуска тестов закомментирован — workflow выполняет только установку Go.

**Входные параметры:** `skip_tests` (`'false'`), `folder` (`'.'`).

---

## Релизы и артефакты

### `release.yml` — Публикация релиза

Создаёт и публикует GitHub-релиз на основе тега через [Release Drafter](https://github.com/release-drafter/release-drafter). Версия вычисляется из имени тега (`refs/tags/vX.Y.Z` → `X.Y.Z`). Конфигурация категорий и резолвинга версии — в [`.github/release-drafter.yml`](../.github/release-drafter.yml).

**Секреты:** `GITHUB_TOKEN`.

### `release_frontend.yml` — Релиз + сборка фронтенда

Публикует релиз через Release Drafter, затем собирает фронтенд и прикладывает к релизу `application.zip`.

**Секреты:** `GITHUB_TOKEN`.

**Шаги:** checkout → определение версии из тега → публикация релиза → setup-node (с кэшем npm) → npm-auth → `npm ci` → сборка с `VITE_VERSION=<version>` → упаковка `dist` в `application.zip` → загрузка ассета в релиз.

### `release_with_artifacts.yml` — Релиз + готовый артефакт

Публикует релиз и прикладывает к нему ранее собранный артефакт `*.tar.gz` (обычно подготовленный workflow'ом [`go_build_with_artifacts.yml`](#go_build_with_artifactsyml--сборка-go-бинарника)).

**Входные параметры:**

| Параметр | Тип | Обяз. | По умолчанию | Описание |
| --- | --- | --- | --- | --- |
| `projectname` | string | нет | `'main'` | Имя проекта = имя скачиваемого артефакта |
| `suffixname` | string | нет | `''` | Суффикс к имени файла ассета |

**Секреты:** `GITHUB_TOKEN`.

**Шаги:** checkout → версия из тега → публикация релиза → `download-artifact` (`<projectname>`) → загрузка `<projectname>.tar.gz` как `<projectname><suffixname>.tar.gz`.

### `go_build_with_artifacts.yml` — Сборка Go-бинарника

Кросс-компилирует Go-проект через `make build` и сохраняет результат как артефакт GitHub Actions (хранится 1 день). Обычно используется в паре с `release_with_artifacts.yml`.

**Входные параметры:**

| Параметр | Тип | Обяз. | По умолчанию | Описание |
| --- | --- | --- | --- | --- |
| `folder` | string | нет | `'.'` | Рабочая папка |
| `goos` | string | нет | `'linux'` | Целевая ОС (`GOOS`) |
| `goarch` | string | нет | `'amd64'` | Целевая архитектура (`GOARCH`) |
| `projectname` | string | нет | `'main'` | Имя проекта (`PROJECTNAME`) |

**Требования к проекту:** наличие `Makefile` с целью `build`, принимающей `GOOS`, `GOARCH`, `PROJECTNAME` и складывающей бинарник в `./bin/<projectname>`.

### `deploy_for_build_application.yml` — Сборка по скрипту + релиз

Выполняет произвольный скрипт сборки, создаёт GitHub-релиз и прикладывает `application.zip`.

**Входные параметры:**

| Параметр | Тип | Обяз. | Описание |
| --- | --- | --- | --- |
| `file_path` | string | да | Путь к исполняемому файлу сборки (запускается через `. <file_path>`) |

**Секреты:** `GITHUB_TOKEN`.

**Шаги:** checkout → версия из тега → выполнение `file_path` → `actions/create-release` → загрузка `./application.zip`.

> Скрипт сборки должен в результате создать файл `application.zip` в корне рабочей директории.

---

## Docker-образы

Все Docker-workflow'ы публикуют образы в GitHub Packages по адресу
`docker.pkg.github.com/<github_user>/<repo>/<repo>` с тегами `latest` и версией приложения.
В [`deploy_for_docker_container.yml`](#deploy_for_docker_containeryml--образ-по-локальному-dockerfile) набор тегов
выбирается параметром `format_mode` (см. [`docker-tags`](actions.md#docker-tags)).
Подробнее про используемые Dockerfile'ы — в [docs/dockerfiles.md](dockerfiles.md).

### `deploy_for_backend.yml` — Docker-образ Node.js-бэкенда

**Входные параметры:**

| Параметр | Тип | Обяз. | По умолчанию | Описание |
| --- | --- | --- | --- | --- |
| `github_user` | string | нет | `$GITHUB_ACTOR` | Пользователь GitHub (владелец образа / логин в реестр) |

**Секреты:** `GITHUB_TOKEN`.

**Шаги:** checkout → версия Node → формирование имени образа → версия из git-тега → создание `.npmrc` для приватного реестра → скачивание `.dockerignore` и `deploy_backend.dockerfile` из этого репозитория → `docker build` (с `ARG_NODE_VERSION`, `ARG_APP_VERSION`) → `docker login` → `docker push`.

### `deploy_for_go_backend.yml` — Docker-образ Go-бэкенда

Аналогичен предыдущему, но для Go: скачивает `.full.dockerignore` и `deploy_go_backend.dockerfile`, собирает многоступенчатый образ на `scratch`.

**Входные параметры:** `github_user` (`$GITHUB_ACTOR`).

**Секреты:** `GITHUB_TOKEN`.

### `deploy_for_full_app.yml` — Docker-образ полного приложения

Собирает единый образ для приложения, состоящего из Go-бэкенда и Node.js-фронтенда (использует `full_deploy.dockerfile`). Создаёт `.npmrc` в папке `frontend`.

**Входные параметры:** `github_user` (`$GITHUB_ACTOR`).

**Секреты:** `GITHUB_TOKEN`.

### `deploy_for_docker_container.yml` — Образ по локальному Dockerfile

Универсальная сборка: использует `Dockerfile`, лежащий в самом проекте (ничего не скачивает). Версия — тег, инициировавший запуск. Сборка **без тега** (расписание, ручной запуск) всегда идёт как `dd.mm.yyyy-HHMM-auto` в формате `date`, даже если репозиторий настроен на `semver`.

**Входные параметры:**

| Параметр | Тип | Обяз. | По умолчанию | Описание |
| --- | --- | --- | --- | --- |
| `github_user` | string | нет | `$GITHUB_ACTOR` | Пользователь GitHub (владелец образа / логин в реестр) |
| `format_mode` | string | нет | `'date'` | Формат тегов образа: `date` — `<версия>` + `latest`; `semver` — `vX.Y.Z`, `vX.Y`, `vX`, `latest` |

**Секреты:** `GITHUB_TOKEN`.

**Шаги:** checkout → формирование имени образа → определение версии → [`docker-tags`](actions.md#docker-tags) (список тегов по `format_mode`) → `docker build` со всеми тегами → `docker login` → `docker push` каждого тега.

Пример вызова для репозитория с числовыми тегами:

```yaml
on:
  push:
    tags:
      - "v[0-9]+.[0-9]+.[0-9]+"

jobs:
  deploy:
    uses: moogur/all-workflows/.github/workflows/deploy_for_docker_container.yml@master
    secrets: inherit
    with:
      format_mode: 'semver'
```

> Параметр не задан → `date`, то есть старое поведение (репозитории с тегами-датами менять не нужно).
> В режиме `semver` тег обязан подходить под `vX.Y.Z`, иначе сборка падает.
> `format_mode` действует только на сборку по тегу: плановая пересборка (`schedule`) публикует
> `dd.mm.yyyy-HHMM-auto` и `latest`, а релизные `vX.Y.Z` / `vX.Y` / `vX` остаются нетронутыми — иначе
> она переписала бы уже выпущенную версию другим содержимым.

### `auto_deploy_for_docker_container.yml` — Автодеплой при обновлении

Проверяет, появилась ли новая версия во внешнем репозитории, и только в этом случае запускает [`deploy_for_docker_container.yml`](#deploy_for_docker_containeryml--образ-по-локальному-dockerfile) (без `format_mode`, то есть в формате `date`: тега при запуске по расписанию нет). Состояние «последней увиденной версии» хранится в переменной окружения `LAST_UPDATE_VALUE` указанного GitHub Environment.

**Входные параметры:**

| Параметр | Тип | Обяз. | По умолчанию | Описание |
| --- | --- | --- | --- | --- |
| `repository_url` | string | да | — | URL отслеживаемого git-репозитория |
| `environment` | string | да | — | Имя GitHub Environment (где хранится `LAST_UPDATE_VALUE`) |
| `type` | string | нет | `'commit'` | Критерий новизны: `commit` или `tag` |
| `repository_branch` | string | нет | `'master'` | Ветка для проверки (для `type: commit`) |

**Секреты:** `UPDATE_VARIABLES_CLI_TOKEN` (PAT для обновления переменной через API), `GITHUB_TOKEN`.

**Логика (три job'а):**

1. `checking_to_use_the_latest_version` — [`remote-update-check`](actions.md#remote-update-check) считывает маркер свежести внешнего репозитория (`commit` — время последнего коммита ветки, `tag` — имя самого свежего по дате создания тега). Если он совпадает с `vars.LAST_UPDATE_VALUE`, job завершается с ошибкой и всё остальное пропускается.
2. `auto_deploy` — сборка и публикация образа (`secrets: inherit`).
3. `save_update_value` — [`save-update-value`](actions.md#save-update-value) записывает новый маркер в `LAST_UPDATE_VALUE`.

> **Порядок важен:** переменная обновляется **после** успешного деплоя. Если бы она обновлялась в момент проверки (как было раньше), упавшая сборка считалась бы доставленной и следующий запуск по расписанию уже не повторил бы её.
> Переменную не нужно заводить руками: при первом запуске в новом Environment она создаётся (`POST`), дальше обновляется (`PATCH`).
> Если у Environment настроены required reviewers, job проверки встанет на ручное подтверждение — «авто»-деплой перестанет быть автоматическим.

### `auto_deploy_for_build_application.yml` — Автодеплой сборки приложения

То же, что выше (те же три job'а и тот же порядок сохранения маркера), но вместо Docker запускает [`deploy_for_build_application.yml`](#deploy_for_build_applicationyml--сборка-по-скрипту--релиз).

**Входные параметры:** все параметры `auto_deploy_for_docker_container.yml` плюс:

| Параметр | Тип | Обяз. | Описание |
| --- | --- | --- | --- |
| `file_path` | string | да | Путь к скрипту сборки |

Во вложенный [`deploy_for_build_application.yml`](#deploy_for_build_applicationyml--сборка-по-скрипту--релиз) передаётся `file_path: ${{ inputs.repository_branch }}`: в этом сценарии путь к исполняемому скрипту сборки совпадает со значением `repository_branch`.

---

## Публикация пакетов и фронтенда

### `publish_package.yml` — Публикация npm-пакета

Собирает и публикует npm-пакет в GitHub Packages.

**Секреты:** `GITHUB_TOKEN`.

**Шаги:** checkout → setup-node (с кэшем npm) → npm-auth → `npm ci` → `npm run build` → запуск `node ./node_modules/@moogur/helpers/pre-build.js` → `npm publish`.

> Требует зависимость `@moogur/helpers` (скрипт `pre-build.js`).

### `deploy_for_lerna.yml` — Публикация монорепозитория через Lerna

Публикует пакеты Lerna-монорепозитория в реестр GitHub Packages командой `lerna publish from-package`. Перед установкой удаляет скрипт `prepare` (husky) из `package.json`, чтобы избежать его запуска в CI.

**Секреты:** `GITHUB_TOKEN`.

### `deploy_for_frontend.yml` — Деплой фронтенда в ветку `builds`

Собирает фронтенд и публикует содержимое `dist` в отдельную ветку `builds` (force-push). Удобно для статического хостинга, который раздаёт ветку `builds`.

**Секреты:** `GITHUB_TOKEN`.

**Шаги:** checkout → setup-node (с кэшем npm) → npm-auth → `npm ci` → `npm run build` → создание ветки `builds` → очистка репозитория и копирование содержимого `dist` в корень → коммит → `git push origin builds --force`.

---

## Интеграции

### `kanboard.yml` — Перемещение задач Kanboard

Автоматически двигает задачи по колонкам канбан-доски [Kanboard](https://kanboard.org/) в зависимости от события Git. Номер задачи извлекается из сообщения коммита или имени ветки (формат `XX-<id>-...`). Подробности и описание JSON-RPC скрипта — в [docs/kanboard.md](kanboard.md).

**Входные параметры:**

| Параметр | Тип | Обяз. | Описание |
| --- | --- | --- | --- |
| `kanboard_columns` | string | да | Список id колонок слева направо через запятую |
| `project_type` | string | да | Тип проекта: `single_branch` или `multi_branch` |
| `event_type` | string | да | Тип события: `push`, `pr`, `merge`, `deploy` |

**Секреты:** `KANBOARD_HOST`, `KANBOARD_USER`, `KANBOARD_TOKEN`.

**Переходы по колонкам (индексы в `kanboard_columns`):**

| Событие | Условие | Перемещение |
| --- | --- | --- |
| `push` | задача в одной из «рабочих» колонок | → колонка `[3]` (in progress) |
| `pr` | `multi_branch`, задача в `[3]` | → колонка `[4]` (in review) |
| `merge` | `multi_branch`, задача в `[4]` | → колонка `[5]` (merged) |
| `deploy` | `multi_branch`, задачи из диапазона тегов в `[5]` | → колонка `[6]` (deploy) + проставление версии в метаданные задачи |

# Справочник по workflow'ам

Подробное описание каждого переиспользуемого workflow: входные параметры (`inputs`), используемые секреты (`secrets`) и переменные (`vars`), а также основные шаги. Все workflow'ы объявлены как `on: workflow_call` и предназначены для вызова через `uses` из других репозиториев.

← Назад к [README](../README.md)

## Общие моменты

- **`permissions`** — каждый workflow объявляет права `GITHUB_TOKEN` явно (минимально необходимые). Вызванный workflow не может просить больше, чем есть у вызвавшего: если в репозитории-потребителе токен урезан, запуск упадёт сразу с понятной ошибкой, а не на середине деплоя. Полная таблица — в [conventions.md](conventions.md#права-github_token).
- **`concurrency`** — почти все workflow'ы группируют запуски по `${{ github.workflow }}-${{ github.ref }}` (а где есть параметр `folder` — ещё и по нему; `go_build_with_artifacts` — ещё и по `goos`/`goarch`, чтобы job'ы одной матрицы не отменяли друг друга) с `cancel-in-progress: true`. Это значит, что новый запуск отменяет предыдущий незавершённый для той же ветки/папки/платформы.
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

**Шаги:** checkout → подготовка папки → setup-node (с кэшем npm) → npm-auth → `npm ci` → удаление `.npmrc` → action покрытия с `test-script: npm run test:coverage` и `skip-step: install`.

Job не запускается на Pull Request из форка, а токен приватного scope не доживает до выполнения кода из PR — подробности в [security.md](security.md#1-недоверенный-код-из-pull-request).

---

## Релизы и артефакты

Отдельного «релизного» workflow больше нет: каждая сборка, у которой есть что опубликовать, по тегу
(`if: github.ref_type == 'tag'`) сама вызывает единую цепочку [`github-release`](actions.md#github-release) —
проверка формата тега, тело из PR/коммитов, публикация с ассетами. Без тега (авто-деплой по расписанию,
ручной запуск) релизный шаг просто пропускается.

### `go_build_with_artifacts.yml` — Сборка Go-бинарника (+ релиз по тегу)

Кросс-компилирует Go-проект через `make build`, сохраняет результат как артефакт GitHub Actions (хранится
1 день) и, по тегу, прикладывает бинарник к GitHub-релизу.

**Входные параметры:**

| Параметр | Тип | Обяз. | По умолчанию | Описание |
| --- | --- | --- | --- | --- |
| `folder` | string | нет | `'.'` | Рабочая папка |
| `goos` | string | нет | `'linux'` | Целевая ОС (`GOOS`) |
| `goarch` | string | нет | `'amd64'` | Целевая архитектура (`GOARCH`) |
| `projectname` | string | нет | `'main'` | Имя проекта (`PROJECTNAME`) |

**Секреты:** `GITHUB_TOKEN`.

**Требования к проекту:** наличие `Makefile` с целью `build`, принимающей `GOOS`, `GOARCH`, `PROJECTNAME` и складывающей бинарник в `./bin/<projectname>`.

**Шаги:** checkout с `fetch-depth: 0` → сборка и упаковка в `<projectname>.tar.gz` → `upload-artifact` (всегда) →
**по тегу**: копия ассета `<projectname>-<goos>-<goarch>.tar.gz` → [`github-release`](actions.md#github-release).

> **Имя ассета релиза включает `goos`/`goarch`.** У всей матрицы (разные ОС/архитектуры одного и того же
> вызова этого workflow) общий тег — без платформы в имени параллельные job'ы матрицы перезаписали бы
> ассет друг друга (`gh release upload --clobber` заменяет файл с тем же именем). Артефакт GitHub Actions
> (`upload-artifact`) при этом сохраняет прежнее имя — он никак не участвует в релизе.
>
> **Группа `concurrency` включает `goos`/`goarch`.** Без них job'ы одной матрицы для одного тега попали бы
> в одну группу конкурентности и отменяли бы друг друга (`cancel-in-progress: true`) — до того, как каждый
> успеет опубликовать свой ассет.

### `deploy_for_build_application.yml` — Сборка по скрипту + релиз

Выполняет произвольный скрипт сборки и, если запуск идёт по тегу, создаёт GitHub-релиз с `application.zip`. Без тега (авто-деплой по расписанию) сборка выполняется, но релиз полностью пропускается.

**Входные параметры:**

| Параметр | Тип | Обяз. | Описание |
| --- | --- | --- | --- |
| `file_path` | string | да | Путь к исполняемому файлу сборки (запускается через `. <file_path>`) |

**Секреты:** `GITHUB_TOKEN`.

**Шаги:** checkout с `fetch-depth: 0` → **по тегу**: [`tag-format`](actions.md#tag-format) (фейл-фаст до сборки) → выполнение `file_path` (всегда) → **по тегу** (`if: github.ref_type == 'tag'`): версия (`mode: ref`, `prefix: ''`) → [`github-release`](actions.md#github-release) с `./application.zip` и заголовком `Release <version>`.

> **Без тега релиза не будет.** Раньше версия без тега (авто-деплой) считалась через `git describe` — на коммите с несколькими тегами (дата и `vX.Y.Z`) он мог выбрать другой, чем инициировавший запуск. Теперь версия для релиза — только `mode: ref` (сам тег, инициировавший запуск), и шаги версии/релиза закрыты условием `github.ref_type == 'tag'`; без тега выполняется только сборочный скрипт.

> Скрипт сборки должен в результате создать файл `application.zip` в корне рабочей директории.

### `release_frontend.yml` — Релиз + сборка фронтенда

Собирает фронтенд, прикладывает к сборке `application.zip` и, по тегу, публикует GitHub-релиз.

**Секреты:** `GITHUB_TOKEN`.

**Шаги:** checkout с `fetch-depth: 0` → **по тегу**: [`tag-format`](actions.md#tag-format) (фейл-фаст до сборки) → версия из тега (`mode: ref`, идёт в `VITE_VERSION`) → setup-node (с кэшем npm) → npm-auth → `npm ci` → сборка с `VITE_VERSION=<version>` → упаковка `dist` в `application.zip` → **по тегу**: [`github-release`](actions.md#github-release) с ассетом.

> Версия считается всегда (нужна `VITE_VERSION` независимо от того, тег это или нет), а вот релиз публикуется
> только по тегу — сборка ветки (не тега) просто не создаёт релиз.

---

## Docker-образы

Все Docker-workflow'ы публикуют образы в GitHub Packages по адресу
`docker.pkg.github.com/<github_user>/<repo>/<repo>`. Набор тегов определяется по формату версии
(см. [`docker-tags`](actions.md#docker-tags)). Подробнее про используемые Dockerfile'ы — в [docs/dockerfiles.md](dockerfiles.md).

**Тело сборки у всех четырёх общее** — action [`docker-image`](actions.md#docker-image): версия, теги, подмена
Dockerfile, `docker build`, логин и пуш. Сами workflow'ы отличаются только спецификой стека (какую версию языка
определить, нужен ли `.npmrc`, какой Dockerfile взять), поэтому у них одинаковые входы и секреты:

| Параметр | Тип | Обяз. | По умолчанию | Описание |
| --- | --- | --- | --- | --- |
| `github_user` | string | нет | `$GITHUB_ACTOR` | Пользователь GitHub (владелец образа / логин в реестр) |

**Секреты:** `GITHUB_TOKEN`.

| Workflow | Версия языка | `.npmrc` | Dockerfile |
| --- | --- | --- | --- |
| `deploy_for_backend` | Node | в корне | `deploy_backend.dockerfile` + `.dockerignore` |
| `deploy_for_go_backend` | Go | — | `deploy_go_backend.dockerfile` + `.full.dockerignore` |
| `deploy_for_full_app` | Node + Go | в `frontend/` | `full_deploy.dockerfile` + `.full.dockerignore` |
| `deploy_for_docker_container` | — | — | свой, из проекта |

> **Версия сборки везде одинакова:** тег, инициировавший запуск, а запуск без тега (расписание, ручной) —
> `dd.mm.yyyy-HHMM-auto` (датная метка), даже в semver-репозитории. Раньше так вёл себя только
> `deploy_for_docker_container`, а остальные три брали последний тег из истории и плановой пересборкой могли
> переписать релизный `vX.Y.Z` другим содержимым.

> **Сборка по тегу публикует и GitHub-релиз.** Последним шагом `docker-image` вызывает
> [`docker-release`](actions.md#docker-release) (`if: github.ref_type == 'tag'`, после успешного пуша образа):
> тело собирает [`github-release`](actions.md#github-release) (PR/коммиты из локальной git-истории),
> `docker-release` дописывает блок `docker pull` и список тегов образа. Сборка без тега (расписание, ручной
> запуск) релиз не трогает. Из-за этого у всех четырёх workflow'ов `permissions: contents: write` (вместо
> прежнего `contents: read`).

### `deploy_for_backend.yml` — Docker-образ Node.js-бэкенда

**Шаги:** checkout → [`detect-node-version`](actions.md#detect-node-version) → [`npm-auth`](actions.md#npm-auth) в корне → [`docker-image`](actions.md#docker-image) с `deploy_backend.dockerfile` и `ARG_NODE_VERSION`.

### `deploy_for_go_backend.yml` — Docker-образ Go-бэкенда

Многоступенчатый образ на `scratch`.

**Шаги:** checkout → [`detect-go-version`](actions.md#detect-go-version) → [`docker-image`](actions.md#docker-image) с `deploy_go_backend.dockerfile` и `ARG_GO_VERSION`.

### `deploy_for_full_app.yml` — Docker-образ полного приложения

Единый образ для приложения из Go-бэкенда и Node.js-фронтенда.

**Шаги:** checkout → версии Node и Go → [`npm-auth`](actions.md#npm-auth) в `frontend/` → [`docker-image`](actions.md#docker-image) с `full_deploy.dockerfile` и обоими build-arg.

### `deploy_for_docker_container.yml` — Образ по локальному Dockerfile

Сборка по `Dockerfile`, который лежит в самом проекте: ничего не подменяется.

**Шаги:** checkout → [`docker-image`](actions.md#docker-image) без `dockerfile`.

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
```

> Формат тегов образа выводится из тега: `dd.mm.yyyy` → `<версия>` + `latest`, `vX.Y.Z` → лестница
> `vX.Y.Z`, `vX.Y`, `vX`, `latest`. Тег другого вида (предрелиз, неполная версия) — сборка падает.
> Плановая пересборка (`schedule`) публикует `dd.mm.yyyy-HHMM-auto` и `latest`, а релизные
> `vX.Y.Z` / `vX.Y` / `vX` остаются нетронутыми — иначе она переписала бы уже выпущенную версию другим содержимым.

### `auto_deploy_for_docker_container.yml` — Автодеплой при обновлении

Проверяет, появилась ли новая версия во внешнем репозитории, и только в этом случае запускает [`deploy_for_docker_container.yml`](#deploy_for_docker_containeryml--образ-по-локальному-dockerfile) (тега при запуске по расписанию нет, поэтому образ получает датную метку). Состояние «последней увиденной версии» хранится в переменной окружения `LAST_UPDATE_VALUE` указанного GitHub Environment.

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

> Запуск идёт не по тегу, поэтому во вложенном workflow релиз не публикуется — выполняется только сборочный скрипт.

---

## Публикация пакетов и фронтенда

### `publish_package.yml` — Публикация npm-пакета

Собирает и публикует npm-пакет в GitHub Packages. По тегу, после успешной публикации, — GitHub-релиз
с блоком `npm install`.

**Секреты:** `GITHUB_TOKEN`.

**Шаги:** checkout с `fetch-depth: 0` → setup-node (с кэшем npm) → npm-auth → `npm ci` → `npm run build` → запуск `node ./node_modules/@moogur/helpers/pre-build.js` → `npm publish` → **по тегу**: имя/версия из `package.json` ([`npm-package-version`](actions.md#npm-package-version)) → [`npm-package-notes`](actions.md#npm-package-notes) → [`github-release`](actions.md#github-release).

> Требует зависимость `@moogur/helpers` (скрипт `pre-build.js`).
> `package.json` читается **после** `pre-build.js` — он готовит файл к публикации (может менять версию), поэтому имя/версия в релизе — то, что реально опубликовано.

### `deploy_for_lerna.yml` — Публикация монорепозитория через Lerna

Публикует пакеты Lerna-монорепозитория в реестр GitHub Packages командой `lerna publish from-package`. Перед установкой удаляет скрипт `prepare` (husky) из `package.json`, чтобы избежать его запуска в CI. По тегу, после публикации, — GitHub-релиз с `npm install` на каждый непубличный пакет.

**Секреты:** `GITHUB_TOKEN`.

**Шаги (добавлены по тегу, перед `Publish packages`):** файлы `packages/*/package.json` (раскладка пуста —
ошибка до публикации) → имя+версия каждого непубличного пакета ([`npm-package-version`](actions.md#npm-package-version))
→ `Publish packages` → [`npm-package-notes`](actions.md#npm-package-notes) → [`github-release`](actions.md#github-release).

> **Раскладка пакетов — `packages/*/package.json`.** Это раскладка Lerna по умолчанию; кастомный `packages`
> в `lerna.json` (другой glob) не читается — понадобится своя доработка. Список пакетов собирается до
> `lerna publish`, чтобы неверная раскладка проваливала сборку раньше, чем что-то уже опубликовано в реестр.

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

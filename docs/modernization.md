# Отложенная модернизация (TODO)

Здесь собраны замечания по устаревшей инфраструктуре, которые **сознательно не правились** при рефакторинге, чтобы не менять поведение и используемые реестры/пакеты. Поведение всех workflow'ов оставлено прежним. Этот список — чтобы ничего не потерять при будущей миграции.

← Назад к [README](../README.md)

## P0 — устаревшая инфраструктура

### 1. Docker-реестр `docker.pkg.github.com`

**Где:** [deploy_for_backend.yml](../.github/workflows/deploy_for_backend.yml), [deploy_for_go_backend.yml](../.github/workflows/deploy_for_go_backend.yml), [deploy_for_full_app.yml](../.github/workflows/deploy_for_full_app.yml), [deploy_for_docker_container.yml](../.github/workflows/deploy_for_docker_container.yml).

Docker-реестр GitHub Packages по адресу `docker.pkg.github.com` устарел; актуальный — **`ghcr.io`** (GitHub Container Registry).

**Что можно сделать при миграции:**
- заменить адрес образа на `ghcr.io/<owner>/<repo>`;
- использовать официальные actions: [`docker/login-action`](https://github.com/docker/login-action) (логин через `--password-stdin`), [`docker/build-push-action`](https://github.com/docker/build-push-action) (buildx, кэш слоёв, мульти-арх).

> Оставлено как есть по решению владельца репозитория.

### 2. `golint`

**Где:** [actions_for_push_go.yml](../.github/workflows/actions_for_push_go.yml).

`golang/lint` (`golint`) заархивирован. Дополнительно `staticcheck` и `golint` ставятся как `@latest` на каждом прогоне (медленно и невоспроизводимо).

**Замена:** [`golangci-lint`](https://github.com/golangci/golangci-lint) (включает в себя `staticcheck`); версии инструментов запинить.

## Версионирование зависимостей через `@master`

Несколько мест жёстко ссылаются на ветку `master`/`main`, из-за чего версия вызванного workflow и версия скачиваемого ресурса могут разойтись:

| Где | Что тянется | Ссылка |
| --- | --- | --- |
| [deploy_for_backend.yml](../.github/workflows/deploy_for_backend.yml), [deploy_for_go_backend.yml](../.github/workflows/deploy_for_go_backend.yml), [deploy_for_full_app.yml](../.github/workflows/deploy_for_full_app.yml) | Dockerfile и `.dockerignore` через `wget` с `raw.githubusercontent.com/.../master/...` | хардкод `master` |
| Все workflow'ы | composite actions `moogur/all-workflows/.github/actions/*@master` | хардкод `master` |

> Оставлено как есть по решению владельца репозитория. При желании можно заменить `master` на конкретный тег/SHA, чтобы привязать ресурсы к версии вызываемого workflow.

## Dockerfiles

Статический разбор [`dockerfiles/`](../dockerfiles/) (не собирались — поведение зависит от
проекта-потребителя; уверенность указана). Подробности — в [dockerfiles.md](dockerfiles.md).

**🔴 Критичное (вероятно, ломается):**

- **(1) [full_deploy.dockerfile](../dockerfiles/full_deploy.dockerfile): `make` нет в `golang:<ver>-alpine`.** Стадия `backend` делает `make build`, но в alpine-образе go нет `make` → `make: not found`. Нужно `RUN apk add --no-cache make` (и `build-base`, если CGO). Уверенность высокая.
- **(2) [deploy_backend.dockerfile](../dockerfiles/deploy_backend.dockerfile): в рантайм-образе нет `node_modules`.** Финальная стадия копирует только `dist` и запускает `node dist/index.js`, не ставя прод-зависимости. Работает лишь если сборка бандлит зависимости в `dist`. Для стандартного `nest build` (на NestJS указывает `nest-cli.json` в `.dockerignore`) — `Cannot find module`. Уверенность средняя (зависит от бандлинга).

**🟠 Надёжность:**

- **(3) Образы на `scratch` без CA-сертификатов и tzdata** ([deploy_go_backend](../dockerfiles/deploy_go_backend.dockerfile), [full_deploy](../dockerfiles/full_deploy.dockerfile)): исходящий HTTPS падает с x509, нет таймзон. Лечится `COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/` или `gcr.io/distroless/static`.
- **(4) full_deploy: scratch требует статический бинарь** — если `make build` проекта собирает не статически (без `CGO_ENABLED=0`/`-extldflags -static`), `/main` не запустится.
- **(5) deploy_backend: `CMD node dist/index.js` в shell-форме** — node не PID 1, не получает SIGTERM (проблемы с graceful shutdown). Лучше exec-форма: `CMD ["node", "dist/index.js"]`.

**🟡 Гигиена / `.dockerignore`:**

- **(6) [.full.dockerignore](../dockerfiles/.full.dockerignore) слишком скудный** — не исключает `node_modules`, `dist`, `.github`, `coverage` и **`.env`** (в Node-варианте [.dockerignore](../dockerfiles/.dockerignore) `.env` исключён). Раздувает контекст, `.env` светится в build-слоях. Привести к одному уровню.
- **(7) Node [.dockerignore](../dockerfiles/.dockerignore): `.git` закомментирован** → история гита уходит в контекст и в builder-слой через `COPY . .`. Плюс дубль `*.md` и `README.md`.
- **(8) Мелочи:** строчный `as` в `FROM ... as` (предупреждение BuildKit `FromAsCasing`); в full_deploy `COPY . .` без `WORKDIR` копирует в `/`; нет `USER` (root); нет кэширующего слоя зависимостей.

> Можно добавить `hadolint` (линтер Dockerfile) в CI/Makefile, чтобы ловить часть этого автоматически.

## Прочие наблюдения (не критично)

- **`exit 1` при отсутствии обновлений** в auto-deploy workflow'ах помечает прогон красным. Оставлено намеренно: так гарантированно пропускаются все последующие шаги, а не только деплой (см. [workflows.md](workflows.md)).
- **Недоступность Kanboard не роняет прогон.** Вызывающий код не проверяет код возврата `request_for_*`, поэтому задача просто не переезжает по колонкам, а деплой идёт дальше. С обёрткой `execute_request` это хотя бы видно в логе (`Kanboard request failed: <url>`). Если понадобится обратное поведение — `continue-on-error` на job и явная проверка статуса.
- **Required reviewers у Environment** остановят job проверки в авто-деплое на ручном подтверждении — автоматическим такой деплой уже не будет. Ограничение самого GitHub, обходить нечем (кроме отказа от `environment:` и хранения состояния где-то ещё).

## Исправлено

- **Кэш `node_modules` + пропуск `npm ci`** → перешли на `actions/setup-node` с `cache: 'npm'` (кэш `~/.npm`) и безусловный `npm ci` через общий action [`setup-node`](actions.md). Каталог `node_modules` больше не кэшируется.
- **`npm i` → `npm ci`** в [deploy_for_lerna.yml](../.github/workflows/deploy_for_lerna.yml).
- **`wget @master` для kanboard-скрипта** → [kanboard.yml](../.github/workflows/kanboard.yml) теперь берёт `scripts/kanboard_requests.sh` через `actions/checkout` репозитория `all-workflows`, запиненный к `github.job_workflow_sha` (версия вызванного workflow), без обращения к `raw.githubusercontent`.
- **Shebang хука `.husky/commit-msg`** → `#!/usr/bin/env bash` (портативно).
- **Word-splitting в `scripts/kanboard_requests.sh`** → все аргументы закавычены, `shellcheck` проходит строго без исключений.
- **`LAST_UPDATE_VALUE` обновлялся до деплоя** → запись вынесена в отдельный job `save_update_value`, зависящий от результата сборки: упавший деплой больше не «съедает» обновление.
- **Первый запуск авто-деплоя падал на 404** → [`save-update-value`](actions.md#save-update-value) создаёт переменную через `POST`, если `PATCH` не прошёл; заводить её руками больше не нужно.
- **«Последний тег» внешнего репозитория считался сортировкой по имени** (`--sort='v:refname'`), а она врёт на неверсионных тегах: среди датных «максимум» — `26.05.2023`, потому что `26 > 14`, так что маркер мог намертво встать на старом теге. → [`remote-update-check`](actions.md#remote-update-check) берёт самый свежий тег по дате создания, независимо от формата имени.
- **Вложенный вызов деплоя без `secrets: inherit`** в авто-деплое → секреты прокидываются явно (работало только потому, что вложенному workflow хватало автоматического `GITHUB_TOKEN`).
- **Метка авто-сборки `dd.mm.yyyy-auto`** → `dd.mm.yyyy-HHMM-auto` (UTC): две автосборки за сутки больше не перезаписывают друг друга.
- **Лишний `actions/checkout` в авто-деплое** → убран: сравнение идёт по внешнему репозиторию, своя история не нужна.
- **Права `GITHUB_TOKEN` брались из дефолта потребителя** → в каждом workflow объявлен явный минимальный `permissions` (таблица — в [conventions.md](conventions.md#права-github_token)).
- **`deploy_for_backend` / `deploy_for_go_backend` / `deploy_for_full_app` отставали от `deploy_for_docker_container`** → версия берётся из тега, инициировавшего запуск (а не `git describe`, который на коммите с несколькими тегами мог выбрать не тот), теги образа собирает [`docker-tags`](actions.md#docker-tags), появился `format_mode`.
- **`echo $new_package_json > package.json` в [deploy_for_lerna](../.github/workflows/deploy_for_lerna.yml)** → `jq` пишет во временный файл: переменная без кавычек раскрывала глобы в значениях (например, `"files": ["*"]`).
- **`detect-node-version` отдавал строку `null`**, а `detect-go-version` — пустую версию, если поля нет → оба падают с внятным сообщением.
- **`cp -r dist/* .` в [deploy_for_frontend](../.github/workflows/deploy_for_frontend.yml)** → `cp -a dist/. .`: точечные файлы (`.nojekyll`, `.htaccess`) больше не теряются.
- **Сторонние actions работали на node20**, который GitHub выводит из эксплуатации (прогон уже предупреждал: «forced to run on Node.js 24»). → Подняты до мажоров на node24: `actions/checkout@v7`, `actions/setup-go@v7`, `actions/setup-node@v7`, `actions/upload-artifact@v7`, `actions/download-artifact@v7`, `release-drafter/release-drafter@v7`. Минимальные мажоры зафиксированы guard-тестом [action-versions.bats](../tests/action-versions.bats).
- **Заархивированные `actions/create-release` и `actions/upload-release-asset`** → общий action [`publish-release`](actions.md#publish-release) на `gh`: создаёт релиз или обновляет существующий и грузит ассеты с `--clobber`. Перезапуск job'а по уже выпущенному тегу больше не падает.
- **`curl` к Kanboard без таймаутов, ретраев и `-f`** → общая обёртка `execute_request` (см. [kanboard.md](kanboard.md#скрипт-kanboard_requestssh)): запрос больше не висит две минуты на недоступном хосте, переживает короткие сбои и не выдаёт 5xx за успех.

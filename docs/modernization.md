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

### 2. Архивные actions для релизов

**Где:** [deploy_for_build_application.yml](../.github/workflows/deploy_for_build_application.yml), [release_frontend.yml](../.github/workflows/release_frontend.yml), [release_with_artifacts.yml](../.github/workflows/release_with_artifacts.yml).

Используются заархивированные (не поддерживаемые) actions:
- `actions/create-release` (запинен на `@master`);
- `actions/upload-release-asset` (запинен на `@master` / `@main`).

**Замена:** [`softprops/action-gh-release`](https://github.com/softprops/action-gh-release) или CLI `gh release create` / `gh release upload`.

### 3. `golint`

**Где:** [actions_for_push_go.yml](../.github/workflows/actions_for_push_go.yml).

`golang/lint` (`golint`) заархивирован. Дополнительно `staticcheck` и `golint` ставятся как `@latest` на каждом прогоне (медленно и невоспроизводимо).

**Замена:** [`golangci-lint`](https://github.com/golangci/golangci-lint) (включает в себя `staticcheck`); версии инструментов запинить.

## Версионирование зависимостей через `@master`

Несколько мест жёстко ссылаются на ветку `master`/`main`, из-за чего версия вызванного workflow и версия скачиваемого ресурса могут разойтись:

| Где | Что тянется | Ссылка |
| --- | --- | --- |
| [deploy_for_backend.yml](../.github/workflows/deploy_for_backend.yml), [deploy_for_go_backend.yml](../.github/workflows/deploy_for_go_backend.yml), [deploy_for_full_app.yml](../.github/workflows/deploy_for_full_app.yml) | Dockerfile и `.dockerignore` через `wget` с `raw.githubusercontent.com/.../master/...` | хардкод `master` |
| Все workflow'ы | composite actions `moogur/all-workflows/.github/actions/*@master` | хардкод `master` |
| [deploy_for_build_application.yml](../.github/workflows/deploy_for_build_application.yml), [release_frontend.yml](../.github/workflows/release_frontend.yml) | `actions/*-release@master` / `@main` | сторонние actions |

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

## Исправлено

- **Кэш `node_modules` + пропуск `npm ci`** → перешли на `actions/setup-node` с `cache: 'npm'` (кэш `~/.npm`) и безусловный `npm ci` через общий action [`setup-node`](actions.md). Каталог `node_modules` больше не кэшируется.
- **`npm i` → `npm ci`** в [deploy_for_lerna.yml](../.github/workflows/deploy_for_lerna.yml).
- **`wget @master` для kanboard-скрипта** → [kanboard.yml](../.github/workflows/kanboard.yml) теперь берёт `scripts/kanboard_requests.sh` через `actions/checkout` репозитория `all-workflows`, запиненный к `github.job_workflow_sha` (версия вызванного workflow), без обращения к `raw.githubusercontent`.
- **Shebang хука `.husky/commit-msg`** → `#!/usr/bin/env bash` (портативно).
- **Word-splitting в `scripts/kanboard_requests.sh`** → все аргументы закавычены, `shellcheck` проходит строго без исключений.

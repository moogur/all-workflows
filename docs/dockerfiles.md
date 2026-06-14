# Dockerfile'ы

В каталоге [`dockerfiles/`](../dockerfiles/) лежат шаблоны Dockerfile и `.dockerignore`, которые Docker-workflow'ы **скачивают на лету** во время сборки (через `wget` с `raw.githubusercontent.com`) и кладут в корень собираемого проекта под именами `Dockerfile` и `.dockerignore`.

← Назад к [README](../README.md) · [Справочник workflow'ов](workflows.md)

> ⚠️ Известные проблемы этих Dockerfile'ов (отсутствие `make` в `golang:alpine`,
> рантайм без `node_modules`, scratch без CA-сертификатов и др.) собраны в
> [modernization.md → Dockerfiles](modernization.md#dockerfiles).

## Зачем так сделано

Dockerfile'ы хранятся централизованно в этом репозитории, а не дублируются в каждом проекте. Workflow подставляет версии через build-args, поэтому один шаблон подходит для проектов с разными версиями Node/Go.

Передаваемые build-args:

- `ARG_NODE_VERSION` — версия Node.js (из `package.json` проекта);
- `ARG_GO_VERSION` — версия Go (из `go.mod` проекта);
- `ARG_APP_VERSION` — версия приложения (из git-тега), пробрасывается в образ как переменная окружения `APP_VERSION`.

## Файлы

### `deploy_backend.dockerfile` — Node.js-бэкенд

Многоступенчатая сборка на `node:<version>-alpine`:

1. **builder**: `npm ci` → `npm run build`;
2. **runtime**: копирует только `dist`, задаёт `APP_VERSION`, запускает `node dist/index.js`.

Используется в [`deploy_for_backend.yml`](../.github/workflows/deploy_for_backend.yml). Требует `.npmrc` (создаётся workflow'ом для доступа к приватному реестру).

### `deploy_go_backend.dockerfile` — Go-бэкенд

Многоступенчатая сборка:

1. **builder**: `golang:<version>-alpine`, статическая сборка бинарника из `/app/src` (`CGO_ENABLED=0`, `-ldflags "-s -w -extldflags '-static'"`);
2. **runtime**: `scratch` (минимальный образ), копирует один бинарник `/application`, задаёт `APP_VERSION`.

Используется в [`deploy_for_go_backend.yml`](../.github/workflows/deploy_for_go_backend.yml).

### `full_deploy.dockerfile` — Полное приложение (Go + Node.js)

Сборка приложения из двух частей:

1. **backend**: `golang:<version>-alpine`, `cd backend && make build`;
2. **frontend**: `node:<version>-alpine`, `cd frontend && npm ci && npm run build`;
3. **runtime**: `scratch`, копирует бинарник `/main` и каталог `/frontend` (собранный `dist`), запускает `/main`.

Используется в [`deploy_for_full_app.yml`](../.github/workflows/deploy_for_full_app.yml). Предполагает структуру проекта с папками `backend/` (с `Makefile`) и `frontend/`.

## `.dockerignore`

### `.dockerignore`

Полный список исключений для Node.js-сборки: `coverage`, `*.md`, конфиги IDE и линтеров, `.env`, `node_modules`, `test`, `dist`, файлы Nest и т. д. Скачивается workflow'ом [`deploy_for_backend.yml`](../.github/workflows/deploy_for_backend.yml).

### `.full.dockerignore`

Минимальный список исключений (`.git`, `.vscode`, конфиги, `Makefile`, `README.md`) для сборок Go и полного приложения. Скачивается workflow'ами [`deploy_for_go_backend.yml`](../.github/workflows/deploy_for_go_backend.yml) и [`deploy_for_full_app.yml`](../.github/workflows/deploy_for_full_app.yml).

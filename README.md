# all-workflows

Библиотека **переиспользуемых GitHub Actions workflow'ов** (reusable workflows) для проектов на Node.js и Go. Репозиторий содержит готовые пайплайны CI, релизов, сборки и публикации Docker-образов и npm-пакетов, а также вспомогательные Dockerfile'ы, скрипт интеграции с [Kanboard](https://kanboard.org/) и git-хук проверки сообщений коммитов.

Все workflow'ы вызываются из других репозиториев через [`workflow_call`](https://docs.github.com/en/actions/using-workflows/reusing-workflows) — их не запускают напрямую, а подключают в пайплайне вашего проекта.

## Что внутри

| Каталог / файл | Назначение |
| --- | --- |
| [`.github/workflows/`](.github/workflows/) | Переиспользуемые workflow'ы (основное содержимое репозитория) |
| [`.github/actions/`](.github/actions/) | Composite actions — общие шаги (версии Node/Go, настройка Node с кэшем npm, npm-аутентификация, версия приложения, теги docker-образа) |
| [`dockerfiles/`](dockerfiles/) | Dockerfile'ы и `.dockerignore`, которые workflow'ы скачивают на лету при сборке образов |
| [`scripts/kanboard_requests.sh`](scripts/kanboard_requests.sh) | Bash-библиотека JSON-RPC запросов к Kanboard |
| [`.husky/commit-msg`](.husky/commit-msg) | Git-хук валидации сообщения коммита |
| [`.github/release-drafter.yml`](.github/release-drafter.yml) | Конфигурация [Release Drafter](https://github.com/release-drafter/release-drafter) |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | CI самого репозитория: actionlint, shellcheck, yamllint, bats |
| [`tests/`](tests/) | Unit-тесты ([bats](https://github.com/bats-core/bats-core)) на bash-логику экшенов, хука и скриптов |
| [`Makefile`](Makefile) | Команды локальной разработки: `make check`/`lint`/`test` (повторяют CI), `make help` |

## Быстрый старт

Чтобы подключить workflow в своём репозитории, создайте файл в `.github/workflows/` и вызовите нужный пайплайн через `uses`:

```yaml
name: CI

on:
  push:
    branches: [master]

jobs:
  ci:
    uses: moogur/all-workflows/.github/workflows/actions_for_push.yml@master
    secrets: inherit
    with:
      skip_tests: 'false'
      folder: '.'
```

> Большинство workflow'ов используют `secrets.GITHUB_TOKEN` для доступа к приватному npm-реестру `@moogur` и GitHub Packages. Передавайте секреты через `secrets: inherit` либо явно.

## Обзор workflow'ов

Полный справочник со всеми входными параметрами и секретами — в [docs/workflows.md](docs/workflows.md).

### Проверки кода (CI)

| Workflow | Стек | Что делает |
| --- | --- | --- |
| [`actions_for_push.yml`](.github/workflows/actions_for_push.yml) | Node.js | Lint → build → test |
| [`actions_for_push_go.yml`](.github/workflows/actions_for_push_go.yml) | Go | `go vet`, `staticcheck`, `golint`, тесты |
| [`pr_annotation.yml`](.github/workflows/pr_annotation.yml) | Node.js | Аннотации покрытия Jest в Pull Request |
| [`pr_annotation_go.yml`](.github/workflows/pr_annotation_go.yml) | Go | Заготовка под аннотации тестов Go |

### Релизы и артефакты

| Workflow | Что делает |
| --- | --- |
| [`release.yml`](.github/workflows/release.yml) | Публикация GitHub-релиза через Release Drafter |
| [`release_frontend.yml`](.github/workflows/release_frontend.yml) | Релиз + сборка фронтенда и загрузка `application.zip` |
| [`release_with_artifacts.yml`](.github/workflows/release_with_artifacts.yml) | Релиз + загрузка ранее собранного `*.tar.gz` |
| [`go_build_with_artifacts.yml`](.github/workflows/go_build_with_artifacts.yml) | Сборка Go-бинарника и загрузка артефакта |
| [`deploy_for_build_application.yml`](.github/workflows/deploy_for_build_application.yml) | Сборка по скрипту + создание релиза с `application.zip` |

### Docker-образы

| Workflow | Стек | Что делает |
| --- | --- | --- |
| [`deploy_for_backend.yml`](.github/workflows/deploy_for_backend.yml) | Node.js | Сборка и публикация Docker-образа бэкенда |
| [`deploy_for_go_backend.yml`](.github/workflows/deploy_for_go_backend.yml) | Go | Сборка и публикация Docker-образа Go-бэкенда |
| [`deploy_for_full_app.yml`](.github/workflows/deploy_for_full_app.yml) | Go + Node.js | Сборка образа полного приложения (бэкенд + фронтенд) |
| [`deploy_for_docker_container.yml`](.github/workflows/deploy_for_docker_container.yml) | — | Сборка и публикация образа по локальному `Dockerfile` (теги: `date` или `semver`) |
| [`auto_deploy_for_docker_container.yml`](.github/workflows/auto_deploy_for_docker_container.yml) | — | Проверка обновлений во внешнем репозитории и автодеплой |
| [`auto_deploy_for_build_application.yml`](.github/workflows/auto_deploy_for_build_application.yml) | — | Проверка обновлений + сборка приложения |

### Публикация пакетов и фронтенда

| Workflow | Что делает |
| --- | --- |
| [`publish_package.yml`](.github/workflows/publish_package.yml) | Публикация npm-пакета в GitHub Packages |
| [`deploy_for_lerna.yml`](.github/workflows/deploy_for_lerna.yml) | Публикация пакетов монорепозитория через Lerna |
| [`deploy_for_frontend.yml`](.github/workflows/deploy_for_frontend.yml) | Сборка фронтенда и пуш `dist` в ветку `builds` |

### Интеграции

| Workflow | Что делает |
| --- | --- |
| [`kanboard.yml`](.github/workflows/kanboard.yml) | Перемещение задач по колонкам Kanboard в зависимости от события Git |

## Документация

- [docs/workflows.md](docs/workflows.md) — подробный справочник по каждому workflow: входные параметры, секреты, переменные, шаги.
- [docs/actions.md](docs/actions.md) — composite actions: общие шаги (версии Node/Go, npm-аутентификация, версия приложения).
- [docs/dockerfiles.md](docs/dockerfiles.md) — описание Dockerfile'ов и `.dockerignore`.
- [docs/kanboard.md](docs/kanboard.md) — интеграция с Kanboard и JSON-RPC скрипт.
- [docs/conventions.md](docs/conventions.md) — соглашения: формат коммитов, версионирование, секреты и переменные окружения.
- [docs/security.md](docs/security.md) — замечания по безопасности.
- [docs/testing.md](docs/testing.md) — тесты и валидация: что проверяется, как запускать, насколько можно доверять.
- [docs/modernization.md](docs/modernization.md) — отложенная модернизация (устаревшая инфраструктура, что стоит обновить).

## Соглашения (кратко)

- **Версия Node.js** берётся из поля `engines.node` в `package.json` проекта.
- **Версия Go** берётся из директивы `go` в `go.mod`.
- **Версия приложения** определяется по git-тегу (`git describe --tags`).
- **Docker-образы** публикуются в GitHub Packages (`docker.pkg.github.com`) с тегами `<версия>` и `latest`; в `deploy_for_docker_container` с `format_mode: 'semver'` — `vX.Y.Z`, `vX.Y`, `vX`, `latest`.
- **npm-пакеты** области `@moogur` ставятся из приватного реестра GitHub Packages.
- **Сообщения коммитов** проверяются хуком и должны иметь вид `[GA-123] type(scope): subject`.

Подробнее — в [docs/conventions.md](docs/conventions.md).

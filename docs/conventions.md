# Соглашения и настройки

Соглашения, на которые опираются workflow'ы: формат коммитов, версионирование, секреты, переменные окружения и конвенции именования.

← Назад к [README](../README.md) · [Справочник workflow'ов](workflows.md)

## Формат сообщений коммитов

Git-хук [`.husky/commit-msg`](../.husky/commit-msg) валидирует каждое сообщение коммита. Формат:

```text
[GA-<номер>] <type>(<scope>): <subject>
```

Пример: `[GA-557] feature(frontend): add deploy spa and pwa`

**Правила валидации:**

| Часть | Требования |
| --- | --- |
| Номер задачи | Строго `[GA-<цифры>]` (регэксп `^\[GA-[0-9]+\]$`) |
| `type` | Не пустой; одно из: `feature`, `bugfix`, `ci`, `config`, `refactor`, `test`, `docs` |
| `scope` | Не пустой; только нижний регистр |
| `subject` | Не пустой; нижний регистр; не длиннее 125 символов |

Валидируется только **заголовок** (первая строка): тело коммита — свободный текст, регистр и длина строк в нём не проверяются.

Хук подключается через [husky](https://typicode.github.io/husky/) (`npm run prepare` → `husky install`, см. `package.json`).

> Префикс `GA-` и номер задачи используются также интеграцией с Kanboard для определения `task_id` (см. [kanboard.md](kanboard.md)).

## Версионирование

- **Версия Node.js** для CI и Docker-сборок берётся из `engines.node` в `package.json` проекта (через composite action `detect-node-version`, см. [actions.md](actions.md)).
- **Версия Go** берётся из директивы `go` в `go.mod` (через `detect-go-version`).
- **Версия приложения / релиза** определяется по git-тегам через composite action `app-version` (см. [actions.md](actions.md)) со снятием параметризуемого префикса (по умолчанию `v`):
  - в релизах — режим `mode: ref` (тег из `GITHUB_REF`, инициировавший запуск);
  - в Docker-сборках и сборке приложения — режим `mode: git` (`git describe --tags --abbrev=0`);
  - для любой сборки без тега (расписание, ручной запуск) — `dd.mm.yyyy-HHMM-auto` по UTC (отдельная inline-логика в [deploy_for_docker_container.yml](../.github/workflows/deploy_for_docker_container.yml)); время в метке — чтобы две сборки за сутки не перезаписали друг друга. В semver-репозиториях такая сборка тоже уходит в формате `date`, чтобы не переписать релизные `vX.Y.Z`.
- **Формат git-тегов** зависит от репозитория и поддерживается в двух вариантах:
  - старый — дата, `dd.mm.yyyy` (например, `14.03.2026`);
  - новый — числовой, `vX.Y.Z` (например, `v1.0.0`); именно он ожидается при `format_mode: 'semver'`.

### Уровень версии в релизах

[Release Drafter](https://github.com/release-drafter/release-drafter) (конфиг [`.github/release-drafter.yml`](../.github/release-drafter.yml)) определяет инкремент версии по меткам PR:

| Уровень | Метки PR |
| --- | --- |
| major | `type:major` |
| minor | `type:feature`, `type:refactor`, `type:test` |
| patch | `type:bugfix`, `type:ci`, `type:config`, `type:docs` |

Категории в changelog: 🚀 New Features, 🐞 Bugs Fixes, 📚 Documentation, 🧰 Maintenance, 🛠 Configuration.

## Секреты

| Секрет | Где используется | Назначение |
| --- | --- | --- |
| `GITHUB_TOKEN` | большинство workflow'ов | Доступ к приватному npm-реестру `@moogur`, GitHub Packages, релизам |
| `KANBOARD_HOST` | `kanboard.yml` | URL инстанса Kanboard |
| `KANBOARD_USER` | `kanboard.yml` | Логин JSON-RPC API |
| `KANBOARD_TOKEN` | `kanboard.yml` | Токен JSON-RPC API |
| `UPDATE_VARIABLES_CLI_TOKEN` | `auto_deploy_*` | PAT для обновления переменной окружения через GitHub API |

Передавайте секреты в reusable workflow через `secrets: inherit` или явным списком `secrets:`.

## Права `GITHUB_TOKEN`

Каждый переиспользуемый workflow объявляет `permissions` явно — минимально необходимый набор вместо дефолта репозитория-потребителя.

| Workflow | Права |
| --- | --- |
| `actions_for_push` | `contents: read`, `packages: read` |
| `actions_for_push_go`, `pr_annotation_go`, `go_build_with_artifacts`, `kanboard` | `contents: read` |
| `pr_annotation` | `contents: read`, `packages: read`, `pull-requests: write`, `checks: write` |
| `publish_package`, `deploy_for_lerna` | `contents: read`, `packages: write` |
| `deploy_for_backend`, `deploy_for_go_backend`, `deploy_for_full_app`, `deploy_for_docker_container` | `contents: read`, `packages: write` |
| `deploy_for_frontend` | `contents: write`, `packages: read` |
| `deploy_for_build_application` | `contents: write` |
| `release`, `release_with_artifacts` | `contents: write`, `pull-requests: read` |
| `release_frontend` | `contents: write`, `packages: read`, `pull-requests: read` |
| `auto_deploy_for_docker_container` | `contents: read`, `packages: write` |
| `auto_deploy_for_build_application` | `contents: write` |

> Вызванный workflow не может получить больше прав, чем есть у вызвавшего, поэтому у `auto_deploy_*` права не уже, чем у вложенных в них деплоев. Если в репозитории-потребителе дефолтный токен урезан до read-only, запуск упадёт сразу и с внятной причиной, а не на шаге `docker push`.

## Переменные окружения (vars)

| Переменная | Где используется | Назначение |
| --- | --- | --- |
| `LAST_UPDATE_VALUE` | `auto_deploy_*` | Хранит «последнюю увиденную» версию/время коммита отслеживаемого репозитория в рамках GitHub Environment. Сравнивается для принятия решения о деплое; записывается через API только после успешного деплоя, при первом запуске создаётся автоматически |

## Приватный npm-реестр

Пакеты области `@moogur` устанавливаются из GitHub Packages. Аутентификация настраивается единообразно через composite action `npm-auth` (см. [actions.md](actions.md)), который создаёт `.npmrc`:

```ini
@moogur:registry=https://npm.pkg.github.com/
//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}
```

## Реестр Docker-образов

Образы публикуются в GitHub Packages:

```text
docker.pkg.github.com/<github_user>/<repo>/<repo>:<version>
docker.pkg.github.com/<github_user>/<repo>/<repo>:latest
```

`<github_user>` задаётся параметром `github_user` (по умолчанию `$GITHUB_ACTOR`), `<repo>` — `github.event.repository.name`.

Набор тегов формирует composite action [`docker-tags`](actions.md#docker-tags). В [deploy_for_docker_container.yml](../.github/workflows/deploy_for_docker_container.yml) он выбирается параметром `format_mode`:

| `format_mode` | Теги образа |
| --- | --- |
| `date` (по умолчанию) | `<version>`, `latest` |
| `semver` | `vX.Y.Z`, `vX.Y`, `vX`, `latest` |

Подвижные `vX` и `vX.Y` перезаписываются каждым новым патчем: потребитель может закрепиться на мажоре (`:v1`) или миноре (`:v1.2`) и получать обновления автоматически. Остальные Docker-workflow'ы (`deploy_for_backend`, `deploy_for_go_backend`, `deploy_for_full_app`) публикуют только `<version>` и `latest`.

## Стиль кода

[`.editorconfig`](../.editorconfig): UTF-8, отступ 2 пробела, LF, финальная пустая строка, обрезка хвостовых пробелов, максимальная длина строки 120.

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

Хук подключается через [husky](https://typicode.github.io/husky/) (`npm run prepare` → `husky install`, см. `package.json`).

> Префикс `GA-` и номер задачи используются также интеграцией с Kanboard для определения `task_id` (см. [kanboard.md](kanboard.md)).

## Версионирование

- **Версия Node.js** для CI и Docker-сборок берётся из `engines.node` в `package.json` проекта (через composite action `detect-node-version`, см. [actions.md](actions.md)).
- **Версия Go** берётся из директивы `go` в `go.mod` (через `detect-go-version`).
- **Версия приложения / релиза** определяется по git-тегам через composite action `app-version` (см. [actions.md](actions.md)) со снятием параметризуемого префикса (по умолчанию `v`):
  - в релизах — режим `mode: ref` (тег из `GITHUB_REF`, инициировавший запуск);
  - в Docker-сборках и сборке приложения — режим `mode: git` (`git describe --tags --abbrev=0`);
  - для авто-деплоя без тега — `dd.mm.yyyy-auto` (отдельная inline-логика в [deploy_for_docker_container.yml](../.github/workflows/deploy_for_docker_container.yml)).

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

## Переменные окружения (vars)

| Переменная | Где используется | Назначение |
| --- | --- | --- |
| `LAST_UPDATE_VALUE` | `auto_deploy_*` | Хранит «последнюю увиденную» версию/время коммита отслеживаемого репозитория в рамках GitHub Environment. Сравнивается для принятия решения о деплое и обновляется через API |

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

## Стиль кода

[`.editorconfig`](../.editorconfig): UTF-8, отступ 2 пробела, LF, финальная пустая строка, обрезка хвостовых пробелов, максимальная длина строки 120.

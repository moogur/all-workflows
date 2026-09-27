# Соглашения и настройки

Соглашения, на которые опираются workflow'ы: формат коммитов, версионирование, секреты, переменные окружения и конвенции именования.

← Назад к [README](../README.md) · [Справочник workflow'ов](workflows.md)

## Форматы

Формат, разбор и преобразование каждого «базового значения» (версия/тег, заголовок коммита,
docker-ссылка, npm-пакет) живёт ровно в одном файле — [`lib/`](../lib/) — и оттуда подключается
через `source` во все места, которые с этим значением работают. Спецификация формата — в
заголовке самого файла, здесь она не повторяется:

- [`lib/version.sh`](../lib/version.sh) — версия/тег: дата `dd.mm.yyyy`, semver `vX.Y.Z`, метка авто-сборки;
- [`lib/tags.sh`](../lib/tags.sh) — «последний тег» и N последних тегов по дате создания;
- [`lib/commit.sh`](../lib/commit.sh) — заголовок коммита, типы, PR в git-истории, `task_id`;
- [`lib/docker.sh`](../lib/docker.sh) — имя docker-образа и ссылка `<образ>:<тег>`;
- [`lib/npm.sh`](../lib/npm.sh) — `имя@версия` опубликованного npm-пакета.

Guard-тест [`tests/formats.bats`](../tests/formats.bats) проверяет, что вне `lib/` эти форматы
не переизобретаются повторно.

## Формат сообщений коммитов

Git-хук [`.husky/commit-msg`](../.husky/commit-msg) валидирует каждое сообщение коммита поверх
общего формата [`lib/commit.sh`](../lib/commit.sh) (регэксп заголовка, точный список типов).
Этот репозиторий дополнительно требует префикс задачи ровно `GA` — `lib/commit.sh` сам по себе
допускает любой `[A-Z][A-Z0-9]*` (нужно потребителям вроде `release-notes`, которые живут со
своими префиксами: `GA-123`, `IPB-456`). Формат:

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
  - в релизах и в сборке приложения по тегу — режим `mode: ref` (тег из `GITHUB_REF`, инициировавший запуск);
  - в сборке приложения без тега (авто-деплой) релиз не считается вовсе: `deploy_for_build_application` без тега (`github.ref_type != 'tag'`) выполняет только сборочный скрипт и пропускает версию и релиз. Режим `mode: git` (`git describe --tags --abbrev=0`) у `app-version` остаётся в экшене для потребителей вне этого репозитория, но в его собственных workflow'ах сейчас не используется;
  - в Docker-сборках — тег, инициировавший запуск (`github.ref_name`, внутри [`docker-image`](actions.md#docker-image));
  - для любой сборки без тега (расписание, ручной запуск) — `dd.mm.yyyy-HHMM-auto` по UTC (в [`docker-image`](actions.md#docker-image)); время в метке — чтобы две сборки за сутки не перезаписали друг друга. В semver-репозиториях такая метка тоже датная и не переписывает релизные `vX.Y.Z`.
- **Формат git-тегов** проверяется общим action [`tag-format`](actions.md#tag-format) (используется в `docker-tags`, в [`github-release`](actions.md#github-release) — единой точке публикации релиза, и напрямую как ранний фейл-фаст в `release_frontend`/`deploy_for_build_application`, до сборки) и поддерживается ровно в двух вариантах — версия любого другого вида проваливает сборку/релиз:
  - дата, `dd.mm.yyyy` (например, `14.03.2026`), включая метки авто-сборки `dd.mm.yyyy-HHMM-auto` и `dd.mm.yyyy-auto`;
  - semver строго с префиксом `v`, `vX.Y.Z` (например, `v1.0.0`); по нему образ получает теги `vX.Y.Z`, `vX.Y`, `vX`. Тег без префикса (`1.2.3`) больше не принимается.

### Тело релиза

Отдельного «релизного» workflow нет: каждая сборка, у которой есть что опубликовать, по тегу вызывает
единую цепочку [`github-release`](actions.md#github-release), которая собирает тело автоматически —
Release Drafter в репозитории больше не используется.

[`release-notes`](actions.md#release-notes) собирает тело целиком из локальной git-истории
(`git log --first-parent`) — без обращений к GitHub API. PR, смёрженный кнопкой Merge либо сквошенный,
даёт одну запись **по PR**: заголовок берётся из истории (первая строка тела merge-коммита либо сам
subject сквош-коммита без суффикса `(#N)`) и разбирается по формату [`commit-msg`](#формат-сообщений-коммитов)
— категория по `type`, как у обычного коммита. Не подошёл под формат — категория `other`, заголовок как есть.

Коммит, запушенный напрямую (без PR — трунковая разработка в `master`), даёт запись **по коммиту**: заголовок
разбирается по тому же формату `commit-msg`. Несколько коммитов одного PR (squash, ребейз через Merge pull
request) `--first-parent` уже схлопывает в одну запись — по отдельности они в тело не попадают.

**Ограничение:** PR, смёрженный через rebase-merge (не через squash и не через кнопку Merge pull request),
в git-истории неотличим от серии прямых коммитов — каждый его коммит даёт свою запись по коммиту, а не одну
запись по PR.

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
| `actions_for_push_go`, `kanboard` | `contents: read` |
| `pr_annotation` | `contents: read`, `packages: read`, `pull-requests: write`, `checks: write` |
| `deploy_for_frontend` | `contents: write`, `packages: read` |
| `deploy_for_backend`, `deploy_for_go_backend`, `deploy_for_full_app`, `deploy_for_docker_container` | `contents: write`, `packages: write` — по тегу релизит `docker-image` (`docker-release` → `github-release`) |
| `deploy_for_build_application`, `go_build_with_artifacts` | `contents: write` — по тегу релизят через `github-release` |
| `release_frontend` | `contents: write`, `packages: read` — по тегу релизит через `github-release` |
| `publish_package`, `deploy_for_lerna` | `contents: write`, `packages: write` — по тегу релизят через `github-release` |
| `auto_deploy_for_docker_container` | `contents: write`, `packages: write` |
| `auto_deploy_for_build_application` | `contents: write` |

> Вызванный workflow не может получить больше прав, чем есть у вызвавшего, поэтому у `auto_deploy_*` права не уже, чем у вложенных в них деплоев. Если в репозитории-потребителе дефолтный токен урезан до read-only, запуск упадёт сразу и с внятной причиной, а не на шаге `docker push`.

## Выключатель тестов

Шаг с тестами в переиспользуемом workflow всегда закрыт условием `inputs.skip_tests`, а сам вход объявлен как `required: false` с `default: 'false'`. Решение принимает потребитель: ничего не передал — тесты идут, передал `skip_tests: 'true'` — шаг пропускается. Тесты нигде не выключаются правкой самого workflow и не комментируются.

Сейчас так устроены [`actions_for_push.yml`](workflows.md#actions_for_pushyml--lint-build-test-nodejs), [`actions_for_push_go.yml`](workflows.md#actions_for_push_goyml--lint-build-test-go) и [`pr_annotation.yml`](workflows.md#pr_annotationyml--аннотации-покрытия-jest). Правило закреплено guard-тестом [tests/skip-tests.bats](../tests/skip-tests.bats): он же ловит и обратную ошибку — вход `skip_tests` без шага, который им закрыт.

Линтеры и сборка выключателя не имеют намеренно: `npm run lint`, `go vet`, `staticcheck` и `golint` идут всегда.

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

Набор тегов формирует composite action [`docker-tags`](actions.md#docker-tags). Формат определяется по самой версии:

| Версия | Теги образа |
| --- | --- |
| дата `dd.mm.yyyy`, метка `dd.mm.yyyy-HHMM-auto` | `<version>`, `latest` |
| `vX.Y.Z` (или `X.Y.Z`) | `vX.Y.Z`, `vX.Y`, `vX`, `latest` |
| что-то другое | ошибка, сборка падает |

Подвижные `vX` и `vX.Y` перезаписываются каждым новым патчем: потребитель может закрепиться на мажоре (`:v1`) или миноре (`:v1.2`) и получать обновления автоматически. Правило одно для всех Docker-workflow'ов.

## Стиль кода

[`.editorconfig`](../.editorconfig): UTF-8, отступ 2 пробела, LF, финальная пустая строка, обрезка хвостовых пробелов, максимальная длина строки 120.

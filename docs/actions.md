# Composite actions

Повторяющиеся шаги вынесены в переиспользуемые [composite actions](https://docs.github.com/en/actions/creating-actions/creating-a-composite-action) в каталоге [`.github/actions/`](../.github/actions/). Это убирает дублирование: версия Node/Go, npm-аутентификация и определение версии приложения описаны один раз.

← Назад к [README](../README.md) · [Справочник workflow'ов](workflows.md)

## Почему composite actions, а не отдельные `.sh`-файлы

Workflow'ы вызываются через `workflow_call` из чужих репозиториев, и `actions/checkout` забирает репозиторий **вызывающего**. Поэтому простой bash-файл из `scripts/` в рабочей директории недоступен — его нужно отдельно получать (например, `actions/checkout` этого репозитория в подпапку, как сделано для Kanboard). Composite action же GitHub скачивает автоматически по полному пути `owner/repo/path@ref`, и при этом сохраняется штатная работа с `$GITHUB_OUTPUT`.

Во всех workflow'ах actions подключаются как:

```yaml
uses: moogur/all-workflows/.github/actions/<name>@master
```

> Ссылка на `@master` оставлена намеренно (см. [modernization.md](modernization.md)).

## `detect-node-version`

Считывает версию Node.js из `engines.node` в `package.json`.

| | |
| --- | --- |
| **Входы** | `working-directory` (необяз., по умолчанию `.`) — каталог с `package.json` |
| **Выходы** | `version` — версия Node.js |

```yaml
- id: node
  uses: moogur/all-workflows/.github/actions/detect-node-version@master
- uses: actions/setup-node@v4
  with:
    node-version: ${{ steps.node.outputs.version }}
```

## `detect-go-version`

Считывает версию Go из директивы `go` в `go.mod`.

| | |
| --- | --- |
| **Входы** | `working-directory` (необяз., по умолчанию `.`) — каталог с `go.mod` |
| **Выходы** | `version` — версия Go |

## `setup-node`

Готовит окружение Node.js для npm-сборок: определяет версию (через [`detect-node-version`](#detect-node-version)), ставит Node и включает **кэш npm** (`~/.npm`) средствами `actions/setup-node` (`cache: 'npm'`).

| | |
| --- | --- |
| **Входы** | `cache-dependency-path` (необяз., по умолчанию `package-lock.json`) — путь к lock-файлу для ключа кэша |
| **Выходы** | `version` — версия Node.js |

```yaml
- uses: moogur/all-workflows/.github/actions/setup-node@master
- uses: moogur/all-workflows/.github/actions/npm-auth@master
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
- run: npm ci
```

Используется в npm-workflow'ах ([actions_for_push](../.github/workflows/actions_for_push.yml), [pr_annotation](../.github/workflows/pr_annotation.yml), [publish_package](../.github/workflows/publish_package.yml), [release_frontend](../.github/workflows/release_frontend.yml), [deploy_for_frontend](../.github/workflows/deploy_for_frontend.yml), [deploy_for_lerna](../.github/workflows/deploy_for_lerna.yml)).

> **Почему так, а не кэш `node_modules`.** Раньше кэшировался каталог `node_modules`, а при попадании в кэш `npm ci` пропускался. Это быстрее на «тёплом» кэше, но небезопасно: ключ кэша не включал версию Node (риск битых нативных модулей при смене ABI), не запускались lifecycle-скрипты и не было сверки с lock-файлом. Текущий подход — кэш скачанных тарболов (`~/.npm`) и **всегда** `npm ci`: чистая, воспроизводимая, проверенная установка; проигрыш по времени обычно небольшой.

## `npm-auth`

Создаёт `.npmrc` для приватного scope `@moogur` в GitHub Packages. **Единый подход** к npm-аутентификации (раньше в разных workflow'ах было два способа — `npm set` и ручная генерация `.npmrc`).

| | |
| --- | --- |
| **Входы** | `token` (обяз.) — токен с `read:packages`, обычно `GITHUB_TOKEN`; `working-directory` (необяз., по умолчанию `.`) — где создать `.npmrc` |
| **Выходы** | — |

```yaml
- uses: moogur/all-workflows/.github/actions/npm-auth@master
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    working-directory: frontend   # например, для монорепозитория
```

Создаёт файл:

```ini
@moogur:registry=https://npm.pkg.github.com/
//npm.pkg.github.com/:_authToken=<token>
```

## `app-version`

Определяет версию приложения из git-тега и снимает префикс. Поддерживает **два режима работы** (`mode`) и **параметризуемый префикс** (`#v` остаётся поведением по умолчанию).

| | |
| --- | --- |
| **Входы** | `mode` (необяз., по умолчанию `git`) — источник версии; `prefix` (необяз., по умолчанию `v`) — снимаемый префикс тега, пустая строка — оставить тег как есть |
| **Выходы** | `version` — версия приложения |

**Режимы (`mode`):**

| Значение | Источник | Когда использовать |
| --- | --- | --- |
| `git` | `git describe --tags --abbrev=0` — последний тег в истории | Docker-сборки, сборка приложения. Требует `fetch-depth: 0` в `actions/checkout` |
| `ref` | `GITHUB_REF` — тег, инициировавший запуск | Релизные workflow'ы, запускаемые по `push` тега |

```yaml
# режим git, v1.2.3 -> 1.2.3 (по умолчанию)
- id: version
  uses: moogur/all-workflows/.github/actions/app-version@master

# режим ref — тег, инициировавший запуск (для релизов по тегу)
- id: version
  uses: moogur/all-workflows/.github/actions/app-version@master
  with:
    mode: ref

# тег как есть, без снятия префикса
- id: version
  uses: moogur/all-workflows/.github/actions/app-version@master
  with:
    prefix: ''
```

> В режиме `git` требуется полная история тегов: в шаге `actions/checkout` должно стоять `fetch-depth: 0`.
> Режим `ref` используют релизные workflow'ы ([release.yml](../.github/workflows/release.yml), [release_frontend.yml](../.github/workflows/release_frontend.yml), [release_with_artifacts.yml](../.github/workflows/release_with_artifacts.yml)).

# Composite actions

Повторяющиеся шаги вынесены в переиспользуемые [composite actions](https://docs.github.com/en/actions/creating-actions/creating-a-composite-action) в каталоге [`.github/actions/`](../.github/actions/). Это убирает дублирование: версия Node/Go, npm-аутентификация, определение версии приложения, формирование тегов docker-образа и проверка обновлений внешнего репозитория описаны один раз.

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

## `docker-tags`

Формирует полный список тегов docker-образа по версии сборки. Поддерживает **два формата** (`format_mode`): старый (`date`) и семантический (`semver`).

| | |
| --- | --- |
| **Входы** | `image` (обяз.) — имя образа без тега; `version` (обяз.) — версия сборки (git-тег как есть либо `dd.mm.yyyy-auto`); `format_mode` (необяз., по умолчанию `date`) — формат тегов |
| **Выходы** | `tags` — полные ссылки `<image>:<tag>`, разделённые пробелом |

**Форматы (`format_mode`):**

| Значение | Теги образа | Когда использовать |
| --- | --- | --- |
| `date` | `<version>`, `latest` | Старое поведение (тег-дата `14.03.2026`, метка авто-деплоя `dd.mm.yyyy-auto`). Формат по умолчанию — обратная совместимость |
| `semver` | `vX.Y.Z`, `vX.Y`, `vX`, `latest` | Репозитории с числовыми тегами `vX.Y.Z`: подвижные `vX` / `vX.Y` дают «последний патч мажора/минора» |

```yaml
- id: tags
  uses: moogur/all-workflows/.github/actions/docker-tags@master
  with:
    image: docker.pkg.github.com/user/repo/repo
    version: v1.2.3
    format_mode: semver
# tags = ...:v1.2.3 ...:v1.2 ...:v1 ...:latest

- run: |
    build_args=()
    for ref in ${{ steps.tags.outputs.tags }}; do build_args+=(-t "$ref"); done
    docker build "${build_args[@]}" .
```

> Формат выбирает вызывающий workflow: [deploy_for_docker_container](../.github/workflows/deploy_for_docker_container.yml)
> передаёт `semver` только для сборки по тегу, а сборке без тега всегда ставит `date`.
> В режиме `semver` префикс `v` в теги образа добавляется всегда, даже если git-тег был без него (`1.2.3` → `v1.2.3`).
> Тег, не подходящий под `vX.Y.Z` (дата, предрелиз `v1.2.3-rc.1`, неполная версия), в режиме `semver` — ошибка: сборка падает вместо публикации мусорных тегов.

Используется в [deploy_for_docker_container](../.github/workflows/deploy_for_docker_container.yml).

## `remote-update-check`

Считывает **маркер свежести** внешнего репозитория — по нему авто-деплой решает, появилось ли что-то новое.
Используется в [auto_deploy_for_docker_container](../.github/workflows/auto_deploy_for_docker_container.yml)
и [auto_deploy_for_build_application](../.github/workflows/auto_deploy_for_build_application.yml).

| | |
| --- | --- |
| **Входы** | `repository_url` (обяз.) — URL отслеживаемого репозитория; `type` (необяз., по умолчанию `commit`) — критерий новизны; `repository_branch` (необяз., по умолчанию `master`) — ветка для `type=commit` |
| **Выходы** | `value` — маркер свежести |

**Критерии (`type`):**

| Значение | Маркер | Как считается |
| --- | --- | --- |
| `commit` | unix-время последнего коммита ветки | `git clone --depth=1` нужной ветки и `git log -1 --format=%ct` |
| `tag` | имя самого свежего тега | bare-клон без блобов (`--filter=blob:none`) и `git for-each-ref --sort=-creatordate --count=1` |

> В режиме `tag` берётся **самый свежий тег по дате создания**, а не максимальный по имени: сортировка по имени
> врёт на любых неверсионных тегах — среди датных тегов «максимумом» окажется `26.05.2023`, потому что `26 > 14`,
> а год в сравнение не попадает. Формат имени тега при этом не важен: годятся и `v1.2.3`, и `14.03.2026`, и `nightly`.
> `git ls-remote` дат не отдаёт, поэтому нужен клон — но без блобов, только рефы и история
> (для `vrana/adminer` это ~1.5 с). Если тегов нет вовсе — ошибка, а не пустое значение.
>
> Маркеру не нужно быть «наибольшей версией» — ему достаточно **меняться** при появлении нового тега. Обратная
> сторона: предрелизный тег апстрима тоже сдвинет маркер и вызовет пересборку (лишнюю, но не ошибочную).
> Своего репозитория action не требует: `actions/checkout` перед ним не нужен.

## `save-update-value`

Записывает значение в переменную GitHub Environment: обновляет существующую (`PATCH`), а если переменной ещё
нет — создаёт (`POST`). Отдельный шаг нужен потому, что `PATCH` умеет только обновлять и на первом запуске
в новом Environment отвечает 404.

| | |
| --- | --- |
| **Входы** | `environment` (обяз.) — имя GitHub Environment; `name` (обяз.) — имя переменной; `value` (обяз.) — значение; `token` (обяз.) — PAT с правом записи переменных |
| **Выходы** | — |

```yaml
- uses: moogur/all-workflows/.github/actions/save-update-value@master
  with:
    environment: DEPLOY
    name: LAST_UPDATE_VALUE
    value: ${{ needs.checking_to_use_the_latest_version.outputs.last_update_value }}
    token: ${{ secrets.UPDATE_VARIABLES_CLI_TOKEN }}
```

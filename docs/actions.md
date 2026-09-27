# Composite actions

Повторяющиеся шаги вынесены в переиспользуемые [composite actions](https://docs.github.com/en/actions/creating-actions/creating-a-composite-action) в каталоге [`.github/actions/`](../.github/actions/). Это убирает дублирование: версия Node/Go, npm-аутентификация, определение версии приложения, тело релиза по PR/коммитам, публикация релиза (и единая цепочка публикации GitHub-релиза целиком), сборка docker-образа и релиз по тегу сборки, блок `npm install` и проверка обновлений внешнего репозитория описаны один раз.

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
| `git` | `git describe --tags --abbrev=0` — последний тег в истории | Версия нужна не по тегу push'а. Требует `fetch-depth: 0` в `actions/checkout`. В workflow'ах этого репозитория сейчас не используется — `deploy_for_build_application` без тега (авто-деплой) больше не считает версию и не релизит вовсе |
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
> Режим `ref` использует [`github-release`](#github-release) — единая точка публикации релиза.

## `release-notes`

Собирает тело GitHub-релиза из коммитов между текущим и предыдущим тегом. Коммит, смёрженный через Pull
Request, даёт одну запись **по PR** (заголовок, автор, категория по меткам PR — GitHub API, `gh api
repos/<repo>/commits/<sha>/pulls`); коммит, запушенный напрямую, — запись **по коммиту** (заголовок разбирается
по формату `commit-msg`). Используется только внутри [`github-release`](#github-release).

| | |
| --- | --- |
| **Входы** | `tag` (необяз., по умолчанию пусто) — тег релиза, пусто — тег из `GITHUB_REF`; `previous_tag` (необяз.) — с чем сравнивать, пусто — соседний тег по дате создания; `notes_file` (необяз.) — куда записать тело, пусто — `$RUNNER_TEMP/release-notes.md`; `token` (необяз., по умолчанию пусто) — токен для поиска PR коммита (`pull-requests: read`), пусто — тело только из коммитов |
| **Выходы** | `notes_file` — путь к файлу с телом релиза; `previous_tag` — тег, с которым сравнивали (пусто, если релиз первый); `commit_count` — число коммитов в диапазоне без слияний |

```yaml
- name: 'Checkout'
  uses: actions/checkout@v7
  with:
    fetch-depth: 0           # нужны вся история и теги

- id: notes
  uses: moogur/all-workflows/.github/actions/release-notes@master
  with:
    token: ${{ secrets.GITHUB_TOKEN }}

- env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    TAG: ${{ github.ref_name }}
    NOTES_FILE: ${{ steps.notes.outputs.notes_file }}
  run: gh release create "$TAG" --title "$TAG" --notes-file "$NOTES_FILE"
```

**Коммит, смёрженный через PR.** Для каждого коммита диапазона экшен спрашивает GitHub, к какому PR он
относится (`gh api .../commits/<sha>/pulls`, берётся смёрженный). Несколько коммитов одного PR (squash из
веб-интерфейса, ребейз) дают одну запись — дедупликация по номеру PR. Категория — по меткам PR (тот же
список, что раньше жил в `.github/release-drafter.yml`):

| Категория | Метка PR |
| --- | --- |
| 🚀 New Features | `type:feature`, `type:test` |
| 🐞 Bugs Fixes | `type:bugfix` |
| 📚 Documentation | `type:docs` |
| 🧰 Maintenance | `type:refactor` |
| 🛠 Configuration | `type:config`, `type:ci` |
| 🧩 Other | без ни одной из этих меток |

Запись: `- <заголовок PR> (#<номер>) @<автор>`.

**Коммит без PR (запушен напрямую).** Заголовок читается по формату хука [`commit-msg`](conventions.md#формат-сообщений-коммитов)
(`[GA-123] type(scope): subject`) и раскладывается по тем же категориям, но по `type` коммита (`feature`/`test` →
New Features и т. д., как в таблице выше). Префикс задачи может быть любым (`GA-123`, `IPB-456`): у каждого
репозитория-потребителя свой, и экшен принимает `[<ПРЕФИКС>-<номер>]`. Запись: `- [GA-557] frontend: add deploy
spa and pwa (a1b2c3d)`. Заголовок не по формату (старые коммиты, merge из веб-интерфейса) идёт в Other как есть.

Результат — заголовок `# What's Changed`, строка с числом коммитов («**3 commits** since `v1.2.2`.»),
категории с записями (PR и/или коммиты вперемешку, в порядке истории) и ссылка `**Full Changelog**` на
сравнение тегов.

> **Нет `token`, `GITHUB_REPOSITORY` или `gh` в `PATH` — тело собирается только из коммитов**, с одним
> предупреждением в лог (не на каждый коммит). Это и держит рабочими локальные прогоны и тесты без сети:
> без токена экшен даже не пытается звать `gh`.
>
> **Предыдущий тег берётся соседним по дате создания** (`git for-each-ref --sort=-creatordate`), а не
> максимальным по имени: сортировка по имени врёт на датных тегах — «максимумом» окажется `26.05.2023`,
> потому что `26 > 14` (та же причина, что и в [`remote-update-check`](#remote-update-check)).
> Слияния (`--no-merges`) в тело не идут; если предыдущего тега нет, берётся вся история, а ссылка
> ведёт на `/commits/<тег>`. Тега нет в репозитории — ошибка с подсказкой про `fetch-depth: 0`,
> потому что без полной истории диапазон посчитать нечем.
>
> **Риск:** запрос к GitHub API идёт на каждый коммит диапазона (не пачкой) — большой диапазон коммитов
> между тегами может упереться в лимит запросов API.

## `publish-release`

Публикует GitHub-релиз по тегу и прикладывает ассеты. **Идемпотентен**: если релиз по тегу уже есть — обновляет
его, а не падает, поэтому перезапуск упавшего job'а безопасен. **Устойчив к гонке параллельных job'ов матрицы**
за один и тот же тег (см. ниже). Используется только внутри [`github-release`](#github-release).

| | |
| --- | --- |
| **Входы** | `tag` (обяз.) — тег релиза; `title` (необяз.) — заголовок, пусто — не трогать существующий, а при создании взять имя тега; `notes_file` (необяз.) — файл с телом, пусто — не трогать существующее тело; `assets` (необяз.) — пути к файлам через пробел; `token` (обяз.) — токен с `contents: write` |
| **Выходы** | — |

```yaml
- id: notes
  uses: moogur/all-workflows/.github/actions/release-notes@master

- uses: moogur/all-workflows/.github/actions/publish-release@master
  with:
    tag: ${{ github.ref_name }}
    notes_file: ${{ steps.notes.outputs.notes_file }}
    assets: ./application.zip
    token: ${{ secrets.GITHUB_TOKEN }}
```

> **Пустые входы значат «не трогать».** При создании флаги обязательны: без `--notes` `gh` в неинтерактивном
> режиме не работает, поэтому пустое тело задаётся явно (`--notes ''`). При правке существующего релиза
> обновляется только то, что передали явно — пустой `title`/`notes_file` значит «здесь править нечего».
>
> Ассеты грузятся с `--clobber` — перезапуск заменяет файл, а не спотыкается об уже загруженный. Имя ассета
> у `gh` — это имя файла: чтобы опубликовать его под другим именем, файл нужно переименовать (так делает
> [`go_build_with_artifacts.yml`](../.github/workflows/go_build_with_artifacts.yml) — добавляет `goos`/`goarch`).
>
> **Правка существующего релиза снимает draft** (`--draft=false`): удаление git-тега переводит его GitHub-релиз
> в draft, а повторный пуш того же тега находит именно его через `gh release view`. Флаг добавляется, только
> когда правка вообще происходит (`title` или `notes_file` непустые) — в ветке «менять нечего» лишнего вызова
> `gh` как не было, так и нет.
>
> **Гонка параллельных job'ов матрицы.** `gh release view` перед созданием не гарантирует эксклюзивности:
> два job'а одной матрицы (например, `go_build_with_artifacts` для разных `goos`/`goarch`) могут оба не найти
> релиз и оба попытаться его создать — второй `gh release create` упадёт («already exists»). В этом случае
> экшен перепроверяет `gh release view`: релиз нашёлся — доделывает как `edit` (или ничего не делает, если
> нечего менять) вместо падения; не нашёлся — падает с ошибкой (значит, дело не в гонке).
>
> Заменяет заархивированные `actions/create-release` и `actions/upload-release-asset` (см. [modernization.md](modernization.md)).

## `github-release`

**Единая цепочка публикации GitHub-релиза** — единственный способ создать релиз в этом репозитории.
Проверяет формат тега, собирает тело из PR/коммитов, опционально дописывает готовый markdown-блок,
публикует релиз с ассетами. Вызывается по тегу (`if: github.ref_type == 'tag'`) из каждого workflow,
который что-то публикует: [`deploy_for_build_application`](../.github/workflows/deploy_for_build_application.yml),
[`release_frontend`](../.github/workflows/release_frontend.yml),
[`go_build_with_artifacts`](../.github/workflows/go_build_with_artifacts.yml),
[`publish_package`](../.github/workflows/publish_package.yml),
[`deploy_for_lerna`](../.github/workflows/deploy_for_lerna.yml), а также из [`docker-release`](#docker-release).

| | |
| --- | --- |
| **Входы** | `tag` (обяз.) — тег релиза; `extra_notes` (необяз.) — markdown-блок, дописываемый после автособранного тела, пусто — ничего не дописывать; `assets` (необяз.) — пути к файлам через пробел; `title` (необяз.) — заголовок релиза; `token` (обяз.) — токен с `contents: write` и `pull-requests: read` |
| **Выходы** | — |

```yaml
- uses: moogur/all-workflows/.github/actions/github-release@master
  with:
    tag: ${{ github.ref_name }}
    assets: ./application.zip
    token: ${{ secrets.GITHUB_TOKEN }}
```

**Шаги:** [`tag-format`](#tag-format) → [`release-notes`](#release-notes) → (если `extra_notes` непустой)
дописывание блока в файл тела → [`publish-release`](#publish-release).

> Это единственное производственное место, которое вызывает `release-notes` и `publish-release` — обе
> проверяются напрямую своими тестами, а composite-цепочка между ними самими тестами не покрыта (собрана из
> уже покрытых экшенов).

## `tag-format`

Определяет формат git-тега/версии: дата или semver; версия другого вида — ошибка. Единая точка правды для формата тегов, которую используют и сборка docker-образов, и релизы.

| | |
| --- | --- |
| **Входы** | `version` (обяз.) — версия для проверки (git-тег) |
| **Выходы** | `format` — `date` или `semver` |

**Форматы:**

| Версия | `format` | Примечание |
| --- | --- | --- |
| `14.03.2026`, `14.03.2026-0930-auto`, `14.03.2026-auto` | `date` | Дата и метки авто-сборки |
| `v1.2.3` | `semver` | Только с префиксом `v`; без него (`1.2.3`) — ошибка |

```yaml
- id: format
  uses: moogur/all-workflows/.github/actions/tag-format@master
  with:
    version: ${{ github.ref_name }}
# format = semver
```

> Дата проверяется первой: `14.03.2026` подходит и под `X.Y.Z` без префикса.
> Версия, не подходящая ни под один формат (предрелиз `v1.2.3-rc.1`, неполная версия `v1.2`, `2026-03-14`, тег без `v`, произвольная строка), — ошибка: сборка/релиз падает вместо публикации мусорных тегов.

Используется в [`docker-tags`](#docker-tags) и в [`github-release`](#github-release) — там тег проверяется до создания релиза.

## `docker-tags`

Формирует полный список тегов docker-образа по версии сборки. Формат версии определяет [`tag-format`](#tag-format) (шаг внутри этого экшена); сама сборка списка тегов по формату не переопределяет.

| | |
| --- | --- |
| **Входы** | `image` (обяз.) — имя образа без тега; `version` (обяз.) — версия сборки (git-тег как есть либо `dd.mm.yyyy-HHMM-auto`) |
| **Выходы** | `tags` — полные ссылки `<image>:<tag>`, разделённые пробелом |

**Форматы:**

| Версия | Теги образа | Примечание |
| --- | --- | --- |
| дата: `14.03.2026`, `14.03.2026-0930-auto`, `14.03.2026-auto` | `<version>`, `latest` | Теги-даты и метки авто-сборки |
| semver: `v1.2.3` | `vX.Y.Z`, `vX.Y`, `vX`, `latest` | Подвижные `vX` / `vX.Y` дают «последний патч мажора/минора» |

```yaml
- id: tags
  uses: moogur/all-workflows/.github/actions/docker-tags@master
  with:
    image: docker.pkg.github.com/user/repo/repo
    version: v1.2.3
# tags = ...:v1.2.3 ...:v1.2 ...:v1 ...:latest

- run: |
    build_args=()
    for ref in ${{ steps.tags.outputs.tags }}; do build_args+=(-t "$ref"); done
    docker build "${build_args[@]}" .
```

> Версия, не подходящая ни под один формат (предрелиз `v1.2.3-rc.1`, неполная версия, `2026-03-14`, тег без `v`), — ошибка: сборка падает вместо публикации мусорных тегов. Классификация — целиком в [`tag-format`](#tag-format).

Используется в [`docker-image`](#docker-image).

## `docker-image`

Общее тело docker-workflow'ов: версия сборки, теги, подмена Dockerfile, `docker build`, логин и публикация.
Раньше эти ~45 строк были скопированы в [deploy_for_backend](../.github/workflows/deploy_for_backend.yml),
[deploy_for_go_backend](../.github/workflows/deploy_for_go_backend.yml),
[deploy_for_full_app](../.github/workflows/deploy_for_full_app.yml) и
[deploy_for_docker_container](../.github/workflows/deploy_for_docker_container.yml) — и успели разойтись.

| | |
| --- | --- |
| **Входы** | `github_user` (обяз.) — владелец образа и логин в реестр; `dockerfile` (необяз.) — имя файла в `dockerfiles/`, пусто — Dockerfile проекта; `dockerignore` (необяз.) — имя файла `.dockerignore` там же; `build_args` (необяз.) — строки `KEY=VALUE`, по одной на строку; `context` (необяз., по умолчанию `.`); `token` (обяз.) — токен с `packages: write` и, для сборки по тегу, `contents: write` + `pull-requests: read` (публикация релиза) |
| **Выходы** | `version` — версия сборки; `tags` — полные ссылки на образ со всеми тегами |

```yaml
- id: node
  uses: moogur/all-workflows/.github/actions/detect-node-version@master

- uses: moogur/all-workflows/.github/actions/docker-image@master
  with:
    github_user: ${{ inputs.github_user }}
    dockerfile: deploy_backend.dockerfile
    dockerignore: .dockerignore
    build_args: ARG_NODE_VERSION=${{ steps.node.outputs.version }}
    token: ${{ secrets.GITHUB_TOKEN }}
```

**Версия сборки.** Тег, инициировавший запуск. Запуск без тега (расписание, ручной) всегда идёт как
`dd.mm.yyyy-HHMM-auto` в формате `date`, даже в semver-репозитории: иначе плановая пересборка переписала бы
релизные `vX.Y.Z` другим содержимым. Время в метке — чтобы две сборки за сутки не затёрли друг друга (UTC).

**Build-arg'и.** `ARG_APP_VERSION` экшен добавляет сам, остальные приходят списком `KEY=VALUE` — по строке на
аргумент. Для Dockerfile, который такой аргумент не объявляет, docker ограничится предупреждением.

> **Dockerfile берётся из копии этого репозитория рядом с экшеном.** Каталог `$GITHUB_ACTION_PATH` лежит внутри
> выкачанной копии `all-workflows` той же версии, что и сам экшен, поэтому `dockerfiles/` доступен как
> `$GITHUB_ACTION_PATH/../../../dockerfiles` — без `wget` с `master` и без расхождения версий. Если раскладка
> когда-нибудь изменится и файла там не окажется, шаг печатает `::warning::` и тянет файл с `master`, как раньше.
>
> Логин идёт через `--password-stdin`: токен не попадает ни в список процессов, ни в лог.
>
> **По тегу (`github.ref_type == 'tag'`) последним шагом публикуется GitHub-релиз** — экшен
> [`docker-release`](#docker-release). Сборка без тега (расписание, ручной запуск) релиз не трогает.
> Шаг стоит после публикации образа: неудачный `docker push` не должен оставлять релиз без образа.

## `docker-release`

Публикует GitHub-релиз для тега docker-сборки через [`github-release`](#github-release): собирает блок про
опубликованный docker-образ (`docker pull`, список тегов) и передаёт его как `extra_notes`. Вызывается
только из [`docker-image`](#docker-image), отдельно не используется.

| | |
| --- | --- |
| **Входы** | `version` (обяз.) — тег, инициировавший сборку; `tags` (обяз.) — полные ссылки на образ со всеми тегами (вывод `docker-tags`); `token` (обяз.) — токен с `contents: write` и `pull-requests: read` |
| **Выходы** | — |

Блок про образ (передаётся в `github-release` как `extra_notes`, дописывается после тела из PR/коммитов):

```markdown
## 🐳 Docker image

\`\`\`bash
docker pull docker.pkg.github.com/user/repo/repo:v1.2.3
\`\`\`

Tags: `v1.2.3`, `v1.2`, `v1`, `latest`

**Packages**: https://github.com/user/repo/packages
```

> Ссылка на страницу пакетов добавляется только при известном `GITHUB_REPOSITORY` (обычная сборка в Actions).
> Список тегов берётся из `tags` (вывод `docker-tags`) построчным разбором `<образ>:<тег>` — свой формат не
> пересчитывается. Сам скрипт (`image-notes.sh`) только строит блок и пишет его в `$GITHUB_OUTPUT` — в файл
> тела релиза ничего не дописывает: это делает `github-release` (`append-notes.sh`).

## `npm-package-notes`

Строит markdown-блок «как поставить» для опубликованных npm-пакетов — команда `npm install` на каждый
из списка. Один пакет ([`publish_package`](../.github/workflows/publish_package.yml)) или несколько
([`deploy_for_lerna`](../.github/workflows/deploy_for_lerna.yml)) — формат один и тот же. Результат идёт
в `github-release` как `extra_notes`.

| | |
| --- | --- |
| **Входы** | `packages` (обяз.) — опубликованные пакеты, `имя@версия` по одному на строку |
| **Выходы** | `notes` — markdown-блок для `github-release` (`extra_notes`) |

```yaml
- id: notes
  uses: moogur/all-workflows/.github/actions/npm-package-notes@master
  with:
    packages: '@moogur/lib@1.2.3'

- uses: moogur/all-workflows/.github/actions/github-release@master
  with:
    tag: ${{ github.ref_name }}
    extra_notes: ${{ steps.notes.outputs.notes }}
    token: ${{ secrets.GITHUB_TOKEN }}
```

> Пустых строк в `packages` быть не должно — если после фильтрации (например, все пакеты монорепозитория
> приватные) список пуст, экшен падает явно, а не публикует релиз с пустым блоком команд.

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

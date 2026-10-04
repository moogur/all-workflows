# Тестирование и валидация

Репозиторий валидирует сам себя в CI ([.github/workflows/ci.yml](../.github/workflows/ci.yml)) и содержит unit-тесты на bash-логику. Здесь — что и как проверяется, как запускать локально и **насколько можно доверять** результату.

← Назад к [README](../README.md) · [Composite actions](actions.md)

## Слои проверок

| Слой | Инструмент | Что проверяет | Где |
| --- | --- | --- | --- |
| Статика workflow'ов | **actionlint** | синтаксис, выражения `${{ }}`, ссылки `steps.<id>`, `uses`, контексты; внутри — shellcheck inline-скриптов | job `actionlint` |
| Статика bash | **shellcheck** | ошибки в скриптах экшенов, хуке, хелперах | job `shellcheck` |
| Структура YAML | **yamllint** | базовая корректность YAML (мягкий конфиг [.yamllint.yml](../.yamllint.yml)) | job `yamllint` |
| Unit-логика | **bats** | форматы `lib/*.sh`, поведение скриптов экшенов, хука commit-msg, генераторов Kanboard | job `bats` |

## Что покрыто unit-тестами

Тесты в [`tests/`](../tests/) проверяют **тот же код**, что выполняется в проде: логика экшенов вынесена в отдельные `.sh` (см. [actions.md](actions.md)), и тесты гоняют именно их.

| Файл тестов | Покрывает | Кейсы |
| --- | --- | --- |
| [tests/app-version.bats](../tests/app-version.bats) | `app-version/resolve.sh` | режимы `git`/`ref`, снятие/сохранение префикса, дефолты, ошибка на неизвестном `mode` |
| [tests/detect-node-version.bats](../tests/detect-node-version.bats) | `detect-node-version/detect.sh` | точная версия и диапазон из `engines.node`, понятная ошибка при отсутствующем и пустом `engines.node` |
| [tests/detect-go-version.bats](../tests/detect-go-version.bats) | `detect-go-version/detect.sh` | версия из директивы `go`, игнор `require`-блока, понятная ошибка при отсутствии директивы |
| [tests/remote-update-check.bats](../tests/remote-update-check.bats) | `remote-update-check/check.sh` | `commit` (время коммита, смена значения, выбор ветки), `tag` (самый свежий по дате, а не максимальный по имени — guard против возврата к сортировке по имени, которая на датных тегах выбирает старый; неверсионный тег как маркер; смена значения), ошибки: нет тегов, неизвестный `type`, недоступный репозиторий |
| [tests/save-update-value.bats](../tests/save-update-value.bats) | `save-update-value/save.sh` | обновление существующей переменной одним `PATCH`, создание через `POST` при 404, отсутствие лишнего `POST`, падение обоих вызовов, обязательные переменные окружения (gh подменяется заглушкой) |
| [tests/auto-deploy.bats](../tests/auto-deploy.bats) | конфигурация авто-деплоя | guard: маркер сохраняется отдельным job'ом после деплоя, вложенный деплой с `secrets: inherit`, проверка через общий action, отсутствие лишнего checkout, время в метке `-auto` |
| [tests/release-notes.bats](../tests/release-notes.bats) | `release-notes/notes.sh` | выбор предыдущего тега по дате создания (guard против сортировки по имени), переопределение через `previous_tag`, первый релиз без предыдущего тега, раскладка типов коммитов по категориям, произвольный префикс задачи, коммит не по формату в Other, число изменений и ссылка на сравнение, ошибки: неизвестный тег (с подсказкой про `fetch-depth`), отсутствие тега и `GITHUB_REF` |
| [tests/release-notes-pr.bats](../tests/release-notes-pr.bats) | `release-notes/notes.sh` | PR из локальной истории (`--first-parent`): merge-коммит `Merge pull request` — запись по заголовку PR из тела, коммиты ветки и описание PR не попадают, заголовок не по формату — Other как есть, сквошенный PR-коммит (`... (#N)`), PR и прямой коммит вперемешку, `Merge branch ...` — запись Other по короткому sha. Общая обвязка — `tests/release-notes-helpers.bash` |
| [tests/publish-release.bats](../tests/publish-release.bats) | `publish-release/publish.sh` | создание релиза (тело из файла, пустое тело, заголовок), обновление существующего вместо падения, снятие draft (`--draft=false`) при правке существующего релиза, «менять нечего» без лишних вызовов, загрузка ассетов с `--clobber`, гонка параллельных job'ов матрицы (`create` падает, `view` находит релиз только на повторной проверке — правка вместо падения; `create` падает и релиза всё ещё нет — ошибка), ошибки: отсутствующий файл тела, отсутствие тега (gh подменяется заглушкой) |
| [tests/github-release.bats](../tests/github-release.bats) | `github-release/append-notes.sh` | существующее тело релиза сохраняется, блок дописывается после пустой строки, многострочный блок дописывается как есть, ошибки: отсутствующие `NOTES_FILE`/`EXTRA_NOTES`, несуществующий файл тела |
| [tests/npm-package-notes.bats](../tests/npm-package-notes.bats) | `npm-package-notes/notes.sh` | один пакет, несколько пакетов в одном код-блоке, пустые строки в списке пропускаются, ошибки: отсутствующий `PACKAGES`, `PACKAGES` из одних пробелов |
| [tests/release-workflow.bats](../tests/release-workflow.bats) | конфигурация релизных workflow'ов | guard: `release.yml`/`release_with_artifacts.yml`/`release-drafter.yml` удалены, `release-drafter`/`notes_source` нигде не остались, все прямые релизные workflow'ы вызывают `github-release` только по тегу, `github-release` — единственный производственный вызывающий `release-notes`/`publish-release`, `tag-format` вызывается только в `github-release`/`docker-tags` и как ранний фейл-фаст в `release_frontend`/`deploy_for_build_application` (без собственного regexp), заархивированные release-экшены не используются, npm-workflow'ы собирают блок через `npm-package-notes`, `deploy_for_lerna` определяет список пакетов до `Publish packages`, имя ассета `go_build_with_artifacts` включает `goos`/`goarch`, `deploy_for_build_application` без тега пропускает релиз целиком и берёт версию только из тега, docker-workflow'ы не вызывают `github-release` напрямую |
| [tests/docker-image.bats](../tests/docker-image.bats) | скрипты `docker-image/` | версия сборки (тег или датная метка без тега), имя образа, пользователь образа (явный `GITHUB_USER`, иначе `REPOSITORY_OWNER`, иначе ошибка) и вывод `user=`, Dockerfile из копии рядом с экшеном и откат на `master` с предупреждением, `ARG_APP_VERSION` и дополнительные build-arg, логин через stdin без токена в аргументах, пуш каждого тега (docker и wget подменяются заглушками) |
| [tests/docker-release.bats](../tests/docker-release.bats) | `docker-release/image-notes.sh` | `docker pull` берёт `VERSION`, а не первый тег списка; список тегов из `TAGS` (семвер-лестница, датная версия, единственный тег без висячей запятой); ссылка на пакеты по наличию `GITHUB_REPOSITORY`; блок начинается с заголовка `## 🐳 Docker image`; блок печатается в `$GITHUB_OUTPUT` (`notes`), а не в файл; ошибки: отсутствующие `VERSION`/`TAGS` |
| [tests/docker-workflows.bats](../tests/docker-workflows.bats) | конфигурация docker-workflow'ов | guard: ни один вход workflow/action не имеет дефолта с `$`, `github_user` по умолчанию пустой, сырой `github_user` читает только `resolve.sh`, а `publish.sh` логинится под пользователем из его выхода, сборка только через общий `docker-image`, никаких своих `docker build/push/login`, `docker-tags` вызывается лишь из экшена, запрошенные Dockerfile существуют в `dockerfiles/`, `docker-release` вызывается только внутри `docker-image` (по тегу, последним шагом), а не из самих workflow'ов |
| [tests/workflows-permissions.bats](../tests/workflows-permissions.bats) | права `GITHUB_TOKEN` | guard: `permissions` объявлены в каждом workflow, нет `write-all`, `auto_deploy_*` не уже вложенных деплоев (`contents`, `packages`), все релизящие по тегу workflow'ы просят `contents: write`, ни один (кроме `pr_annotation`, свой отчёт в PR) не просит `pull-requests: read` — `release-notes` собирается локально, без GitHub API |
| [tests/pr-annotation.bats](../tests/pr-annotation.bats) | конфигурация `pr_annotation.yml` | guard: job не стартует на PR из форка (и не отсекает остальные события), `.npmrc` удаляется после `npm ci` и до выполнения кода из PR, сторонний action не ставит зависимости сам |
| [tests/skip-tests.bats](../tests/skip-tests.bats) | выключатель тестов | guard: шаг с тестами закрыт условием `inputs.skip_tests`, вход объявлен с `required: false` и `default: 'false'` (тесты включены по умолчанию), нет входа без соответствующего шага |
| [tests/tag-format.bats](../tests/tag-format.bats) | `tag-format/format.sh` | env → `$GITHUB_OUTPUT` для даты и semver, ошибка неизвестного формата, отсутствующий вход. Классификация формата — в `tests/lib-version.bats` |
| [tests/docker-tags.bats](../tests/docker-tags.bats) | `docker-tags/tags.sh` | построение тегов по готовому `FORMAT` (дата — версия как есть + `latest`; semver — лестница `vX.Y.Z`/`vX.Y`/`vX`/`latest`, нули и многозначные разряды), ошибки: неизвестный `FORMAT`, отсутствующие входы |
| [tests/npm-auth.bats](../tests/npm-auth.bats) | `npm-auth/configure.sh` | содержимое и формат `.npmrc` |
| [tests/commit-msg.bats](../tests/commit-msg.bats) | `.husky/commit-msg` | все допустимые типы, правила отклонения (номер задачи, регистр, скобки, пустые поля, граница длины 125/126), многострочные сообщения (валидируется только заголовок), требование префикса `GA` именно этого репозитория, точное совпадение типа (`feat` больше не проходит как часть `feature`) |
| [tests/kanboard.bats](../tests/kanboard.bats) | `scripts/kanboard_requests.sh` (генераторы payload) | валидный JSON и методы, значения по умолчанию (`position`, `private_*`), типы полей (число/строка), экранирование строк, нечисловые id и `$(...)` отвергаются |
| [tests/kanboard-requests.bats](../tests/kanboard-requests.bats) | `scripts/kanboard_requests.sh` (обёртка `execute_request`) | таймауты и ретраи в аргументах curl, `-f`, адрес/тело запроса, логин и токен только через stdin-конфиг (нет в argv), токен с `"`/`\`/переводом строки доходит без искажений, ненулевой код и сообщение при недоступном Kanboard (curl подменяется заглушкой), значения из `KANBOARD_*` в окружении, `$(...)` в них не выполняется |
| [tests/kanboard-messages.bats](../tests/kanboard-messages.bats) | `scripts/kanboard_requests.sh` (отчёт `message.tmpl`) | ветки success/error/unknown, `task_id=-1`, разделители, формат ссылки + регрессия на word-splitting многословного raw |
| [tests/kanboard-task-id.bats](../tests/kanboard-task-id.bats) | `scripts/kanboard_task_id.sh` | `task_id` из заголовка последнего коммита и из имени ветки/тега, версия релиза (снятие `v`), два последних тега, `task_id` коммитов диапазона (и всей истории без предыдущего тега) без дублей, коммит не по формату не даёт числового id, вредоносные заголовки/ветки (`$(...)`, `;id`) не дают id и ничего не исполняют |
| [tests/kanboard-workflow.bats](../tests/kanboard-workflow.bats) | guard `kanboard.yml` | нет `sed`/копии requests.sh, секреты только через `env:`, шаги пропускаются без task_id |
| [tests/no-expressions-in-run.bats](../tests/no-expressions-in-run.bats) | guard: все workflow'ы и composite actions | ни в одном `run:` (блочном и однострочном) нет `${{ }}` — значения только через `env:` шага; `if:`/`with:`/`env:` разрешены; сам сканер проверяется на плохих и допустимых примерах |
| [tests/run-build-script.bats](../tests/run-build-script.bats) | `run-build-script/run.sh` | путь к скрипту сборки: относительный внутри workspace выполняется (в т.ч. `./`, пробелы, `a..b.sh`, симлинк внутри); пустой, абсолютный, `..` в начале/середине, несуществующий, каталог, симлинк на файл/каталог вне workspace — отказ без выполнения; метасимволы в пути не исполняются; guard: workflow ходит только через action |
| [tests/action-versions.bats](../tests/action-versions.bats) | версии сторонних actions | guard: ни один `actions/*` не откатывается на мажор с node20 (GitHub выводит его из эксплуатации) |
| [tests/workflows-cache.bats](../tests/workflows-cache.bats) | конфигурация workflow'ов | guard: нет кэша `node_modules`/пропуска по `cache-hit`/`actions/cache`, npm-workflow'ы используют общий `setup-node` с кэшем npm |
| [tests/lib-version.bats](../tests/lib-version.bats) | `lib/version.sh` | классификация даты/semver (обе метки авто-сборки, легаси `-auto`) и её ошибки (без `v`, предрелиз, неполная версия, дата не в формате, произвольная строка), разбор semver на major/minor/patch, формат метки авто-сборки, снятие `refs/tags/` и произвольного префикса, повторное подключение в одном shell не падает под `bash -e` |
| [tests/lib-tags.bats](../tests/lib-tags.bats) | `lib/tags.sh` | N последних тегов по дате создания (guard против сортировки по имени), поведение при `n` больше числа тегов и без тегов, тег по умолчанию — текущая директория, сосед по дате для первого/несуществующего тега |
| [tests/lib-commit.bats](../tests/lib-commit.bats) | `lib/commit.sh` | разбор заголовка на 4 группы, произвольный префикс задачи, отклонение (пробел после `]`, пустой subject/scope, тип с заглавной), захват `Merge pull request`/сквош-суффикса, точное совпадение типа (не подстрока), карта категорий, регистр, `task_id` из заголовка/имени ветки (дефис и подчёркивание), многострочный вход — только первая строка, `commit_task_id_valid`/`commit_task_id` (только цифры, `$(...)`/`;id` отвергаются), повторное подключение в одном shell (и оба скрипта kanboard подряд в обоих порядках, как в `kanboard.yml`) не падает под `bash -e`, функции и константы после него на месте |
| [tests/lib-docker.bats](../tests/lib-docker.bats) | `lib/docker.sh` | имя образа в легаси-реестре, склейка `<образ>:<тег>`, разбор на образ/тег и их обратимость, повторное подключение в одном shell не падает под `bash -e` |
| [tests/lib-npm.bats](../tests/lib-npm.bats) | `lib/npm.sh` | `имя@версия` из package.json, приватный пакет отдаёт пустую строку, несуществующий файл — ошибка |
| [tests/formats.bats](../tests/formats.bats) | форматы вне `lib/` | guard: регэкспы/идиомы форматов (дата, semver, `creatordate`, `Merge pull request`, список типов, снятие `refs/tags/`, разбор `task_id` через `tr`, проверка числового id `^[0-9]+$`) не переизобретаются в `.github`, `scripts`, `.husky` — только в `lib/` |

## Запуск локально

Проще всего — через [`Makefile`](../Makefile):

```bash
make check   # всё, что гоняет CI: статика + тесты
make lint    # только статика (actionlint + shellcheck + yamllint)
make test    # только bats-тесты
make help    # список команд
```

Либо вручную (то, что вызывают цели Makefile):

```bash
# Unit-тесты (нужны bats и jq)
bats tests/

# Статика bash (-x: следовать за source lib/*.sh, см. source= в файлах)
shellcheck -x lib/*.sh .github/actions/*/*.sh scripts/*.sh .husky/commit-msg tests/*.bash

# Статика workflow'ов (нужен actionlint)
SHELLCHECK_OPTS=--severity=error actionlint -ignore 'job_workflow_sha'

# Структура YAML (нужен yamllint)
yamllint -c .yamllint.yml .github
```

Установка инструментов:
- **bats**: `brew install bats-core` (macOS) / `apt-get install bats` (Linux);
- **shellcheck**: `brew install shellcheck` / `apt-get install shellcheck`;
- **actionlint**: `brew install actionlint` или [скрипт загрузки](https://github.com/rhysd/actionlint/blob/main/docs/install.md);
- **yamllint**: `pipx install yamllint`.

## Насколько можно быть уверенным

**Высокая уверенность** (проверяется автоматически и детерминированно):
- корректность проводки workflow'ов: нет битых ссылок `steps.<id>`, ошибок в выражениях, неверных `uses` — это ровно тот класс ошибок, что мы правили вручную (например, опечатка `steps.go-node-version`), и actionlint его ловит;
- бизнес-логика скриптов: расчёт версии (оба режима и префикс), формирование тегов docker-образа (оба формата), выбор маркера свежести внешнего репозитория, запись переменной окружения (на заглушке `gh`), парсинг версий Node/Go, генерация `.npmrc`, все правила `commit-msg`, формирование JSON-RPC payload Kanboard.

**Не покрывается (проверяется только реальным запуском на GitHub):**
- что `wget` с `raw.githubusercontent.com/.../master/...` отдаёт нужные файлы;
- что секреты корректно прокидываются через `workflow_call` во вложенные workflow'ы;
- что `docker push` в `docker.pkg.github.com` проходит с данным токеном;
- что `gh api` обновляет переменную окружения с правами `UPDATE_VARIABLES_CLI_TOKEN`;
- поведение сторонних actions (jest-coverage) и публикация релиза через `gh release create` (тело релиза собирается локально и покрыто тестами, сам вызов `gh` — нет).

Это «слепая зона» внешней среды. Закрыть её можно только smoke-прогоном на реальном GitHub (отдельный объём работ, в текущий набор не входит) — см. также [modernization.md](modernization.md).

## Особенности, влияющие на проверки

- В CI shellcheck для inline-скриптов workflow'ов (внутри actionlint) работает на уровне `--severity=error`: в существующих docker-командах есть намеренный word-splitting (`SC2086`), который не считается ошибкой. Все отдельные `.sh`-скрипты (`lib/`, экшены, `scripts/kanboard_requests.sh`, хук, хелперы) проверяются строго на всех уровнях, без исключений.
- Скрипты подключают `lib/*.sh` динамическим путём (`dirname "${BASH_SOURCE[0]}"`), поэтому standalone-shellcheck нужен флаг `-x` (следовать за `source`) и директивы `# shellcheck source=lib/<файл>.sh` рядом с каждым `source` — без них shellcheck не находит файл и не проверяет реальное использование того, что в нём объявлено (`SC1091`/`SC2034`).
- Единственный `-ignore` — на `github.job_workflow_sha`: поле валидно (GitHub docs), но отсутствует в схеме actionlint 1.7.12; используется в [kanboard.yml](../.github/workflows/kanboard.yml) для пина версии при checkout. Прежний `-ignore 'is potentially untrusted'` снят: `github.head_ref` теперь приходит в шаг переменной окружения (см. [security.md](security.md#5-инъекция-через-githubhead_ref-в-kanboardyml--исправлено)).
- actionlint в CI ставится не сторонним загрузчиком с ветки `main`, а скачиванием релиза с проверкой `sha256sum`. При обновлении версии в [ci.yml](../.github/workflows/ci.yml) нужно поменять и `ACTIONLINT_VERSION`, и `ACTIONLINT_SHA256` (хеш `actionlint_<version>_linux_amd64.tar.gz` берётся из `actionlint_<version>_checksums.txt` в релизе).

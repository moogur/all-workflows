# Тестирование и валидация

Репозиторий валидирует сам себя в CI ([.github/workflows/ci.yml](../.github/workflows/ci.yml)) и содержит unit-тесты на bash-логику. Здесь — что и как проверяется, как запускать локально и **насколько можно доверять** результату.

← Назад к [README](../README.md) · [Composite actions](actions.md)

## Слои проверок

| Слой | Инструмент | Что проверяет | Где |
| --- | --- | --- | --- |
| Статика workflow'ов | **actionlint** | синтаксис, выражения `${{ }}`, ссылки `steps.<id>`, `uses`, контексты; внутри — shellcheck inline-скриптов | job `actionlint` |
| Статика bash | **shellcheck** | ошибки в скриптах экшенов, хуке, хелперах | job `shellcheck` |
| Структура YAML | **yamllint** | базовая корректность YAML (мягкий конфиг [.yamllint.yml](../.yamllint.yml)) | job `yamllint` |
| Unit-логика | **bats** | поведение скриптов экшенов, хука commit-msg, генераторов Kanboard | job `bats` |

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
| [tests/release-notes.bats](../tests/release-notes.bats) | `release-notes/notes.sh` | выбор предыдущего тега по дате создания (guard против сортировки по имени), переопределение через `previous_tag`, первый релиз без предыдущего тега, раскладка типов коммитов по категориям, произвольный префикс задачи, коммит не по формату в Other, игнор слияний, число коммитов и ссылка на сравнение, ошибки: неизвестный тег (с подсказкой про `fetch-depth`), отсутствие тега и `GITHUB_REF` |
| [tests/publish-release.bats](../tests/publish-release.bats) | `publish-release/publish.sh` | создание релиза (тело из файла, пустое тело, заголовок), обновление существующего вместо падения, «менять нечего» без лишних вызовов, неперетирание тела в режиме `drafter`, загрузка ассетов с `--clobber`, ошибки: отсутствующий файл тела, отсутствие тега (gh подменяется заглушкой) |
| [tests/release-workflow.bats](../tests/release-workflow.bats) | конфигурация релизных workflow'ов | guard: источник тела по умолчанию (`drafter`, у `deploy_for_build_application` — `none`), полная история тегов в режиме `commits` (строки `'0'`/`'1'` в выражении), публикация через общий `publish-release`, отсутствие архивных release-экшенов, тег ассетов и заголовок из вывода драфтера, права под драфтер у вложенного и вызывающего workflow |
| [tests/docker-workflows.bats](../tests/docker-workflows.bats) | конфигурация docker-workflow'ов | guard: теги через общий action, версия из тега запуска (а не `git describe`), semver только для сборки по тегу, пуш всех тегов циклом |
| [tests/workflows-permissions.bats](../tests/workflows-permissions.bats) | права `GITHUB_TOKEN` | guard: `permissions` объявлены в каждом workflow, нет `write-all`, `auto_deploy_*` не уже вложенных деплоев |
| [tests/docker-tags.bats](../tests/docker-tags.bats) | `docker-tags/tags.sh` | форматы `date`/`semver`, лестница `vX.Y.Z`/`vX.Y`/`vX`/`latest`, добавление префикса `v`, отклонение тега-даты/предрелиза/неполной версии, ошибка на неизвестном `format_mode` |
| [tests/npm-auth.bats](../tests/npm-auth.bats) | `npm-auth/configure.sh` | содержимое и формат `.npmrc` |
| [tests/commit-msg.bats](../tests/commit-msg.bats) | `.husky/commit-msg` | все допустимые типы, правила отклонения (номер задачи, регистр, скобки, пустые поля, граница длины 125/126), многострочные сообщения (валидируется только заголовок) + характеристика нестрогого совпадения типа |
| [tests/kanboard.bats](../tests/kanboard.bats) | `scripts/kanboard_requests.sh` (генераторы payload) | валидный JSON и методы, значения по умолчанию (`position`, `private_*`), типы полей (число/строка) + ломающий ввод |
| [tests/kanboard-requests.bats](../tests/kanboard-requests.bats) | `scripts/kanboard_requests.sh` (обёртка `execute_request`) | таймауты и ретраи в аргументах curl, `-f`, адрес/авторизация/тело запроса, ненулевой код и сообщение при недоступном Kanboard (curl подменяется заглушкой) |
| [tests/kanboard-messages.bats](../tests/kanboard-messages.bats) | `scripts/kanboard_requests.sh` (отчёт `message.tmpl`) | ветки success/error/unknown, `task_id=-1`, разделители, формат ссылки + регрессия на word-splitting многословного raw |
| [tests/action-versions.bats](../tests/action-versions.bats) | версии сторонних actions | guard: ни один `actions/*` и `release-drafter` не откатывается на мажор с node20 (GitHub выводит его из эксплуатации) |
| [tests/workflows-cache.bats](../tests/workflows-cache.bats) | конфигурация workflow'ов | guard: нет кэша `node_modules`/пропуска по `cache-hit`/`actions/cache`, npm-workflow'ы используют общий `setup-node` с кэшем npm |

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

# Статика bash
shellcheck .github/actions/*/*.sh scripts/*.sh .husky/commit-msg tests/helpers.bash

# Статика workflow'ов (нужен actionlint)
SHELLCHECK_OPTS=--severity=error actionlint -ignore 'is potentially untrusted' -ignore 'job_workflow_sha'

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
- поведение сторонних actions (release-drafter, jest-coverage) и публикация релиза через `gh release create` (тело релиза собирается локально и покрыто тестами, сам вызов `gh` — нет).

Это «слепая зона» внешней среды. Закрыть её можно только smoke-прогоном на реальном GitHub (отдельный объём работ, в текущий набор не входит) — см. также [modernization.md](modernization.md).

## Особенности, влияющие на проверки

- В CI shellcheck для inline-скриптов workflow'ов (внутри actionlint) работает на уровне `--severity=error`: в существующих docker-командах есть намеренный word-splitting (`SC2086`), который не считается ошибкой. Все отдельные `.sh`-скрипты (экшены, `scripts/kanboard_requests.sh`, хук, хелперы) проверяются строго на всех уровнях, без исключений.
- Находка actionlint про `github.head_ref` в [kanboard.yml](../.github/workflows/kanboard.yml) намеренно вынесена в `-ignore` и задокументирована в [security.md](security.md).
- Второй `-ignore` — на `github.job_workflow_sha`: поле валидно (GitHub docs), но отсутствует в схеме actionlint 1.7.12; используется в [kanboard.yml](../.github/workflows/kanboard.yml) для пина версии при checkout.

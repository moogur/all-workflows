# Безопасность

Замечания по безопасности переиспользуемых workflow'ов. Это справочный материал «для сведения» — критичных уязвимостей нет, но при расширении использования стоит держать пункты в голове.

← Назад к [README](../README.md)

## 1. Недоверенный код из Pull Request

[pr_annotation.yml](../.github/workflows/pr_annotation.yml) — единственный workflow, который исполняет код из Pull Request: `npm ci` запускает lifecycle-скрипты (`postinstall` и т. п.), а шаг покрытия — тесты проекта. Форк здесь ни при чём: workflow всегда выполняется **в базовом репозитории**, на его раннере и в его окружении, а из форка приходит только код.

**Что видит такой запуск.** Меньше, чем кажется. На событие `pull_request` из форка GitHub не передаёт секреты: `secrets.*` пустые, `secrets: inherit` ничего не наследует, а `GITHUB_TOKEN` принудительно понижается до read-only независимо от блока `permissions` — то есть `pull-requests: write` и `checks: write` у `pr_annotation` не действуют и аннотации всё равно не публикуются. Для публичного репозитория первый запуск от нового контрибьютора вдобавок требует ручного подтверждения.

**Что оставалось доступным.** Файл `.npmrc`, который создаёт [`npm-auth`](actions.md#npm-auth) из `GITHUB_TOKEN`. На публичном репозитории read-only токен бесполезен, на приватном им можно вычитать исходники и пакеты приватного scope.

**Закрыто двумя шагами:**
- job не стартует на PR из форка — `if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`; на форковом PR он в любом случае не мог выполнить свою работу из-за read-only токена;
- `.npmrc` удаляется сразу после `npm ci`, до запуска тестов, а стороннему action передан `skip-step: install`, чтобы он не пытался ставить зависимости уже без авторизации.

Оба правила закреплены guard-тестом [tests/pr-annotation.bats](../tests/pr-annotation.bats).

**Настоящая граница доверия — PR из ветки самого репозитория.** Такие запуски получают секреты полностью, и защищает их только то, что пушить ветки может лишь обладатель write-доступа.

> **`pull_request_target` использовать нельзя.** Он выполняется в контексте базовой ветки **с полным набором секретов и write-токеном**; связка с `actions/checkout` по `github.event.pull_request.head.sha` и последующей установкой зависимостей отдаёт все секреты автору PR. Если отчёт по форковым PR когда-нибудь понадобится — сборка на `pull_request` без секретов, публикация результата отдельным workflow по `workflow_run`.

> Права `GITHUB_TOKEN` заданы явно в каждом workflow (таблица — в [conventions.md](conventions.md#права-github_token)); для `pr_annotation` это `contents: read`, `packages: read`, `pull-requests: write`, `checks: write`. Набор прав не ограничивает доступ к секретам репозитория — только то, что может сам токен.

## 2. Передача токена в `docker login` — исправлено

Раньше токен уходил аргументом командной строки (`docker login ... -p <token>`) и мог попасть в список процессов раннера. Теперь логин выполняет action [`docker-image`](actions.md#docker-image) через `--password-stdin`.

**Осталось на будущее:** [`docker/login-action`](https://github.com/docker/login-action) при переезде на `ghcr.io` (см. [modernization.md](modernization.md)).

## 3. Загрузка ресурсов в рантайме с `master`

Dockerfile'ы и composite actions подтягиваются по ссылке на ветку `master`. Любое изменение в `master` мгновенно влияет на всех потребителей, а версия вызванного workflow не привязана к версии скачиваемого ресурса.

**Риск:** компрометация или ошибочный коммит в `master` немедленно распространяется на все пайплайны (supply-chain).

**Рекомендация:** пинить ресурсы и сторонние actions к тегу или SHA. Подробнее — в [modernization.md](modernization.md).

> Закрыто для собственного CI: [ci.yml](../.github/workflows/ci.yml) больше не исполняет `bash <(curl ... /main/scripts/download-actionlint.bash)`. Релиз actionlint скачивается по фиксированной версии и сверяется с записанным рядом `sha256`, так что компрометация ветки `main` стороннего репозитория ничего не даёт.

> Частично закрыто: [kanboard.yml](../.github/workflows/kanboard.yml) берёт `kanboard_requests.sh` через `actions/checkout`, запиненный к `github.job_workflow_sha`, а Dockerfile'ы [`docker-image`](actions.md#docker-image) копирует из копии репозитория рядом с экшеном — обе ссылки на `master` в рантайме ушли. Осталась ссылка `@master` в самих `uses:`.

## 4. Пин сторонних actions

Сторонние actions пинятся по тегам (`@v7`, `@v2`); архивные release-actions по `@master` / `@main` больше не используются.

**Рекомендация:** для повышения уровня безопасности пинить сторонние actions по полному SHA коммита; как минимум — не использовать `@master`/`@main` у сторонних зависимостей.

## 5. Инъекция через `github.head_ref` в `kanboard.yml` — исправлено

Раньше `${{ github.head_ref }}` подставлялся прямо в тело inline-скрипта ([kanboard.yml](../.github/workflows/kanboard.yml), шаг «Set variables»). Имя ветки задаёт автор PR, поэтому ветка вида `GA-1'; <команда>; '` выполняла произвольный код на раннере.

Теперь значение приходит переменной окружения и берётся в кавычки:

```yaml
env:
  HEAD_REF: ${{ github.head_ref }}
run: |
  task_id=`echo "$HEAD_REF" | ...`
```

Вместе с этим из CI и `Makefile` снят `-ignore 'is potentially untrusted'` — проверка actionlint проходит без него ([testing.md](testing.md)).

## 6. `.npmrc` с токеном в слое сборки

[`deploy_backend.dockerfile`](../dockerfiles/deploy_backend.dockerfile) копирует `.npmrc` внутрь образа (`COPY package.json package-lock.json .npmrc ./`), а файл содержит `_authToken`. В **финальный** образ токен не попадает — сборка многоступенчатая, наружу копируется только `dist`, — но он остаётся в слоях builder-стадии и в кэше сборки раннера.

**Рекомендация:** пробрасывать токен секрет-маунтом BuildKit (`RUN --mount=type=secret,id=npmrc ...`) либо удалять `.npmrc` тем же слоем, что и установка (`RUN npm ci && rm -f .npmrc`). Для `full_deploy.dockerfile` то же самое с `.npmrc` в `frontend/`.

## 7. Секреты, используемые workflow'ами

Полный перечень секретов и их назначение — в [conventions.md](conventions.md#секреты). Передавайте их через `secrets: inherit` либо явным списком и не логируйте значения.

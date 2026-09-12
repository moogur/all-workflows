# Безопасность

Замечания по безопасности переиспользуемых workflow'ов. Это справочный материал «для сведения» — критичных уязвимостей нет, но при расширении использования стоит держать пункты в голове.

← Назад к [README](../README.md)

## 1. Секреты и Pull Request из форков

Workflow [pr_annotation.yml](../.github/workflows/pr_annotation.yml) запускается в контексте Pull Request, имеет доступ к секретам и выполняет установку зависимостей (`npm ci`).

**Риск:** если такой пайплайн когда-либо будет запущен на PR из **форка**, то lifecycle-скрипты npm (`postinstall` и т. п.) из недоверенного кода смогут получить доступ к секретам раннера.

**Рекомендации:**
- использовать эти workflow'ы только во внутренних (доверенных) репозиториях;
- для публичных репозиториев рассмотреть `pull_request_target` с осторожностью либо запуск без секретов.

> Права `GITHUB_TOKEN` теперь заданы явно в каждом workflow (таблица — в [conventions.md](conventions.md#права-github_token)); для `pr_annotation` это `contents: read`, `packages: read`, `pull-requests: write`, `checks: write`. Доступ к секретам репозитория это не ограничивает — только права токена.

## 2. Передача токена в `docker login` — исправлено

Раньше токен уходил аргументом командной строки (`docker login ... -p <token>`) и мог попасть в список процессов раннера. Теперь логин выполняет action [`docker-image`](actions.md#docker-image) через `--password-stdin`.

**Осталось на будущее:** [`docker/login-action`](https://github.com/docker/login-action) при переезде на `ghcr.io` (см. [modernization.md](modernization.md)).

## 3. Загрузка ресурсов в рантайме с `master`

Dockerfile'ы и composite actions подтягиваются по ссылке на ветку `master`. Любое изменение в `master` мгновенно влияет на всех потребителей, а версия вызванного workflow не привязана к версии скачиваемого ресурса.

**Риск:** компрометация или ошибочный коммит в `master` немедленно распространяется на все пайплайны (supply-chain).

**Рекомендация:** пинить ресурсы и сторонние actions к тегу или SHA. Подробнее — в [modernization.md](modernization.md).

> Частично закрыто: [kanboard.yml](../.github/workflows/kanboard.yml) берёт `kanboard_requests.sh` через `actions/checkout`, запиненный к `github.job_workflow_sha`, а Dockerfile'ы [`docker-image`](actions.md#docker-image) копирует из копии репозитория рядом с экшеном — обе ссылки на `master` в рантайме ушли. Осталась ссылка `@master` в самих `uses:`.

## 4. Пин сторонних actions

Сторонние actions пинятся по тегам (`@v7`, `@v2`); архивные release-actions по `@master` / `@main` больше не используются.

**Рекомендация:** для повышения уровня безопасности пинить сторонние actions по полному SHA коммита; как минимум — не использовать `@master`/`@main` у сторонних зависимостей.

## 5. Инъекция через `github.head_ref` в `kanboard.yml`

actionlint помечает использование `${{ github.head_ref }}` напрямую в inline-скрипте ([kanboard.yml](../.github/workflows/kanboard.yml), шаг «Set variables»): имя ветки контролируется автором PR и может содержать спецсимволы (риск инъекции команд).

**Рекомендация:** передавать значение через переменную окружения, а не интерполировать в тело скрипта:

```yaml
env:
  HEAD_REF: ${{ github.head_ref }}
run: |
  task_id=$(echo "$HEAD_REF" | ...)
```

Находка оставлена как есть (kanboard не меняется) и вынесена в `-ignore` в CI ([testing.md](testing.md)), чтобы не блокировать проверку. Устранить при ближайшей правке `kanboard.yml`.

## 6. `.npmrc` с токеном в слое сборки

[`deploy_backend.dockerfile`](../dockerfiles/deploy_backend.dockerfile) копирует `.npmrc` внутрь образа (`COPY package.json package-lock.json .npmrc ./`), а файл содержит `_authToken`. В **финальный** образ токен не попадает — сборка многоступенчатая, наружу копируется только `dist`, — но он остаётся в слоях builder-стадии и в кэше сборки раннера.

**Рекомендация:** пробрасывать токен секрет-маунтом BuildKit (`RUN --mount=type=secret,id=npmrc ...`) либо удалять `.npmrc` тем же слоем, что и установка (`RUN npm ci && rm -f .npmrc`). Для `full_deploy.dockerfile` то же самое с `.npmrc` в `frontend/`.

## 7. Секреты, используемые workflow'ами

Полный перечень секретов и их назначение — в [conventions.md](conventions.md#секреты). Передавайте их через `secrets: inherit` либо явным списком и не логируйте значения.

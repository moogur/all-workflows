#!/usr/bin/env bash
# Записывает значение в переменную GitHub Environment.
# PATCH умеет только обновлять, поэтому при первом запуске (переменной ещё нет)
# падает на 404 — тогда создаём переменную через POST.
# Вход (env): OWNER, REPO, ENVIRONMENT, VARIABLE_NAME, VARIABLE_VALUE, GH_TOKEN.
set -euo pipefail

owner="${OWNER:?OWNER is required}"
repo="${REPO:?REPO is required}"
environment="${ENVIRONMENT:?ENVIRONMENT is required}"
name="${VARIABLE_NAME:?VARIABLE_NAME is required}"
value="${VARIABLE_VALUE:?VARIABLE_VALUE is required}"

api_path="repos/${owner}/${repo}/environments/${environment}/variables"

if gh api --silent --method PATCH \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "${api_path}/${name}" -f "name=${name}" -f "value=${value}"; then
  echo "Variable '${name}' updated: ${value}"
  exit 0
fi

echo "Variable '${name}' was not updated, creating it"
gh api --silent --method POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$api_path" -f "name=${name}" -f "value=${value}"
echo "Variable '${name}' created: ${value}"

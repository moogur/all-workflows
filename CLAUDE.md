# all-workflows

Library of **reusable GitHub Actions workflows** (`on: workflow_call`) and composite actions,
consumed by other repos via `uses: moogur/all-workflows/...@master`. Nothing is built or
deployed from this repo itself — it only lints and unit-tests its own bash.

## Blast radius

- Consumers reference `@master`. A push to master is an immediate release to every consumer
  repo; there is no version tag for the library. Treat master as production.
- The same `@master` hardcoding applies inside this repo: workflows call
  `.github/actions/*@master` and `wget` dockerfiles from `raw.githubusercontent.com/.../master/`.

## Checks

- `make check` = what CI runs (`make lint` + `make test`), `make help` for the list.
  Tools: `actionlint`, `shellcheck`, `yamllint`, `bats`, `jq`.
- shellcheck is strict for standalone `.sh`, the hook and `tests/*.bash`; inline workflow
  scripts are checked (inside actionlint) only at `--severity=error` — docker commands rely on
  intentional word-splitting.
- The single actionlint `-ignore` (`job_workflow_sha`) is deliberate; do not "fix" that finding.
  Any new ignore needs a line in `docs/testing.md`.

## Where logic goes

- Action logic lives in a separate `<action>/<name>.sh` next to `action.yml`: inputs via `env:`,
  result via `$GITHUB_OUTPUT`, and `action.yml` only does `run: bash "$GITHUB_ACTION_PATH/<name>.sh"`.
  Reason: bats then tests the exact file that runs in prod.
- Steps shared by several workflows go to `.github/actions/`, not copy-pasted inline.
- Formats of shared values (version/tag, commit header, docker ref, npm package) live only in
  `lib/<name>.sh`; scripts `source` it via `$(dirname "${BASH_SOURCE[0]}")/…/lib`, with a
  `# shellcheck source=lib/<name>.sh` line (CI runs `shellcheck -x`). `tests/formats.bats` fails on
  a re-implemented regex/idiom outside `lib/`.
- Every workflow declares an explicit minimal `permissions` block — enforced by a test.
- A workflow that runs tests gates that step on `inputs.skip_tests` (`required: false`,
  `default: 'false'`) so the consumer can switch them off — enforced by a test.

## Tests

- bats in `tests/`, helpers in `tests/helpers.bash` (`repo_root`, `output_value`).
- Two kinds: unit tests of action scripts, and **guard tests** asserting workflow YAML itself
  (permissions, npm cache, docker tags, auto-deploy wiring). Editing a workflow may break a guard
  test on purpose — change the test only when the rule it guards has really changed.
- External commands (`curl`, `gh`) are stubbed by putting a fake executable first on `PATH`.

## Conventions that bite

- Commit message (husky hook, first line only): `[GA-<digits>] <type>(<scope>): <subject>`;
  type ∈ feature|bugfix|ci|config|refactor|test|docs (exact match); scope and subject lowercase;
  subject ≤ 125. Rules live in `lib/commit.sh`.
- "Latest tag" is resolved by creation date (`--sort=-creatordate`), never by name: repos use both
  `dd.mm.yyyy` and `vX.Y.Z` tags, and name sorting picks the wrong one on date tags.
- Application version comes from the `app-version` action with `mode: ref`; builds release only
  on tag runs (`github.ref_type == 'tag'`), untagged runs build without a release.

## Docs

- README, docs and code comments are in Russian; this file is English.
- A change is not finished until the matching doc is updated: `docs/workflows.md` (inputs/steps),
  `docs/conventions.md` (permissions and secrets tables), `docs/actions.md`, `docs/testing.md`
  (test table), README tables.
- `docs/modernization.md` lists legacy left in place on purpose (`docker.pkg.github.com`, archived
  release actions, `golint`, `@master` pins). Do not silently modernise those.

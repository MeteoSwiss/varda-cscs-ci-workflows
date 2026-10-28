# varda-cscs-ci-workflows

Shared [CSCS-CI](https://docs.cscs.ch/services/cicd/) building blocks for MeteoSwiss
repositories: the runner for the bare-metal clusters (balfrin, linard) and the script
fragments every pipeline repeats (strict-mode preamble and logging, a per-pipeline
workdir and its cleanup, a pinned uv). It is a thin layer on top of
[cscs-ci/recipes](https://gitlab.com/cscs-ci/recipes), in the spirit of
[ecmwf/reusable-workflows](https://github.com/ecmwf/reusable-workflows).

The repository is public because GitLab's `include: remote` cannot authenticate.

- [Usage](#usage)
- [Switching cluster](#switching-cluster)
- [Building blocks](#building-blocks): [runners](#runners) · [shell](#shell) · [env](#env) ·
  [uenv](#uenv) · [uv](#uv) · [devml](#devml)
- [Triggering from GitHub](#triggering-from-github)
- [Versioning](#versioning)
- [Migrating a repository](#migrating-a-repository)
- [Testing](#testing)

## Usage

One include gives you cscs-ci's templates, the cluster switch and every v1 block:

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/MeteoSwiss/varda-cscs-ci-workflows/main/v1/.ci-ext-mch.yml'

.runner:
  extends: [.baremetal-runner-mch]
  variables:
    SLURM_TIMELIMIT: '00:30:00'
    MCH_WORK_NAME: 'my-repo-ci'

tests:
  extends: [.runner]
  script:
    - !reference [.mch-sh-preamble, script]
    - !reference [.mch-log-ci-context, script]
    - !reference [.mch-env-paths, script]
    - !reference [.mch-install-uv, script]
    - !reference [.mch-uv-sync, script]
    - uv run pytest
    - !reference [.mch-cleanup, script]
```

Script fragments are pulled in with `!reference [.name, script]`. GitLab concatenates
every referenced fragment into one shell, so the functions and exports of one fragment
are in scope for the next: **reference order matters**, and `.mch-sh-preamble` always
comes first. A fragment's inputs are plain CI variables (job or pipeline `variables:`)
with shell-side defaults, so you only set the ones you want to change.

[`examples/consumer.yml`](examples/consumer.yml) is a complete multi-job pipeline:
build an environment in one job, use it in the next, clean up in any case.

Never set `FIRECREST_SYSTEM`, `F7T_URL` or `ARCH` in a consumer — that is what the
runners are for.

## Switching cluster

[`cluster.yml`](cluster.yml) holds the one value that decides where
`.baremetal-runner-mch` lands:

```yaml
.mch-cluster:
  variables:
    FIRECREST_SYSTEM: 'balfrin'  # balfrin | linard
```

It is deliberately outside the version directories, so **one commit to `cluster.yml`
moves every consumer of every version at once**, without touching them. balfrin and
linard sit behind the same FirecREST endpoint and are both x86_64, so nothing else
changes. raw.githubusercontent.com caches for about five minutes: new pipelines see the
switch after that.

Before switching, make sure the consumers can build on the target — e.g. a devml
workspace needs a `<cluster>-gpu` dependency group for it. A job that must not move uses
`.baremetal-runner-mch-balfrin` or `.baremetal-runner-mch-linard`.

## Building blocks

All of v1 is defined in one file, [`v1/.ci-ext-mch.yml`](v1/.ci-ext-mch.yml), one
section per block; only the cluster switch, `cluster.yml`, is a file of its own.

### Runners

| Name | Lands on |
|---|---|
| `.baremetal-runner-mch` | whichever cluster `cluster.yml` names — use this by default |
| `.baremetal-runner-mch-balfrin` | balfrin, always |
| `.baremetal-runner-mch-linard` | linard, always |

All three extend cscs-ci's generic `.f7t-baremetal-runner` (nothing santis-specific is
inherited) and set `F7T_URL: https://api.cscs.ch/mch/firecrest/v2`, `ARCH: x86_64`,
`SLURM_JOB_NUM_NODES: 1`, `SLURM_NTASKS: 1`. Everything else is cscs-ci's default —
notably `SLURM_TIMELIMIT: 00:15:00`; override what your job needs in its `variables:`.

### shell

| Fragment | What it does | Inputs |
|---|---|---|
| `.mch-sh-preamble` | `set -euo pipefail` and a `banner()` for section headers. Reference it first. | – |
| `.mch-log-ci-context` | Logs host, requested vs. actual cluster, project, ref, SHA, pipeline and job. | – |
| `.mch-log-tool-versions` | Logs the version of each tool, or `MISSING`. | `MCH_LOG_TOOLS` (default `git curl yq uv python3`) |
| `.mch-verify-main` | Fails unless the pipeline runs on `main` — for pipelines that publish. | – |
| `.mch-assert-cluster` | Fails unless the job runs on the expected cluster (`CLUSTER_NAME`, then `scontrol`). | `MCH_EXPECTED_CLUSTER` (default `$FIRECREST_SYSTEM`) |

### env

Compute nodes have no mounted home, so HOME moves into a per-pipeline workdir on
`$SCRATCH`. `$SCRATCH` is on every node and `CI_PIPELINE_ID` is the same in every job,
so separate jobs (separate SLURM allocations) can hand state over through it.

| Fragment / job | What it does | Inputs |
|---|---|---|
| `.mch-env-paths` | Exports `WORK`, `HOME=$WORK/home`, `PATH=$HOME/.local/bin:$PATH`, `UV_CACHE_DIR`, and creates them. | `MCH_WORK_DIR` (verbatim, wins), else `MCH_WORK_NAME` → `$SCRATCH/$MCH_WORK_NAME/$CI_PIPELINE_ID` (default name `<project>-ci`); `UV_CACHE_DIR` (default `$SCRATCH/.cache/uv`, kept across pipelines) |
| `.mch-cleanup` | `rm -rf $WORK`. Refuses an empty `WORK`, `/`, `$SCRATCH` or `$CI_PROJECT_DIR`. Needs `.mch-env-paths`. | – |
| `.mch-cleanup-on-exit` | Registers the same removal as a `trap`, so `$WORK` goes however the script ends — success, a failed command, or a cancel (TERM). Reference it right after `.mch-env-paths`. Only for single-job pipelines: a later job could not reuse `$WORK`. | `MCH_KEEP_WORK` (default `false`; `true` keeps `$WORK`, e.g. to inspect a failed run) |
| `.mch-cleanup-job` | A whole job: `when: always`, no checkout, preamble → env-paths → cleanup. Add a runner and a `stage:`. | as above |

```yaml
cleanup:
  extends: [.runner, .mch-cleanup-job]
  stage: cleanup
```

To work in the runner's build directory instead (single-job pipelines), set
`MCH_WORK_DIR: $CI_PROJECT_DIR` — `.mch-cleanup` then refuses, by design.

### uenv

Pull containerized HPC software stacks from [uenv](https://www.uenv.io/).

| Fragment | What it does | Inputs |
|---|---|---|
| `.mch-pull-uenv` | Pulls a uenv container image. Needs `.mch-sh-preamble`. | `MCH_UENV_IMAGE` (required, no default) |

Example: set the image in your job's variables, then reference the block:

```yaml
mytest:
  extends: [.baremetal-runner-mch]
  variables:
    MCH_UENV_IMAGE: 'fdb/5.21:v2'
  script:
    - !reference [.mch-sh-preamble, script]
    - !reference [.mch-pull-uenv, script]
    - uenv run <your command>
```

### uv

| Fragment | What it does | Inputs |
|---|---|---|
| `.mch-install-uv` | Installs a pinned uv into `$HOME/.local/bin` (skipped if that version is already there, e.g. from an earlier job), exports the uv Python settings. Needs `.mch-env-paths`. | `MCH_UV_VERSION` (default `0.11.32`), `UV_PYTHON_PREFERENCE` (default `only-managed`), `UV_PYTHON_DOWNLOADS` (default `automatic`) |
| `.mch-uv-sync` | `uv sync` in the current directory. | `MCH_UV_SYNC_ARGS` (e.g. `--dev`, `--group cpu`) |

`only-managed` keeps uv off the nodes' `/usr/bin/python3`, which has no `Python.h`
(triton JIT-compiles against it), and makes a failed Python download an error instead
of a silent fallback.

### devml

Blocks for the CI of [devml](https://github.com/MeteoSwiss/devml) workspaces (e.g.
varda-forecaster-det-sgm): clone devml, fetch the workspace at the CI commit, pin devml to
the ref its `workspace.yaml` declares, build the venv — and the workspace's whole
`release` and `register` pipelines. devml fetches the workspace itself, so the jobs need
no checkout. devml lives at `$DEVML`, the workspace at `$WS`, both inside `$WORK`, where
a later job of the pipeline finds them again.

| Fragment / job | What it does |
|---|---|
| `.mch-devml-runner` | `.baremetal-runner-mch` with `GIT_STRATEGY: none` and `SLURM_TIMELIMIT: 00:45:00` (`just sync` downloads the cu124 torch stack). |
| `.mch-devml-setup` | Paths, tool versions, git auth, clone devml, tooling (pinned uv, just, devml's tooling venv), fetch + pin + `workspace-check` + `just sync`. Leaves cwd at `$DEVML`. Needs `.mch-sh-preamble`, `.mch-env-paths`. |
| `.mch-devml-reuse` | In a later job: re-derives `$DEVML`/`$WS`, checks setup's just, workspace and venv are there, cd `$DEVML`. Needs the same. |
| `.mch-devml-release-job` | The whole `release` pipeline: `model_release.py` registers `MODEL` into MLflow, the result goes into `workspace.yaml`'s `release` block, which is committed if it changed, and a `<version>.<patch>` tag is pushed. Main only; one at a time (`resource_group: model-release`); `$WORK` is removed however it ends (`.mch-cleanup-on-exit`). |
| `.mch-devml-register-job` | The whole `register` pipeline: `just model-register` copies `MODEL` into the store, the `model/<name>` tag is pushed — or the model is unregistered again (`just model-unregister`) if the push fails. Main only; one at a time (`resource_group: model-register`); `$WORK` is removed however it ends. |

`.mch-devml-setup` is built from `.mch-devml-paths`, `.mch-devml-git-auth`,
`.mch-devml-clone`, `.mch-devml-tooling` and `.mch-devml-workspace`, which can be
referenced one by one too; the jobs add `.mch-devml-verify-main` and
`.mch-devml-checkout-branch`.

| Input | Default | |
|---|---|---|
| `MODEL` | – | release/register: a key under `models:` in `workspace.yaml` (required). |
| `MLFLOW_TRACKING_TOKEN`, `MLFLOW_RUN_ID`, `MLFLOW_TRACKING_URI` | – | release: passed to `model_release.py`; the token is only needed when the checkpoint changed. |
| `MCH_KEEP_WORK` | `false` | release/register: `true` keeps `$WORK` on `$SCRATCH` after the job, e.g. to inspect a failed run. |
| `MCH_DEVML_DRY_RUN` | `false` | `true`: check everything, write nothing — no MLflow, store copy, commit, tag or push — on any branch. |
| `MCH_DEVML_SYNC` | `true` (`false` in release) | Build the venv with `just sync`. |
| `MCH_DEVML_STORE` | `/store_new/mch/msopr/ml/models` | register's model store. |
| `MCH_DEVML_REPO` | `git@github.com:MeteoSwiss/devml.git` | |
| `MCH_DEVML_SSH_KEY` | `$SCRATCH/.ssh/id_ed25519` | Key for GitHub. |
| `MCH_DEVML_SETUP_ARGS` | `--just --tooling --anemoi-settings` | devml's `hpc/bin/setup.sh` actions. |
| `MCH_DEVML_GIT_EMAIL`, `MCH_DEVML_GIT_NAME` | `cscs-ci@meteoswiss.ch`, `CSCS CI` | Author of release commits and tags. |

A workspace's `.cscs-ci/release.yaml` is then, whole:

```yaml
include:
  - remote: 'https://raw.githubusercontent.com/MeteoSwiss/varda-cscs-ci-workflows/main/v1/.ci-ext-mch.yml'

release:
  extends: [.mch-devml-release-job]
```

and `register.yaml` the same with `.mch-devml-register-job`. Pushing to `main` and
pushing tags needs the project's CI job token to have push rights on protected branches.
The tests pipeline keeps what it runs and shares the rest — see
[`examples/devml-tests.yml`](examples/devml-tests.yml).

## Triggering from GitHub

[`.github/workflows/trigger-cscs-ci.yml`](.github/workflows/trigger-cscs-ci.yml) is a
reusable workflow that starts one of the caller's CSCS-CI pipelines through the
[API-call trigger](https://docs.cscs.ch/services/cicd/#api-call-triggering), from `main`
only unless `main-only: false`. The caller needs the repository secrets
`CSCS_CI_REPOSITORY_ID` and `CSCS_CI_WEBHOOK_SECRET`:

```yaml
on:
  workflow_dispatch:
    inputs:
      model: {description: "Model to release (a key under models: in workspace.yaml)", required: true}
      mlflow_tracking_token: {description: "Only needed if the checkpoint changed", required: false}

jobs:
  release:
    uses: MeteoSwiss/varda-cscs-ci-workflows/.github/workflows/trigger-cscs-ci.yml@main
    with:
      pipeline: release
      variables: |
        MODEL: ${{ toJSON(inputs.model) }}
    secrets:
      CSCS_CI_REPOSITORY_ID: ${{ secrets.CSCS_CI_REPOSITORY_ID }}
      CSCS_CI_WEBHOOK_SECRET: ${{ secrets.CSCS_CI_WEBHOOK_SECRET }}
      SECRET_VARIABLES: |
        MLFLOW_TRACKING_TOKEN: ${{ toJSON(inputs.mlflow_tracking_token) }}
```

`variables` are shown in the log, `SECRET_VARIABLES` are masked. Wrap each interpolated
value in `toJSON()` so that it stays one quoted YAML string. For a dry run from a
branch, pass `MCH_DEVML_DRY_RUN: 'true'` and `main-only: false`.

## Versioning

Versions are directories on `main`; `main` is the only branch consumers use.

- Fixes and **additions** (a new fragment, a new optional input) go into the current
  version.
- **Breaking changes** go into a new directory (`v2/`), leaving the old one as it is:
  renaming or removing a fragment or input, changing a default's meaning, or changing
  what a fragment expects to have run before it.
- `cluster.yml` is unversioned on purpose — see [Switching cluster](#switching-cluster).
- Hidden keys are prefixed `.mch-` so they cannot collide with a consumer's own.

Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Migrating a repository

1. Replace the `include:` of cscs-ci's `.ci-ext.yml` with the one above.
2. Replace the local `.baremetal-runner-balfrin` (or similar) with a local `.runner` that
   extends `.baremetal-runner-mch` and sets only what is the repository's own
   (`SLURM_TIMELIMIT`, `GIT_STRATEGY`, `MCH_WORK_NAME`, ...). Drop `FIRECREST_SYSTEM`,
   `F7T_URL`, `ARCH`, `UV_PYTHON_*`.
3. Replace the local copies of the preamble, logging, workdir, uv install and cleanup
   fragments with the `.mch-*` ones; keep what is genuinely the repository's own.
4. Lint it against the current blocks: `tests/gitlab-lint.sh path/to/your/ci.yml`.

## Testing

`main` is protected: nothing merges unless both of these pass.

- **Static checks** — GitHub Actions ([`static.yml`](.github/workflows/static.yml)), on
  every PR:
  - `yamllint` over every file;
  - `gitlab-ci schema` — GitLab's CI JSON schema (`check-jsonschema`) per file and on
    each merged example consumer;
  - `shellcheck` — every script block, extracted by [`tests/shellcheck.sh`](tests/shellcheck.sh);
  - `includes on main` — every URL to this repository names `main`, and the `local` and
    `remote` includes of `v1/.ci-ext-mch.yml` match ([`tests/includes.sh`](tests/includes.sh));
  - `gitlab lint` — GitLab's own linter (`POST /projects/:id/ci/lint`) on each example
    consumer merged with the blocks of the PR ([`tests/gitlab-lint.sh`](tests/gitlab-lint.sh));
  - `merged pipeline` — `gitlab-ci-local --list` on the same merged files, which resolves
    every `extends` and `!reference` without a token;
  - `actionlint` — the GitHub workflows, `trigger-cscs-ci.yml` among them.

  A consumer pulls the blocks from `main`, so linting it as-is would test `main`;
  [`tests/flatten.sh`](tests/flatten.sh) instead merges the checkout's blocks into it.
- **Integration test** — this repository's own cscs-ci pipeline `integration`
  ([`.cscs-ci/integration.yml`](.cscs-ci/integration.yml)), status `cscs/integration`. It includes
  `v1/.ci-ext-mch.yml` with `include: local`, so the PR's blocks are what runs; inside
  this project the file also switches its nested include of `cluster.yml` to `local`
  (once `.mch-self-project` holds the mirror's project id). One job, on
  `.baremetal-runner-mch`, runs the preamble, the workdir, pulls a uenv image, installs uv
  and runs a `uv sync` on a uv-managed Python, then checks it landed on the cluster
  `cluster.yml` names — so a PR that switches cluster is tested on the new cluster before
  it moves anyone. The devml blocks are not run here — they need a workspace; their
  [examples](examples/) are linted, and a workspace can run its release or register with
  `MCH_DEVML_DRY_RUN: 'true'` from a branch.

cscs-ci does not run pipelines for PRs from forks: push branches to this repository.

Run the token-free checks locally with:

```bash
uvx yamllint --strict .
tests/shellcheck.sh
tests/includes.sh
for f in examples/*.yml; do tests/flatten.sh "$f" > "/tmp/$(basename "$f" .yml).merged.yml"; done
uvx check-jsonschema --builtin-schema vendor.gitlab-ci --data-transform gitlab-ci --regex-variant nonunicode \
  cluster.yml v1/.ci-ext-mch.yml .cscs-ci/*.yml examples/*.yml /tmp/*.merged.yml
```

## License

[BSD 3-Clause](LICENSE)

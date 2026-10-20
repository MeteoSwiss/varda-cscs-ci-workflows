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
- [Building blocks](#building-blocks): [runners](#runners) · [shell](#shell-v1shellyml) ·
  [env](#env-v1envyml) · [uv](#uv-v1uvyml)
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

### Runners

Defined in [`v1/.ci-ext-mch.yml`](v1/.ci-ext-mch.yml).

| Name | Lands on |
|---|---|
| `.baremetal-runner-mch` | whichever cluster `cluster.yml` names — use this by default |
| `.baremetal-runner-mch-balfrin` | balfrin, always |
| `.baremetal-runner-mch-linard` | linard, always |

All three extend cscs-ci's generic `.f7t-baremetal-runner` (nothing santis-specific is
inherited) and set `F7T_URL: https://api.cscs.ch/mch/firecrest/v2`, `ARCH: x86_64`,
`SLURM_JOB_NUM_NODES: 1`, `SLURM_NTASKS: 1`. Everything else is cscs-ci's default —
notably `SLURM_TIMELIMIT: 00:15:00`; override what your job needs in its `variables:`.

### shell ([`v1/shell.yml`](v1/shell.yml))

| Fragment | What it does | Inputs |
|---|---|---|
| `.mch-sh-preamble` | `set -euo pipefail` and a `banner()` for section headers. Reference it first. | – |
| `.mch-log-ci-context` | Logs host, requested vs. actual cluster, project, ref, SHA, pipeline and job. | – |
| `.mch-log-tool-versions` | Logs the version of each tool, or `MISSING`. | `MCH_LOG_TOOLS` (default `git curl yq uv python3`) |
| `.mch-verify-main` | Fails unless the pipeline runs on `main` — for pipelines that publish. | – |
| `.mch-assert-cluster` | Fails unless the job runs on the expected cluster (`CLUSTER_NAME`, then `scontrol`). | `MCH_EXPECTED_CLUSTER` (default `$FIRECREST_SYSTEM`) |

### env ([`v1/env.yml`](v1/env.yml))

Compute nodes have no mounted home, so HOME moves into a per-pipeline workdir on
`$SCRATCH`. `$SCRATCH` is on every node and `CI_PIPELINE_ID` is the same in every job,
so separate jobs (separate SLURM allocations) can hand state over through it.

| Fragment / job | What it does | Inputs |
|---|---|---|
| `.mch-env-paths` | Exports `WORK`, `HOME=$WORK/home`, `PATH=$HOME/.local/bin:$PATH`, `UV_CACHE_DIR`, and creates them. | `MCH_WORK_DIR` (verbatim, wins), else `MCH_WORK_NAME` → `$SCRATCH/$MCH_WORK_NAME/$CI_PIPELINE_ID` (default name `<project>-ci`); `UV_CACHE_DIR` (default `$SCRATCH/.cache/uv`, kept across pipelines) |
| `.mch-cleanup` | `rm -rf $WORK`. Refuses an empty `WORK`, `/`, `$SCRATCH` or `$CI_PROJECT_DIR`. Needs `.mch-env-paths`. | – |
| `.mch-cleanup-job` | A whole job: `when: always`, no checkout, preamble → env-paths → cleanup. Add a runner and a `stage:`. | as above |

```yaml
cleanup:
  extends: [.runner, .mch-cleanup-job]
  stage: cleanup
```

To work in the runner's build directory instead (single-job pipelines), set
`MCH_WORK_DIR: $CI_PROJECT_DIR` — `.mch-cleanup` then refuses, by design.

### uv ([`v1/uv.yml`](v1/uv.yml))

| Fragment | What it does | Inputs |
|---|---|---|
| `.mch-install-uv` | Installs a pinned uv into `$HOME/.local/bin` (skipped if that version is already there, e.g. from an earlier job), exports the uv Python settings. Needs `.mch-env-paths`. | `MCH_UV_VERSION` (default `0.11.32`), `UV_PYTHON_PREFERENCE` (default `only-managed`), `UV_PYTHON_DOWNLOADS` (default `automatic`) |
| `.mch-uv-sync` | `uv sync` in the current directory. | `MCH_UV_SYNC_ARGS` (e.g. `--dev`, `--group cpu`) |

`only-managed` keeps uv off the nodes' `/usr/bin/python3`, which has no `Python.h`
(triton JIT-compiles against it), and makes a failed Python download an error instead
of a silent fallback.

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
  - `gitlab-ci schema` — GitLab's CI JSON schema (`check-jsonschema`) per file and on the
    merged example consumer;
  - `shellcheck` — every script block, extracted by [`tests/shellcheck.sh`](tests/shellcheck.sh);
  - `gitlab lint` — GitLab's own linter (`POST /projects/:id/ci/lint`) on the example
    consumer merged with the blocks of the PR ([`tests/gitlab-lint.sh`](tests/gitlab-lint.sh));
  - `merged pipeline` — `gitlab-ci-local --list` on the same merged file, which resolves
    every `extends` and `!reference` without a token.

  A consumer pulls the blocks from `main`, so linting it as-is would test `main`;
  [`tests/flatten.sh`](tests/flatten.sh) instead merges the checkout's blocks into it.
- **Integration test** — this repository's own cscs-ci pipeline `integration`
  ([`.cscs/integration.yml`](.cscs/integration.yml)), status `cscs/integration`. It includes
  the blocks with `include: local`, and `v1/.ci-ext-mch.yml` switches its own nested
  includes to `local` inside this project, so the PR commit is what runs. One job, on
  `.baremetal-runner-mch`, runs the preamble, the workdir, the uv install and a `uv sync`
  on a uv-managed Python, then checks it landed on the cluster `cluster.yml` names — so a
  PR that switches cluster is tested on the new cluster before it moves anyone.

cscs-ci does not run pipelines for PRs from forks: push branches to this repository.

Run the token-free checks locally with:

```bash
uvx yamllint --strict .
tests/shellcheck.sh
tests/flatten.sh > /tmp/merged.gitlab-ci.yml
uvx check-jsonschema --builtin-schema vendor.gitlab-ci --data-transform gitlab-ci --regex-variant nonunicode \
  cluster.yml v1/*.yml v1/.ci-ext-mch.yml .cscs/*.yml examples/*.yml /tmp/merged.gitlab-ci.yml
```

## License

[BSD 3-Clause](LICENSE)

# Changelog

All notable changes are listed here, newest first, in the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. Versions are directories
on `main` (see the README's *Versioning*); entries name the directory they touch.

## [Unreleased]

### Added
- `cluster.yml`: `.mch-cluster`, the one switch between linard and balfrin.
- `v1/.ci-ext-mch.yml`: single entry point, holding every v1 block (only `cluster.yml`
  is included):
  - runners: `.baremetal-runner-mch`, `.baremetal-runner-mch-balfrin`,
    `.baremetal-runner-mch-linard`.
  - shell: `.mch-sh-preamble`, `.mch-log-ci-context`, `.mch-log-tool-versions`,
    `.mch-verify-main`, `.mch-assert-cluster`.
  - env: `.mch-env-paths`, `.mch-cleanup`, `.mch-cleanup-job`.
  - uenv: `.mch-pull-uenv` (pulls containerized HPC software stacks).
  - uv: `.mch-install-uv` (uv 0.11.32, managed Python only), `.mch-uv-sync`.

### Changed
- `v1/`: `shell.yml`, `env.yml`, `uenv.yml` and `uv.yml` folded into `.ci-ext-mch.yml`,
  so its only nested include of this repository is `cluster.yml`, and a consumer
  pointed at a branch runs that branch's blocks.

### Fixed
- `v1/.ci-ext-mch.yml`: the nested `remote` includes (and the usage comment) pointed at
  the `init` branch instead of `main`; since `v1/uenv.yml` was added, the 404 on
  `init/v1/uenv.yml` stopped every consumer pipeline from being created.

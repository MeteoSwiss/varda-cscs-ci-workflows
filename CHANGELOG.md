# Changelog

All notable changes are listed here, newest first, in the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. Versions are directories
on `main` (see the README's *Versioning*); entries name the directory they touch.

## [Unreleased]

### Added
- `cluster.yml`: `.mch-cluster`, the one switch between linard and balfrin.
- `v1/.ci-ext-mch.yml`: single entry point; `.baremetal-runner-mch`,
  `.baremetal-runner-mch-balfrin`, `.baremetal-runner-mch-linard`.
- `v1/shell.yml`: `.mch-sh-preamble`, `.mch-log-ci-context`, `.mch-log-tool-versions`,
  `.mch-verify-main`, `.mch-assert-cluster`.
- `v1/env.yml`: `.mch-env-paths`, `.mch-cleanup`, `.mch-cleanup-job`.
- `v1/uenv.yml`: `.mch-pull-uenv` (pulls containerized HPC software stacks).
- `v1/uv.yml`: `.mch-install-uv` (uv 0.11.32, managed Python only), `.mch-uv-sync`.

### Fixed
- `v1/.ci-ext-mch.yml`: the nested `remote` includes (and the usage comment) pointed at
  the `init` branch instead of `main`; since `v1/uenv.yml` was added, the 404 on
  `init/v1/uenv.yml` stopped every consumer pipeline from being created.

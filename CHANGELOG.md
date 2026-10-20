# Changelog

All notable changes are listed here, newest first, in the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. Versions are directories
on `main` (see the README's *Versioning*); entries name the directory they touch.

## [Unreleased]

### Added
- `cluster.yml`: `.mch-cluster`, the one switch for `.baremetal-runner-mch` (balfrin).
- `v1/.ci-ext-mch.yml`: single entry point; `.baremetal-runner-mch`,
  `.baremetal-runner-mch-balfrin`, `.baremetal-runner-mch-linard`.
- `v1/shell.yml`: `.mch-sh-preamble`, `.mch-log-ci-context`, `.mch-log-tool-versions`,
  `.mch-verify-main`, `.mch-assert-cluster`.
- `v1/env.yml`: `.mch-env-paths`, `.mch-cleanup`, `.mch-cleanup-job`.
- `v1/uv.yml`: `.mch-install-uv` (uv 0.11.32, managed Python only), `.mch-uv-sync`.

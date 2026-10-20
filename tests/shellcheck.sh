#!/usr/bin/env bash
# tests/shellcheck.sh — shellcheck every script block in the CI files.
#
#   tests/shellcheck.sh [file.yml ...]    (default: every CI file of this repo)
#
# Each job's before_script/script/after_script lines are written out as one
# bash script (`!reference` items are skipped — the fragment they point at is
# checked on its own), behind the strict mode .mch-sh-preamble sets for real,
# and handed to shellcheck. SC2154 (variable referenced
# but not assigned) is off: CI and node variables are set outside the script.
# Needs mikefarah yq v4 and shellcheck.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if (($# == 0)); then
  set -- "$root/cluster.yml" "$root"/v1/*.yml "$root"/v1/.ci-ext-mch.yml "$root"/.cscs/*.yml "$root"/examples/*.yml
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

status=0
for f in "$@"; do
  for job in $(yq -r 'to_entries[] | select(.value | type == "!!map") | select(.value | has("script") or has("before_script") or has("after_script")) | .key' "$f"); do
    out="$tmp/$(basename "$f")__${job#.}.sh"
    {
      echo "# shellcheck shell=bash disable=SC2154"
      echo "# $f: $job"
      echo "set -euo pipefail"
      key="$job" yq -r '.[strenv(key)] | (.before_script // []) + (.script // []) + (.after_script // []) | .[] | select(tag != "!reference")' "$f"
    } > "$out"
    if shellcheck -s bash "$out"; then
      echo "ok   ${f#"$root"/} $job"
    else
      echo "FAIL ${f#"$root"/} $job"
      status=1
    fi
  done
done
exit "$status"

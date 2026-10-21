#!/usr/bin/env bash
# tests/flatten.sh — print one self-contained GitLab CI file: this checkout's
# building blocks merged with a consumer, for the lint checks.
#
#   tests/flatten.sh [consumer.yml]     (default: examples/consumer.yml)
#
# A consumer includes v1/.ci-ext-mch.yml from main on raw.githubusercontent.com,
# and its nested include of cluster.yml points at main as well, so linting the
# consumer as-is would test main, not the change under review. Instead the
# consumer's includes of this repository are dropped and this checkout's files
# are merged in as GitLab merges includes: later files deep-merge over earlier
# ones, and the consumer's own keys win. Every other include (cscs-ci's
# templates, the consumer's own) is kept for the linter to resolve. Needs
# mikefarah yq v4.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
consumer="${1:-$root/examples/consumer.yml}"
# Our files, in GitLab's merge order: the `local` twins of .ci-ext-mch.yml's
# nested includes (cluster.yml), then the file itself.
mapfile -t blocks < <(yq -r '.include[] | select(has("local")) | .local' "$root/v1/.ci-ext-mch.yml" | sed "s|^|$root|")
blocks+=("$root/v1/.ci-ext-mch.yml")

# Includes of this repository: any `local` in our own files, any remote URL of ours.
ours='(type == "!!map" and ((has("local") and $f != "consumer") or ((.remote // "") | test("MeteoSwiss/varda-cscs-ci-workflows/"))))
      or (type == "!!str" and test("MeteoSwiss/varda-cscs-ci-workflows/"))'

includes=""
for f in "${blocks[@]}" "$consumer"; do
  tag=$([[ $f == "$consumer" ]] && echo consumer || echo block)
  includes+="$(f=$tag yq -o json -I0 "[(.include // []) | (select(type == \"!!seq\") // [.]) | .[] | select(strenv(f) as \$f | ($ours) | not)]" "$f")"$'\n'
done

{
  echo "include:"
  printf '%s' "$includes" | yq -p json -o yaml -I2 eval-all '. as $i ireduce ([]; . + $i) | unique_by(tojson)' | sed 's/^/  /'
  yq eval-all '
      explode(.) | del(.include) | del(.".mch-self-project") | del(.".mch-other-project")
    ' "${blocks[@]}" "$consumer" | yq eval-all '. as $d ireduce ({}; . * $d) | ... comments = ""'
}

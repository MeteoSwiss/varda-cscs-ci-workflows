#!/usr/bin/env bash
# tests/gitlab-lint.sh — validate a consumer, merged with this checkout's
# building blocks (tests/flatten.sh), with GitLab's own CI linter.
#
#   GITLAB_LINT_TOKEN=... GITLAB_LINT_PROJECT_ID=... tests/gitlab-lint.sh [consumer.yml]
#
# The lint endpoint is per project and needs a token with Developer access to
# it (the project-less /api/v4/ci/lint was removed in GitLab 16.0); any
# gitlab.com project will do — the content is linted, not the project. GitLab
# resolves the remaining includes (cscs-ci's templates) itself.
# Needs curl, jq and mikefarah yq v4.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${GITLAB_LINT_TOKEN:?needs a gitlab.com token}"
: "${GITLAB_LINT_PROJECT_ID:?needs the id of a gitlab.com project the token can create pipelines in}"
api="${GITLAB_API_URL:-https://gitlab.com/api/v4}"

response="$(
  "$root/tests/flatten.sh" "$@" \
    | jq -Rs '{content: ., include_merged_yaml: false}' \
    | curl -sSf -X POST "$api/projects/$GITLAB_LINT_PROJECT_ID/ci/lint" \
        -H "PRIVATE-TOKEN: $GITLAB_LINT_TOKEN" -H 'Content-Type: application/json' --data-binary @-
)"

jq -r '.warnings[]? | "warning: \(.)"' <<<"$response"
jq -r '.errors[]? | "error: \(.)"' <<<"$response"
if [ "$(jq -r '.valid' <<<"$response")" != "true" ]; then
  echo "GitLab lint: INVALID (${1:-examples/consumer.yml})" >&2
  exit 1
fi
echo "GitLab lint: valid (${1:-examples/consumer.yml})"

#!/usr/bin/env bash
# tests/includes.sh — check the URLs that point back at this repository.
#
#   tests/includes.sh
#
# Consumers follow main, and so must every nested include they pull in: a URL
# to another branch silently serves that branch's blocks, or 404s and stops
# every consumer pipeline from being created. The other checks never fetch
# these URLs (tests/flatten.sh drops them), so this one checks that:
#   - every URL to this repository in the CI files and docs names `main`;
#   - in v1/.ci-ext-mch.yml every `local` include has a `remote` twin and vice
#     versa, and each file they name exists.
# Needs mikefarah yq v4.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo='raw.githubusercontent.com/MeteoSwiss/varda-cscs-ci-workflows'
entry="$root/v1/.ci-ext-mch.yml"

status=0

# Every URL to this repository names main.
while IFS= read -r hit; do
  echo "FAIL not on main: ${hit#"$root"/}"
  status=1
done < <(grep -rnoE --include='*.yml' --include='*.md' "$repo/[^/'\" ]+" "$root" | grep -v "$repo/main\$" || true)

# Local and remote includes of the entry point name the same files.
locals="$(yq -r '.include[] | select(has("local")) | .local' "$entry" | sort)"
remotes="$(yq -r '.include[] | select(has("remote")) | .remote' "$entry" \
  | sed -n "s|^https://$repo/[^/]*||p" | sort)"
if [[ $locals != "$remotes" ]]; then
  echo "FAIL ${entry#"$root"/}: local and remote includes differ (< local, > remote):"
  diff <(echo "$locals") <(echo "$remotes") | grep '^[<>]' || true
  status=1
fi
for f in $locals; do
  if [[ ! -f $root$f ]]; then
    echo "FAIL ${entry#"$root"/}: includes $f, which does not exist"
    status=1
  fi
done

if ((status == 0)); then
  echo "ok   includes of this repository all point at main and match their local twins"
fi
exit "$status"

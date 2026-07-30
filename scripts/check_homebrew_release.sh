#!/usr/bin/env bash

set -euo pipefail

requested_tag=$1
release_tag=$2
is_draft=$3
is_prerelease=$4
latest_stable_tag=$5

if ! [[ $requested_tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Release tag must look like vX.Y.Z: %s\n' "$requested_tag" >&2
  exit 1
fi
if [[ $release_tag != "$requested_tag" ]]; then
  printf 'Release metadata does not match requested tag %s.\n' "$requested_tag" >&2
  exit 1
fi
if [[ $is_draft == true || $is_prerelease == true ]]; then
  printf 'Release %s must be published, non-draft, and non-prerelease.\n' \
    "$requested_tag" >&2
  exit 1
fi
if [[ $requested_tag != "$latest_stable_tag" ]]; then
  printf 'Release %s is not the latest stable release (%s).\n' \
    "$requested_tag" "$latest_stable_tag" >&2
  exit 1
fi

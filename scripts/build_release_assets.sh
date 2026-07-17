#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_DIR

tag=${1:-}
if [[ ! $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Usage: %s vX.Y.Z\n' "$0" >&2
  exit 2
fi

version=${tag#v}
embedded_version=$(git -C "$PROJECT_DIR" show "$tag:VERSION")
if [[ $embedded_version != "$version" ]]; then
  printf 'Tag %s contains VERSION %s, expected %s.\n' \
    "$tag" "$embedded_version" "$version" >&2
  exit 1
fi

dist_dir=${AWS_METADATA_RELEASE_DIST_DIR:-$PROJECT_DIR/dist}
archive_name="aws-metadata-agent-v${version}.tar.gz"
archive_path="$dist_dir/$archive_name"

mkdir -p "$dist_dir"
rm -f "$archive_path" "$archive_path.sha256"
git -C "$PROJECT_DIR" archive \
  --format=tar \
  --prefix="aws-metadata-agent-${version}/" \
  "$tag" | gzip -n >"$archive_path"

(
  cd "$dist_dir"
  shasum -a 256 "$archive_name" >"$archive_name.sha256"
  shasum -a 256 -c "$archive_name.sha256"
)

if tar -tzf "$archive_path" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
  printf 'Release archive contains an unsafe path.\n' >&2
  exit 1
fi

printf 'Built %s and %s.sha256\n' "$archive_path" "$archive_path"

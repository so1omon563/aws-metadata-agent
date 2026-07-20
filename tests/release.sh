#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_DIR

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/aws-metadata-release.XXXXXX")
readonly TEMP_ROOT
trap 'rm -rf "$TEMP_ROOT"' EXIT

repo="$TEMP_ROOT/repo"
mkdir -p "$repo/docs" "$repo/scripts"
cp "$PROJECT_DIR/scripts/stage_release.py" \
  "$PROJECT_DIR/scripts/check_release.py" \
  "$PROJECT_DIR/scripts/build_release_assets.sh" \
  "$PROJECT_DIR/scripts/update_homebrew_formula.py" \
  "$repo/scripts/"

cat >"$repo/VERSION" <<'EOF'
0.2.0
EOF
cat >"$repo/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

### Fixed

- Kept interactive authentication requests alive for their configured wait.

## [0.2.0] - 2026-07-16

### Added

- Homebrew installation support.

[Unreleased]: https://github.com/so1omon563/aws-metadata-agent/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/so1omon563/aws-metadata-agent/releases/tag/v0.2.0
EOF
cat >"$repo/docs/direct-install.md" <<'EOF'
version=0.2.0
sh ./install-release.sh --version 0.2.0
EOF
cat >"$repo/README.md" <<'EOF'
version=0.2.0
EOF
cat >"$repo/install-release.sh" <<'EOF'
Examples:
  ./install-release.sh --version 0.2.0
EOF

git -C "$repo" init -q
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.invalid
git -C "$repo" add .
git -C "$repo" commit -qm initial
git -C "$repo" tag v0.2.0

python3 "$repo/scripts/stage_release.py" \
  --root "$repo" --bump patch --date 2026-07-17 --no-fetch >/dev/null
[[ $(<"$repo/VERSION") == 0.2.1 ]]
grep -Fq '## [0.2.1] - 2026-07-17' "$repo/CHANGELOG.md"
grep -Fq '[Unreleased]: https://github.com/so1omon563/aws-metadata-agent/compare/v0.2.1...HEAD' \
  "$repo/CHANGELOG.md"
grep -Fq '[0.2.1]: https://github.com/so1omon563/aws-metadata-agent/compare/v0.2.0...v0.2.1' \
  "$repo/CHANGELOG.md"
grep -Fq 'version=0.2.1' "$repo/docs/direct-install.md"
grep -Fq -- '--version 0.2.1' "$repo/docs/direct-install.md"
grep -Fq 'version=0.2.1' "$repo/README.md"
grep -Fq -- '--version 0.2.1' "$repo/install-release.sh"
python3 "$repo/scripts/check_release.py" --root "$repo" --bump patch >/dev/null

printf '%s\n' 'version=0.2.0' >"$repo/docs/direct-install.md"
if python3 "$repo/scripts/check_release.py" \
  --root "$repo" --bump patch >/dev/null 2>&1; then
  printf '%s\n' 'Release checks accepted a stale direct-install version.' >&2
  exit 1
fi
printf '%s\n' \
  'version=0.2.1' \
  'sh ./install-release.sh --version 0.2.1' \
  >"$repo/docs/direct-install.md"

git -C "$repo" add VERSION CHANGELOG.md README.md docs/direct-install.md install-release.sh
git -C "$repo" commit -qm release
git -C "$repo" tag v0.2.1
AWS_METADATA_RELEASE_DIST_DIR="$TEMP_ROOT/dist" \
  "$repo/scripts/build_release_assets.sh" v0.2.1 >/dev/null
(
  cd "$TEMP_ROOT/dist"
  shasum -a 256 -c aws-metadata-agent-v0.2.1.tar.gz.sha256 >/dev/null
)
archive_version=$(tar -xOzf "$TEMP_ROOT/dist/aws-metadata-agent-v0.2.1.tar.gz" \
  aws-metadata-agent-0.2.1/VERSION)
[[ $archive_version == 0.2.1 ]]
if tar -tzf "$TEMP_ROOT/dist/aws-metadata-agent-v0.2.1.tar.gz" | \
   grep -Ev '^aws-metadata-agent-0\.2\.1/'; then
  printf '%s\n' 'Release archive contains an unexpected root.' >&2
  exit 1
fi
first_checksum=$(cut -d ' ' -f 1 \
  "$TEMP_ROOT/dist/aws-metadata-agent-v0.2.1.tar.gz.sha256")
AWS_METADATA_RELEASE_DIST_DIR="$TEMP_ROOT/dist" \
  "$repo/scripts/build_release_assets.sh" v0.2.1 >/dev/null
second_checksum=$(cut -d ' ' -f 1 \
  "$TEMP_ROOT/dist/aws-metadata-agent-v0.2.1.tar.gz.sha256")
[[ $first_checksum == "$second_checksum" ]]

formula="$TEMP_ROOT/aws-metadata-agent.rb"
cat >"$formula" <<'EOF'
class AwsMetadataAgent < Formula
  url "https://example.invalid/v0.2.0.tar.gz"
  sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  test do
    assert_equal "0.2.0\n", shell_output("#{bin}/aws-metadata version")
  end
end
EOF
archive_url='https://github.com/so1omon563/aws-metadata-agent/releases/download/v0.2.1/aws-metadata-agent-v0.2.1.tar.gz'
python3 "$repo/scripts/update_homebrew_formula.py" \
  "$formula" 0.2.1 "$archive_url" \
  "$TEMP_ROOT/dist/aws-metadata-agent-v0.2.1.tar.gz.sha256"
grep -Fq "url \"$archive_url\"" "$formula"
grep -Fq "sha256 \"$second_checksum\"" "$formula"
grep -Fq 'assert_equal "0.2.1\n"' "$formula"

workflow="$PROJECT_DIR/.github/workflows/bump.yml"
expected_release_output="release_requested: \${{ steps.bump.outputs.should_release }}"
grep -Fq "$expected_release_output" "$workflow"
grep -Fq 'git log -1 --pretty=%B' "$workflow"
if grep -Fq 'PR_TITLE:' "$workflow"; then
  printf '%s\n' 'Release preflight still validates only the PR title.' >&2
  exit 1
fi

printf '%s\n' 'Release automation tests passed.'

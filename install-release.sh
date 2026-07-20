#!/bin/sh

set -eu

readonly REPOSITORY=so1omon563/aws-metadata-agent
version=''
temp_dir=''

usage() {
  cat <<'EOF'
Usage: install-release.sh --version VERSION [-- INSTALLER OPTIONS]

Downloads a versioned aws-metadata-agent release archive, verifies it against
the SHA-256 file published with that release, and runs its existing installer.

Examples:
  ./install-release.sh --version X.Y.Z
  ./install-release.sh --version X.Y.Z -- --aws-runas "$HOME/.local/bin/aws-runas"
EOF
}

fail() {
  printf 'install-release.sh: %s\n' "$1" >&2
  exit "${2:-1}"
}

cleanup() {
  status=$?
  trap - 0 HUP INT TERM
  if [ -n "$temp_dir" ]; then
    rm -rf -- "$temp_dir"
  fi
  exit "$status"
}

while [ "$#" -gt 0 ]; do
  case $1 in
    --version)
      shift
      [ "$#" -gt 0 ] || fail '--version requires a value.' 2
      version=$1
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1. Installer options must follow --." 2
      ;;
  esac
  shift
done

for command_name in awk curl grep mktemp rm tar uname; do
  command -v "$command_name" >/dev/null 2>&1 || \
    fail "Required command not found: $command_name." 2
done

[ -n "$version" ] || fail '--version is required.' 2
printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || \
  fail "Invalid version: $version. Expected MAJOR.MINOR.PATCH." 2

platform=$(uname -s)
architecture=$(uname -m)
case "$platform/$architecture" in
  Darwin/arm64|Linux/aarch64|Linux/arm64) ;;
  *)
    fail "Unsupported platform: $platform/$architecture." 2
    ;;
esac

if command -v sha256sum >/dev/null 2>&1; then
  hash_command=sha256sum
elif command -v shasum >/dev/null 2>&1; then
  hash_command=shasum
else
  fail 'Required command not found: sha256sum or shasum.' 2
fi

archive_name="aws-metadata-agent-v${version}.tar.gz"
checksum_name="${archive_name}.sha256"
archive_url="https://github.com/${REPOSITORY}/releases/download/v${version}/${archive_name}"
checksum_url="https://github.com/${REPOSITORY}/releases/download/v${version}/${checksum_name}"
release_root="aws-metadata-agent-${version}"

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/aws-metadata-release.XXXXXX") || \
  fail 'Unable to create a temporary directory.'
trap cleanup 0
trap 'exit 1' HUP INT TERM

archive_path=$temp_dir/$archive_name
checksum_path=$temp_dir/$checksum_name

printf 'Downloading versioned release v%s from %s\n' "$version" "$archive_url"
curl --proto '=https' --tlsv1.2 --fail --location --show-error --silent \
  --output "$archive_path" "$archive_url" || fail 'Release download failed.'
curl --proto '=https' --tlsv1.2 --fail --location --show-error --silent \
  --output "$checksum_path" "$checksum_url" || \
  fail 'Published checksum download failed.'

expected_checksum=$(awk -v name="$archive_name" '
  NF {
    count++
    if (NF != 2 || length($1) != 64 || $1 !~ /^[0-9A-Fa-f]+$/ ||
        !($2 == name || $2 == "*" name)) {
      invalid = 1
    }
    checksum = tolower($1)
  }
  END {
    if (count != 1 || invalid) {
      exit 1
    }
    print checksum
  }
' "$checksum_path") || fail 'Published checksum file is invalid.'

if [ "$hash_command" = sha256sum ]; then
  hash_output=$(sha256sum "$archive_path") || fail 'Unable to hash release archive.'
else
  hash_output=$(shasum -a 256 "$archive_path") || fail 'Unable to hash release archive.'
fi
actual_checksum=${hash_output%% *}

[ "$actual_checksum" = "$expected_checksum" ] || \
  fail 'Release archive checksum does not match the published SHA-256.'
printf 'Verified SHA-256: %s\n' "$actual_checksum"

tar -tzf "$archive_path" | awk -v root="$release_root/" '
  {
    if (substr($0, 1, 1) == "/" || index($0, root) != 1) {
      exit 1
    }
    count = split($0, parts, "/")
    for (index_part = 1; index_part <= count; index_part++) {
      if (parts[index_part] == "..") {
        exit 1
      }
    }
    entries++
  }
  END {
    if (entries == 0) {
      exit 1
    }
  }
' || fail 'Release archive contains an unexpected path.'

tar -xzf "$archive_path" -C "$temp_dir" || fail 'Unable to extract release archive.'
release_dir=$temp_dir/$release_root
version_file=$release_dir/VERSION
installer=$release_dir/install.sh

if [ ! -f "$version_file" ] || [ -L "$version_file" ]; then
  fail 'Verified release does not contain a regular VERSION file.'
fi
release_version=$(awk 'NR == 1 { print; exit }' "$version_file")
[ "$release_version" = "$version" ] || \
  fail "Release VERSION is $release_version, expected $version."
if [ ! -f "$installer" ] || [ -L "$installer" ] || [ ! -x "$installer" ]; then
  fail 'Verified release does not contain an executable regular install.sh.'
fi

printf 'Verified aws-metadata-agent v%s; running its reviewed installer.\n' "$version"
"$installer" "$@"

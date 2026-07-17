#!/usr/bin/env bash

set -eu
set -o pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_DIR
readonly INSTALLER="$PROJECT_DIR/install-release.sh"
readonly FIXTURE_VERSION=9.8.7
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/aws-metadata-release-tests.XXXXXX")
readonly TEMP_ROOT
readonly MOCK_BIN="$TEMP_ROOT/bin"
readonly FIXTURE_ARCHIVE="$TEMP_ROOT/aws-metadata-agent-v${FIXTURE_VERSION}.tar.gz"
readonly FIXTURE_CHECKSUM="$FIXTURE_ARCHIVE.sha256"
readonly INSTALL_RECORD="$TEMP_ROOT/install-arguments"
readonly CURL_LOG="$TEMP_ROOT/curl-urls"

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -eu

output=''
url=''
while (($#)); do
  case $1 in
    --output)
      output=$2
      shift 2
      ;;
    --proto)
      shift 2
      ;;
    --tlsv1.2|--fail|--location|--show-error|--silent)
      shift
      ;;
    https://*)
      url=$1
      shift
      ;;
    *)
      printf 'Unexpected curl argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

printf '%s\n' "$url" >>"$MOCK_CURL_LOG"
if [[ ${MOCK_CURL_FAIL:-0} == 1 ]]; then
  exit 22
fi
case $url in
  */archive/refs/tags/v"$FIXTURE_VERSION".tar.gz)
    cp "$FIXTURE_ARCHIVE" "$output"
    ;;
  */releases/download/v"$FIXTURE_VERSION"/aws-metadata-agent-v"$FIXTURE_VERSION".tar.gz.sha256)
    cp "$FIXTURE_CHECKSUM" "$output"
    ;;
  *)
    printf 'Unexpected URL: %s\n' "$url" >&2
    exit 2
    ;;
esac
EOF

cat >"$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
set -eu

case ${1:-} in
  -s) printf '%s\n' "${MOCK_UNAME_S:-Linux}" ;;
  -m) printf '%s\n' "${MOCK_UNAME_M:-aarch64}" ;;
  *) exit 2 ;;
esac
EOF

chmod +x "$MOCK_BIN/curl" "$MOCK_BIN/uname"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1"
  else
    shasum -a 256 "$1"
  fi
}

write_checksum() {
  local checksum

  checksum=$(sha256_file "$FIXTURE_ARCHIVE")
  checksum=${checksum%% *}
  printf '%s  %s\n' "$checksum" "$(basename "$FIXTURE_ARCHIVE")" \
    >"$FIXTURE_CHECKSUM"
}

make_fixture() {
  local recorded_version=$1
  local payload_dir=$TEMP_ROOT/payload
  local release_dir=$payload_dir/aws-metadata-agent-$FIXTURE_VERSION

  rm -rf "$payload_dir"
  mkdir -p "$release_dir"
  printf '%s\n' "$recorded_version" >"$release_dir/VERSION"
  cat >"$release_dir/install.sh" <<'EOF'
#!/usr/bin/env bash
set -eu
: "${INSTALL_RECORD:?}"
printf '%s\n' "$@" >"$INSTALL_RECORD"
EOF
  chmod +x "$release_dir/install.sh"
  tar -czf "$FIXTURE_ARCHIVE" -C "$payload_dir" \
    "aws-metadata-agent-$FIXTURE_VERSION"
  write_checksum
}

assert_exit() {
  local expected=$1
  shift
  local actual=0

  "$@" >/dev/null 2>&1 || actual=$?
  if [[ $actual -ne $expected ]]; then
    printf 'Expected exit %s, received %s: %s\n' \
      "$expected" "$actual" "$*" >&2
    exit 1
  fi
}

assert_cleaned() {
  if compgen -G "$TEMP_ROOT/aws-metadata-release.*" >/dev/null; then
    printf '%s\n' 'Release installer left a temporary directory behind.' >&2
    exit 1
  fi
}

run_installer() {
  env \
    PATH="$MOCK_BIN:$PATH" \
    TMPDIR="$TEMP_ROOT" \
    FIXTURE_VERSION="$FIXTURE_VERSION" \
    FIXTURE_ARCHIVE="$FIXTURE_ARCHIVE" \
    FIXTURE_CHECKSUM="$FIXTURE_CHECKSUM" \
    INSTALL_RECORD="$INSTALL_RECORD" \
    MOCK_CURL_LOG="$CURL_LOG" \
    "$@"
}

make_fixture "$FIXTURE_VERSION"
rm -f "$INSTALL_RECORD" "$CURL_LOG"
run_installer "$INSTALLER" --version "$FIXTURE_VERSION" -- \
  --aws-runas /tmp/fake-aws-runas
installed_arguments=$(<"$INSTALL_RECORD")
expected_arguments=$'--aws-runas\n/tmp/fake-aws-runas'
if [[ $installed_arguments != "$expected_arguments" ]]; then
  printf 'Unexpected installer arguments: %s\n' "$installed_arguments" >&2
  exit 1
fi
if ! grep -Fq "/archive/refs/tags/v${FIXTURE_VERSION}.tar.gz" "$CURL_LOG" ||
   ! grep -Fq "/releases/download/v${FIXTURE_VERSION}/aws-metadata-agent-v${FIXTURE_VERSION}.tar.gz.sha256" "$CURL_LOG"; then
  printf '%s\n' 'Installer did not request the immutable archive and checksum URLs.' >&2
  exit 1
fi
assert_cleaned

assert_exit 2 run_installer "$INSTALLER"
assert_exit 2 run_installer "$INSTALLER" --version latest
assert_exit 2 run_installer env MOCK_UNAME_M=x86_64 \
  "$INSTALLER" --version "$FIXTURE_VERSION"
assert_cleaned

rm -f "$INSTALL_RECORD"
assert_exit 1 run_installer env MOCK_CURL_FAIL=1 \
  "$INSTALLER" --version "$FIXTURE_VERSION"
[[ ! -e $INSTALL_RECORD ]]
assert_cleaned

printf '%064d  %s\n' 0 "$(basename "$FIXTURE_ARCHIVE")" >"$FIXTURE_CHECKSUM"
rm -f "$INSTALL_RECORD"
assert_exit 1 run_installer "$INSTALLER" --version "$FIXTURE_VERSION"
[[ ! -e $INSTALL_RECORD ]]
assert_cleaned

printf '%s\n' 'not-a-checksum' >"$FIXTURE_CHECKSUM"
assert_exit 1 run_installer "$INSTALLER" --version "$FIXTURE_VERSION"
assert_cleaned

make_fixture "$FIXTURE_VERSION"
printf '%s\n' 'unexpected' >"$TEMP_ROOT/payload/unexpected"
tar -czf "$FIXTURE_ARCHIVE" -C "$TEMP_ROOT/payload" \
  "aws-metadata-agent-$FIXTURE_VERSION" unexpected
write_checksum
assert_exit 1 run_installer "$INSTALLER" --version "$FIXTURE_VERSION"
[[ ! -e $INSTALL_RECORD ]]
assert_cleaned

make_fixture 9.8.6
rm -f "$INSTALL_RECORD"
assert_exit 1 run_installer "$INSTALLER" --version "$FIXTURE_VERSION"
[[ ! -e $INSTALL_RECORD ]]
assert_cleaned

printf '%s\n' 'Release installer tests passed.'

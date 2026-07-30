#!/usr/bin/env bash

set -eu

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_DIR
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/aws-metadata-readiness.XXXXXX")
readonly TEMP_ROOT

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'installer-readiness test: %s\n' "$1" >&2
  exit 1
}

eval "$(sed -n '/^wait_for_metadata_endpoint()/,/^}/p' \
  "$PROJECT_DIR/install.sh")"

mkdir "$TEMP_ROOT/bin"
cat >"$TEMP_ROOT/bin/sleep" <<'EOF'
#!/bin/sh
:
EOF
cat >"$TEMP_ROOT/bin/curl" <<'EOF'
#!/bin/sh
output_file=''
while [ "$#" -gt 0 ]; do
  case $1 in
    --noproxy)
      shift
      printf 'noproxy=%s\n' "$1" >>"${MOCK_CURL_LOG:?}"
      ;;
    --output)
      shift
      output_file=$1
      ;;
    http://*)
      printf 'url=%s\n' "$1" >>"${MOCK_CURL_LOG:?}"
      ;;
  esac
  shift
done
printf '%s' "${MOCK_CURL_BODY:-}" >"$output_file"
printf '%s' "${MOCK_CURL_STATUS:-200}"
EOF
chmod +x "$TEMP_ROOT/bin/curl" "$TEMP_ROOT/bin/sleep"

MOCK_CURL_LOG=$TEMP_ROOT/curl.log
export MOCK_CURL_LOG

assert_ready() {
  if ! PATH="$TEMP_ROOT/bin:$PATH" \
    MOCK_CURL_STATUS=$1 MOCK_CURL_BODY=$2 \
    wait_for_metadata_endpoint http://example.invalid >/dev/null; then
    fail "rejected HTTP $1 response: $2"
  fi
}

assert_rejected() {
  if PATH="$TEMP_ROOT/bin:$PATH" \
    MOCK_CURL_STATUS=$1 MOCK_CURL_BODY=$2 \
    wait_for_metadata_endpoint http://example.invalid >/dev/null; then
    fail "accepted HTTP $1 response: $2"
  fi
}

assert_ready 500 'profile not set'
assert_ready 200 '{"role_arn":""}'
assert_rejected 500 $'profile not set\n'
assert_rejected 200 '{}'
assert_rejected 200 'unrelated listener'
assert_rejected 404 'not found'
grep -Fqx 'noproxy=*' "$MOCK_CURL_LOG" ||
  fail "readiness requests did not bypass proxies"
grep -Fqx 'url=http://example.invalid/profile' "$MOCK_CURL_LOG" ||
  fail "readiness requests did not target /profile"

printf '%s\n' 'Installer readiness checks passed.'

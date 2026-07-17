#!/usr/bin/env bash

set -eu

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_DIR
readonly CLI="$PROJECT_DIR/bin/aws-metadata"
readonly FIXTURES="$PROJECT_DIR/tests/fixtures"

export PATH="$FIXTURES:$PATH"
export AWS_METADATA_URL=http://127.0.0.1:9876
export AWS_METADATA_VERSION_FILE="$PROJECT_DIR/VERSION"

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/aws-metadata-cli.XXXXXX")
readonly TEMP_ROOT
trap 'rm -rf "$TEMP_ROOT"' EXIT
readonly CURL_MAX_TIME_LOG="$TEMP_ROOT/curl-max-time"
readonly CURL_CALL_LOG="$TEMP_ROOT/curl-calls"
readonly CURL_RESPONSE_QUEUE="$TEMP_ROOT/curl-responses"
readonly TRANSIENT_SAML_STS_TIMEOUT='failed to refresh cached credentials, operation error STS: AssumeRoleWithSAML, https response error StatusCode: 408, RequestID: , api error UnknownError: UnknownError'

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

assert_request_timeout() {
  local expected=$1
  shift
  local actual

  : >"$CURL_MAX_TIME_LOG"
  MOCK_CURL_MAX_TIME_LOG="$CURL_MAX_TIME_LOG" "$@" >/dev/null 2>&1
  actual=$(tail -n 1 "$CURL_MAX_TIME_LOG")
  if [[ $actual != "$expected" ]]; then
    printf 'Expected request timeout %s, received %s: %s\n' \
      "$expected" "$actual" "$*" >&2
    exit 1
  fi
}

assert_curl_calls() {
  local expected=$1
  local actual

  actual=$(wc -l <"$CURL_CALL_LOG" | tr -d ' ')
  if [[ $actual != "$expected" ]]; then
    printf 'Expected %s curl calls, received %s.\n' "$expected" "$actual" >&2
    exit 1
  fi
}

MOCK_CURL_STATUS=200 assert_exit 0 "$CLI" profile test-profile --no-open
MOCK_CURL_STATUS=200 assert_exit 0 "$CLI" use test-profile
MOCK_CURL_STATUS=401 assert_exit 4 "$CLI" use test-profile --no-open
MOCK_CURL_STATUS=401 assert_exit 4 "$CLI" profile test-profile --no-open
MOCK_CURL_STATUS=500 assert_exit 6 "$CLI" profile test-profile --no-open
MOCK_CURL_STATUS=000 assert_exit 3 "$CLI" profile test-profile --no-open
MOCK_CURL_STATUS=200 assert_exit 0 "$CLI" status --json
MOCK_CURL_STATUS=500 MOCK_CURL_BODY='profile not set' \
  assert_exit 0 "$CLI" status --json
MOCK_CURL_STATUS=500 MOCK_CURL_BODY='unexpected failure' \
  assert_exit 6 "$CLI" status --json

MOCK_CURL_STATUS=200 assert_request_timeout \
  15 "$CLI" profile test-profile --no-open
MOCK_CURL_STATUS=200 assert_request_timeout \
  305 "$CLI" use test-profile
MOCK_CURL_STATUS=200 assert_request_timeout \
  47 "$CLI" profile test-profile --open --wait 42
MOCK_CURL_STATUS=200 assert_request_timeout \
  15 "$CLI" use test-profile --wait 0
AWS_METADATA_REQUEST_TIMEOUT=75 MOCK_CURL_STATUS=200 assert_request_timeout \
  75 "$CLI" use test-profile

# Simulate a profile endpoint that needs longer than the normal 15-second
# automation timeout. Interactive selection must keep the request alive for
# its configured wait, while noninteractive selection stays bounded.
MOCK_CURL_REQUIRED_TIMEOUT=30 MOCK_CURL_STATUS=200 \
  assert_exit 0 "$CLI" use test-profile
MOCK_CURL_REQUIRED_TIMEOUT=30 MOCK_CURL_STATUS=200 \
  assert_exit 3 "$CLI" profile test-profile --no-open
AWS_METADATA_REQUEST_TIMEOUT=1 MOCK_CURL_REQUIRED_TIMEOUT=30 \
  MOCK_CURL_STATUS=200 assert_exit 5 "$CLI" use test-profile
AWS_METADATA_REQUEST_TIMEOUT=1 MOCK_CURL_REQUIRED_TIMEOUT=30 \
  MOCK_CURL_STATUS=200 assert_exit 3 "$CLI" use test-profile --wait 0

# A cold browser login can successfully persist its browser session and then
# receive a transient STS 408 during the first SAML credential exchange. The
# interactive command retries that exact response once; the warm retry can then
# complete without requiring the user to invoke the command again.
: >"$CURL_CALL_LOG"
printf '500|%s\n200|\n' "$TRANSIENT_SAML_STS_TIMEOUT" >"$CURL_RESPONSE_QUEUE"
MOCK_CURL_CALL_LOG="$CURL_CALL_LOG" \
  MOCK_CURL_RESPONSE_QUEUE="$CURL_RESPONSE_QUEUE" \
  assert_exit 0 "$CLI" use test-profile
assert_curl_calls 2

# A repeated transient response is still bounded to one retry.
: >"$CURL_CALL_LOG"
printf '500|%s\n500|%s\n200|\n' \
  "$TRANSIENT_SAML_STS_TIMEOUT" "$TRANSIENT_SAML_STS_TIMEOUT" \
  >"$CURL_RESPONSE_QUEUE"
MOCK_CURL_CALL_LOG="$CURL_CALL_LOG" \
  MOCK_CURL_RESPONSE_QUEUE="$CURL_RESPONSE_QUEUE" \
  assert_exit 6 "$CLI" use test-profile
assert_curl_calls 2

# Do not retry unrelated broker failures or noninteractive selection.
: >"$CURL_CALL_LOG"
printf '500|unexpected failure\n200|\n' >"$CURL_RESPONSE_QUEUE"
MOCK_CURL_CALL_LOG="$CURL_CALL_LOG" \
  MOCK_CURL_RESPONSE_QUEUE="$CURL_RESPONSE_QUEUE" \
  assert_exit 6 "$CLI" use test-profile
assert_curl_calls 1

: >"$CURL_CALL_LOG"
printf '500|%s\n200|\n' "$TRANSIENT_SAML_STS_TIMEOUT" >"$CURL_RESPONSE_QUEUE"
MOCK_CURL_CALL_LOG="$CURL_CALL_LOG" \
  MOCK_CURL_RESPONSE_QUEUE="$CURL_RESPONSE_QUEUE" \
  assert_exit 6 "$CLI" profile test-profile --no-open
assert_curl_calls 1

status_output=$(MOCK_CURL_STATUS=500 MOCK_CURL_BODY='profile not set' \
  "$CLI" status --json)
if [[ $status_output != \
  '{"state":"running","endpoint":"http://127.0.0.1:9876","profile":null}' ]]; then
  printf 'Unexpected empty-profile status output: %s\n' "$status_output" >&2
  exit 1
fi
assert_exit 2 "$CLI" profile

expected_version=$(<"$PROJECT_DIR/VERSION")
if [[ ! $expected_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Invalid project version: %s\n' "$expected_version" >&2
  exit 1
fi
version_output=$("$CLI" version)
if [[ $version_output != "$expected_version" ]]; then
  printf 'Unexpected version output: %s\n' "$version_output" >&2
  exit 1
fi
if [[ $("$CLI" --version) != "$version_output" ]]; then
  printf '%s\n' '--version did not match the version command.' >&2
  exit 1
fi
assert_exit 2 "$CLI" version unexpected

setup_help=$(AWS_METADATA_PACKAGE_ROOT="$PROJECT_DIR" "$CLI" setup --help)
if [[ $setup_help != *'--no-install-cli'* ]]; then
  printf '%s\n' 'Packaged setup help did not expose the installer contract.' >&2
  exit 1
fi
uninstall_help=$(AWS_METADATA_PACKAGE_ROOT="$PROJECT_DIR" "$CLI" uninstall --help)
if [[ $uninstall_help != *'Stops and removes aws-metadata-agent services'* ]]; then
  printf '%s\n' 'Packaged uninstall help did not reach the uninstaller.' >&2
  exit 1
fi
assert_exit 2 env AWS_METADATA_PACKAGE_ROOT= "$CLI" setup --help
assert_exit 2 env AWS_METADATA_PACKAGE_ROOT= "$CLI" uninstall --help
assert_exit 2 env \
  AWS_METADATA_PACKAGE_ROOT="$PROJECT_DIR" AWS_METADATA_PACKAGE_CLI= \
  "$CLI" setup --aws-runas /bin/true
assert_exit 2 env \
  AWS_METADATA_PACKAGE_ROOT="$PROJECT_DIR" AWS_METADATA_PACKAGE_CLI= \
  "$CLI" uninstall
assert_exit 2 "$PROJECT_DIR/install.sh" --package-cli relative/path
assert_exit 2 "$PROJECT_DIR/uninstall.sh" unexpected
assert_exit 2 "$PROJECT_DIR/uninstall.sh" --package-cli relative/path

bootstrap_output=$("$PROJECT_DIR/bootstrap.sh" --dry-run)
if [[ $bootstrap_output != *'/mmmorris1975/aws-runas/releases/download/'* ]]; then
  printf '%s\n' 'Bootstrap dry run did not reference the upstream repository.' >&2
  exit 1
fi
if [[ $bootstrap_output != *"$HOME/.local/bin/aws-runas"* ]]; then
  printf '%s\n' 'Bootstrap default did not use the user-local binary directory.' >&2
  exit 1
fi
if [[ $bootstrap_output != *'--configure-shell'* ]]; then
  printf '%s\n' 'Bootstrap dry run did not advertise optional shell setup.' >&2
  exit 1
fi

bootstrap_output=$(SHELL=/bin/zsh "$PROJECT_DIR/bootstrap.sh" --configure-shell --dry-run)
if [[ $bootstrap_output != *"$HOME/.zprofile"* ]] || \
   [[ $bootstrap_output != *"$HOME/.zshrc"* ]] || \
   [[ $bootstrap_output != *'aws-runas-zsh-completion'* ]]; then
  printf '%s\n' 'Bootstrap shell dry run did not describe zsh configuration.' >&2
  exit 1
fi

printf '%s\n' 'CLI tests passed.'

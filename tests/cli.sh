#!/usr/bin/env bash

set -eu

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_DIR
readonly CLI="$PROJECT_DIR/bin/aws-metadata"
readonly FIXTURES="$PROJECT_DIR/tests/fixtures"

export PATH="$FIXTURES:$PATH"
export AWS_METADATA_URL=http://127.0.0.1:9876
export AWS_METADATA_VERSION_FILE="$PROJECT_DIR/VERSION"

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

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
export AWS_METADATA_STATE_DIR="$TEMP_ROOT/state"
readonly CURL_MAX_TIME_LOG="$TEMP_ROOT/curl-max-time"
readonly CURL_CALL_LOG="$TEMP_ROOT/curl-calls"
readonly CURL_RESPONSE_QUEUE="$TEMP_ROOT/curl-responses"
readonly TRANSIENT_SAML_STS_TIMEOUT='failed to refresh cached credentials, operation error STS: AssumeRoleWithSAML, https response error StatusCode: 408, RequestID: , api error UnknownError: UnknownError'
readonly SERVICE_MOCKS="$TEMP_ROOT/service-mocks"
readonly SERVICE_CALL_LOG="$TEMP_ROOT/service-calls"

mkdir -p "$SERVICE_MOCKS"
cat >"$SERVICE_MOCKS/uname" <<'EOF'
#!/usr/bin/env bash
set -eu
[[ ${1:-} == -s ]]
printf '%s\n' "${MOCK_UNAME_S:?}"
EOF
cat >"$SERVICE_MOCKS/launchctl" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'launchctl %s\n' "$*" >>"${MOCK_SERVICE_CALL_LOG:?}"
exit "${MOCK_SERVICE_EXIT:-0}"
EOF
cat >"$SERVICE_MOCKS/systemctl" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'systemctl %s\n' "$*" >>"${MOCK_SERVICE_CALL_LOG:?}"
if [[ -n ${MOCK_SERVICE_BLOCK_SECONDS:-} ]]; then
  exec /bin/sleep "$MOCK_SERVICE_BLOCK_SECONDS"
fi
exit "${MOCK_SERVICE_EXIT:-0}"
EOF
chmod +x "$SERVICE_MOCKS/uname" "$SERVICE_MOCKS/launchctl" \
  "$SERVICE_MOCKS/systemctl"

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
  actual=$(head -n 1 "$CURL_MAX_TIME_LOG")
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

assert_service_call() {
  local expected=$1
  local actual

  actual=$(<"$SERVICE_CALL_LOG")
  if [[ $actual != "$expected" ]]; then
    printf 'Expected service call %s, received %s.\n' \
      "$expected" "$actual" >&2
    exit 1
  fi
}

MOCK_CURL_STATUS=200 MOCK_CURL_BODY='{"role_arn":"example-role"}' \
  assert_exit 0 "$CLI" profile test-profile --no-open
if grep -Fq 'example-role' "$AWS_METADATA_STATE_DIR/active-profile"; then
  printf '%s\n' 'Cached profile state contains live profile details.' >&2
  exit 1
fi

status_output=$(MOCK_CURL_STATUS=200 \
  MOCK_CURL_BODY='{"role_arn":"example-role"}' "$CLI" status)
if [[ $status_output != *'Active profile: test-profile'* ]] ||
   [[ $status_output != *'Profile details: {"role_arn":"example-role"}'* ]]; then
  printf 'Unexpected named-profile status output: %s\n' "$status_output" >&2
  exit 1
fi

status_output=$(MOCK_CURL_STATUS=200 \
  MOCK_CURL_BODY='{"role_arn":"different-role"}' "$CLI" status --json)
if [[ $status_output != \
  '{"state":"running","endpoint":"http://127.0.0.1:9876","profile_name":null,"profile":{"role_arn":"different-role"}}' ]]; then
  printf 'Unexpected mismatched-profile status output: %s\n' "$status_output" >&2
  exit 1
fi

MOCK_CURL_STATUS=200 assert_exit 0 "$CLI" use test-profile
MOCK_CURL_STATUS=401 assert_exit 4 "$CLI" use test-profile --no-open
MOCK_CURL_STATUS=401 assert_exit 4 "$CLI" profile test-profile --no-open
MOCK_CURL_STATUS=500 assert_exit 6 "$CLI" profile test-profile --no-open
MOCK_CURL_STATUS=000 assert_exit 3 "$CLI" profile test-profile --no-open
status_output=$(MOCK_CURL_STATUS=200 "$CLI" status --json)
if [[ $status_output != \
  '{"state":"running","endpoint":"http://127.0.0.1:9876","profile_name":"test-profile","profile":{"name":"test-profile"}}' ]]; then
  printf 'Unexpected active-profile JSON status: %s\n' "$status_output" >&2
  exit 1
fi
MOCK_CURL_STATUS=500 MOCK_CURL_BODY='profile not set' \
  assert_exit 0 "$CLI" status --json
if [[ -e $AWS_METADATA_STATE_DIR/active-profile ]]; then
  printf '%s\n' 'No-profile status did not remove cached profile state.' >&2
  exit 1
fi
MOCK_CURL_STATUS=500 MOCK_CURL_BODY='unexpected failure' \
  assert_exit 6 "$CLI" status --json

# Clearing an already-empty broker is idempotent and does not restart it.
: >"$SERVICE_CALL_LOG"
clear_output=$(MOCK_CURL_STATUS=500 MOCK_CURL_BODY='profile not set' \
  PATH="$SERVICE_MOCKS:$PATH" MOCK_UNAME_S=Darwin \
  MOCK_SERVICE_CALL_LOG="$SERVICE_CALL_LOG" "$CLI" clear --json)
if [[ $clear_output != \
  '{"state":"clear","message":"No AWS metadata profile is selected."}' ]] ||
   [[ -s $SERVICE_CALL_LOG ]]; then
  printf 'Unexpected idempotent clear result: %s\n' "$clear_output" >&2
  exit 1
fi

# macOS restarts only the user broker and tolerates its transient outage.
: >"$SERVICE_CALL_LOG"
printf '200|{"name":"sensitive-profile"}\n000|\n500|profile not set\n' \
  >"$CURL_RESPONSE_QUEUE"
clear_output=$(PATH="$SERVICE_MOCKS:$PATH" MOCK_UNAME_S=Darwin \
  MOCK_SERVICE_CALL_LOG="$SERVICE_CALL_LOG" \
  MOCK_CURL_RESPONSE_QUEUE="$CURL_RESPONSE_QUEUE" \
  "$CLI" clear --wait 2 --json)
if [[ $clear_output != \
  '{"state":"clear","message":"AWS metadata profile cleared."}' ]] ||
   [[ $clear_output == *'sensitive-profile'* ]]; then
  printf 'Unexpected macOS clear result: %s\n' "$clear_output" >&2
  exit 1
fi
assert_service_call \
  "launchctl kickstart -k gui/$(id -u)/com.github.so1omon563.aws-metadata-agent.broker"

# Linux uses only the systemd user broker and confirms healthy no-profile state.
: >"$SERVICE_CALL_LOG"
printf '200|{"name":"sensitive-profile"}\n000|\n500|profile not set\n' \
  >"$CURL_RESPONSE_QUEUE"
clear_output=$(PATH="$SERVICE_MOCKS:$PATH" MOCK_UNAME_S=Linux \
  MOCK_SERVICE_CALL_LOG="$SERVICE_CALL_LOG" \
  MOCK_CURL_RESPONSE_QUEUE="$CURL_RESPONSE_QUEUE" \
  "$CLI" clear --wait 2 --json)
if [[ $clear_output != \
  '{"state":"clear","message":"AWS metadata profile cleared."}' ]] ||
   [[ $clear_output == *'sensitive-profile'* ]]; then
  printf 'Unexpected Linux clear result: %s\n' "$clear_output" >&2
  exit 1
fi
assert_service_call 'systemctl --user restart aws-metadata-agent.service'

# Clear reports deterministic failures without exposing the active profile.
: >"$SERVICE_CALL_LOG"
MOCK_CURL_STATUS=000 PATH="$SERVICE_MOCKS:$PATH" MOCK_UNAME_S=Darwin \
  MOCK_SERVICE_CALL_LOG="$SERVICE_CALL_LOG" assert_exit 3 "$CLI" clear
[[ ! -s $SERVICE_CALL_LOG ]]

: >"$SERVICE_CALL_LOG"
MOCK_CURL_STATUS=200 PATH="$SERVICE_MOCKS:$PATH" MOCK_UNAME_S=Darwin \
  MOCK_SERVICE_EXIT=2 MOCK_SERVICE_CALL_LOG="$SERVICE_CALL_LOG" \
  assert_exit 6 "$CLI" clear --json

: >"$SERVICE_CALL_LOG"
printf '200|{"name":"sensitive-profile"}\n200|{"name":"other-sensitive-profile"}\n' \
  >"$CURL_RESPONSE_QUEUE"
clear_error_exit=0
clear_error=$(PATH="$SERVICE_MOCKS:$PATH" MOCK_UNAME_S=Linux \
  MOCK_SERVICE_CALL_LOG="$SERVICE_CALL_LOG" \
  MOCK_CURL_RESPONSE_QUEUE="$CURL_RESPONSE_QUEUE" \
  "$CLI" clear --wait 0 --json 2>&1) || clear_error_exit=$?
if [[ $clear_error_exit -ne 6 ]] ||
   [[ $clear_error != *'"state":"error"'* ]] ||
   [[ $clear_error == *'sensitive-profile'* ]]; then
  printf 'Unexpected concurrent clear result: %s\n' "$clear_error" >&2
  exit 1
fi

: >"$SERVICE_CALL_LOG"
printf '200|{"name":"sensitive-profile"}\n000|\n' >"$CURL_RESPONSE_QUEUE"
PATH="$SERVICE_MOCKS:$PATH" MOCK_UNAME_S=Linux \
  MOCK_SERVICE_CALL_LOG="$SERVICE_CALL_LOG" \
  MOCK_CURL_RESPONSE_QUEUE="$CURL_RESPONSE_QUEUE" \
  assert_exit 5 "$CLI" clear --wait 0 --json

MOCK_CURL_STATUS=200 PATH="$SERVICE_MOCKS:$PATH" MOCK_UNAME_S=Other \
  MOCK_SERVICE_CALL_LOG="$SERVICE_CALL_LOG" assert_exit 2 "$CLI" clear
assert_exit 2 "$CLI" clear unexpected
assert_exit 2 "$CLI" clear --wait invalid
AWS_METADATA_CLEAR_WAIT_SECONDS=invalid assert_exit 2 "$CLI" clear

: >"$SERVICE_CALL_LOG"
printf '200|{"name":"sensitive-profile"}\n000|\n' >"$CURL_RESPONSE_QUEUE"
PATH="$SERVICE_MOCKS:$PATH" MOCK_UNAME_S=Linux \
  MOCK_SERVICE_CALL_LOG="$SERVICE_CALL_LOG" \
  MOCK_CURL_RESPONSE_QUEUE="$CURL_RESPONSE_QUEUE" \
  assert_exit 5 "$CLI" clear --wait 00 --json

# A blocked service-manager client remains inside the same clear deadline.
: >"$SERVICE_CALL_LOG"
printf '200|{"name":"sensitive-profile"}\n000|\n' >"$CURL_RESPONSE_QUEUE"
PATH="$SERVICE_MOCKS:$PATH" MOCK_UNAME_S=Linux \
  MOCK_SERVICE_BLOCK_SECONDS=30 MOCK_SERVICE_CALL_LOG="$SERVICE_CALL_LOG" \
  MOCK_CURL_RESPONSE_QUEUE="$CURL_RESPONSE_QUEUE" \
  assert_exit 5 "$CLI" clear --wait 0 --json

profile_error_exit=0
profile_error_output=$(MOCK_CURL_STATUS=500 \
  MOCK_CURL_BODY='failed to refresh cached credentials: sensitive-detail-marker' \
  "$CLI" profile test-profile --no-open 2>&1) || profile_error_exit=$?
if [[ $profile_error_exit -ne 6 ]] ||
   [[ $profile_error_output != *'metadata endpoint at http://127.0.0.1:9876 is reachable'* ]] ||
   [[ $profile_error_output != *'Broker error: Credential refresh failed.'* ]] ||
   [[ $profile_error_output != *'Recent broker errors: aws-metadata errors'* ]] ||
   [[ $profile_error_output != *'Broker log:'* ]] ||
   [[ $profile_error_output == *'sensitive-detail-marker'* ]]; then
  printf 'Unexpected profile diagnostic output: %s\n' "$profile_error_output" >&2
  exit 1
fi

profile_error_exit=0
profile_error_json=$(MOCK_CURL_STATUS=500 \
  MOCK_CURL_BODY="$TRANSIENT_SAML_STS_TIMEOUT" \
  "$CLI" profile test-profile --no-open --json) || profile_error_exit=$?
if [[ $profile_error_exit -ne 6 ]] ||
   [[ $profile_error_json != *'"state":"error"'* ]] ||
   [[ $profile_error_json != *'"broker_error":"STS AssumeRoleWithSAML returned HTTP 408."'* ]] ||
   [[ $profile_error_json != *'"diagnostic_command":"aws-metadata errors"'* ]] ||
   [[ $profile_error_json == *'RequestID'* ]]; then
  printf 'Unexpected JSON profile diagnostic: %s\n' "$profile_error_json" >&2
  exit 1
fi

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
assert_curl_calls 3

# The same one-retry recovery applies when the first request asks the CLI to
# open the browser and a later polling request receives the transient STS 408.
: >"$CURL_CALL_LOG"
printf '401|\n500|%s\n200|\n' \
  "$TRANSIENT_SAML_STS_TIMEOUT" >"$CURL_RESPONSE_QUEUE"
MOCK_CURL_CALL_LOG="$CURL_CALL_LOG" \
  MOCK_CURL_RESPONSE_QUEUE="$CURL_RESPONSE_QUEUE" \
  assert_exit 0 "$CLI" use test-profile
assert_curl_calls 4

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

BROKER_ERROR_FIXTURE="$TEMP_ROOT/broker-errors"
readonly BROKER_ERROR_FIXTURE
printf '%s\n%s\n%s\n' \
  "2026/07/17 ERROR handleAuthError: $TRANSIENT_SAML_STS_TIMEOUT" \
  '2026/07/17 ERROR handleAuthError: browser closed before authentication completed' \
  '2026/07/17 ERROR handleAuthError: sensitive-detail-marker' \
  >"$BROKER_ERROR_FIXTURE"

case $(uname -s) in
  Darwin)
    ERROR_HOME="$TEMP_ROOT/error-home"
    mkdir -p "$ERROR_HOME/Library/Logs"
    cp "$BROKER_ERROR_FIXTURE" \
      "$ERROR_HOME/Library/Logs/aws-metadata-agent.log"
    errors_output=$(HOME="$ERROR_HOME" "$CLI" errors)
    ;;
  Linux)
    errors_output=$(MOCK_JOURNAL_OUTPUT="$BROKER_ERROR_FIXTURE" "$CLI" errors)
    journal_error_exit=0
    journal_error_output=$(MOCK_JOURNAL_EXIT=1 "$CLI" errors 2>&1) || \
      journal_error_exit=$?
    if [[ $journal_error_exit -ne 1 ]] ||
       [[ $journal_error_output != *'Unable to read the broker log'* ]] ||
       [[ $journal_error_output == *'No broker authentication errors'* ]]; then
      printf 'Unexpected journal read failure: %s\n' "$journal_error_output" >&2
      exit 1
    fi
    ;;
  *)
    printf '%s\n' 'Unsupported test platform.' >&2
    exit 1
    ;;
esac
if [[ $errors_output != *'STS AssumeRoleWithSAML returned HTTP 408.'* ]] ||
   [[ $errors_output != *'Browser authentication closed before completion.'* ]] ||
   [[ $errors_output != *'details are redacted.'* ]] ||
   [[ $errors_output == *'sensitive-detail-marker'* ]]; then
  printf 'Unexpected bounded broker error output: %s\n' "$errors_output" >&2
  exit 1
fi
assert_exit 2 "$CLI" errors unexpected

: >"$CURL_CALL_LOG"
printf '500|%s\n200|\n' "$TRANSIENT_SAML_STS_TIMEOUT" >"$CURL_RESPONSE_QUEUE"
MOCK_CURL_CALL_LOG="$CURL_CALL_LOG" \
  MOCK_CURL_RESPONSE_QUEUE="$CURL_RESPONSE_QUEUE" \
  assert_exit 6 "$CLI" profile test-profile --no-open
assert_curl_calls 1

status_output=$(MOCK_CURL_STATUS=500 MOCK_CURL_BODY='profile not set' \
  "$CLI" status --json)
if [[ $status_output != \
  '{"state":"running","endpoint":"http://127.0.0.1:9876","profile_name":null,"profile":null}' ]]; then
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

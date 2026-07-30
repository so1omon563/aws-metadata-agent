#!/usr/bin/env bash

set -eu

TEST_PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly TEST_PROJECT_DIR
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/aws-metadata-uninstall.XXXXXX")
readonly TEMP_ROOT
MOCK_BIN=$TEMP_ROOT/bin
readonly MOCK_BIN

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'uninstall test: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$MOCK_BIN"
cat >"$MOCK_BIN/launchctl" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"${MOCK_SERVICE_LOG:?}"
case $1 in
  print)
    case ${MOCK_LAUNCH_STATE:?} in
      absent) exit 113 ;;
      error) exit 42 ;;
      active) exit 0 ;;
    esac
    ;;
  bootout)
    [[ ${MOCK_STOP_FAIL:-no} != yes ]] || exit 42
    exit 0
    ;;
esac
exit 2
EOF
cat >"$MOCK_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s|%s\n' "${MOCK_SCOPE:-system}" "$*" >>"${MOCK_SERVICE_LOG:?}"
while [[ ${1:-} == --* ]]; do
  shift
done
case ${1:-} in
  is-active)
    case $(<"${MOCK_SYSTEMD_STATE:?}") in
      active) exit 0 ;;
      inactive) exit 3 ;;
      absent) exit 4 ;;
      error) exit 42 ;;
    esac
    ;;
  disable)
    [[ ${MOCK_STOP_FAIL:-no} != yes ]] || exit 42
    printf '%s\n' inactive >"${MOCK_SYSTEMD_STATE:?}"
    ;;
  *) exit 2 ;;
esac
EOF
cat >"$MOCK_BIN/uname" <<'EOF'
#!/bin/sh
printf '%s\n' Darwin
EOF
cat >"$MOCK_BIN/id" <<'EOF'
#!/bin/sh
[[ ${1:-} == -u ]] || exit 2
printf '%s\n' 501
EOF
chmod +x "$MOCK_BIN"/*
export PATH="$MOCK_BIN:$PATH"

# shellcheck disable=SC1091
source "$TEST_PROJECT_DIR/uninstall.sh"

service_log=$TEMP_ROOT/service.log
systemd_state=$TEMP_ROOT/systemd-state
: >"$service_log"

MOCK_SERVICE_LOG=$service_log MOCK_LAUNCH_STATE=absent \
  stop_launchd_job gui/501/com.github.so1omon563.aws-metadata-agent.broker
if MOCK_SERVICE_LOG=$service_log MOCK_LAUNCH_STATE=error \
  stop_launchd_job system/com.github.so1omon563.aws-metadata-agent.forwarder \
  >/dev/null 2>&1; then
  fail 'launchd inspection failure was accepted as an absent job'
fi
if MOCK_SERVICE_LOG=$service_log MOCK_LAUNCH_STATE=active MOCK_STOP_FAIL=yes \
  stop_launchd_job system/com.github.so1omon563.aws-metadata-agent.proxy \
  >/dev/null 2>&1; then
  fail 'launchd bootout failure was ignored'
fi

printf '%s\n' absent >"$systemd_state"
for unit in \
  aws-metadata-agent.service \
  aws-metadata-agent.socket \
  aws-metadata-agent-address.service; do
  MOCK_SERVICE_LOG=$service_log MOCK_SYSTEMD_STATE=$systemd_state \
    stop_systemd_unit "$unit" systemctl
done

printf '%s\n' active >"$systemd_state"
if stop_systemd_unit aws-metadata-agent.service \
  env MOCK_SCOPE=user MOCK_SERVICE_LOG="$service_log" \
    MOCK_SYSTEMD_STATE="$systemd_state" MOCK_STOP_FAIL=yes systemctl --user \
  >/dev/null 2>&1; then
  fail 'systemd user-manager stop failure was ignored'
fi
for unit in \
  aws-metadata-agent.service \
  aws-metadata-agent.socket \
  aws-metadata-agent-address.service; do
  printf '%s\n' active >"$systemd_state"
  if MOCK_SERVICE_LOG=$service_log MOCK_SYSTEMD_STATE=$systemd_state \
    MOCK_STOP_FAIL=yes \
    stop_systemd_unit "$unit" systemctl >/dev/null 2>&1; then
    fail "systemd stop failure was ignored for $unit"
  fi
done

printf '%s\n' active >"$systemd_state"
MOCK_SERVICE_LOG=$service_log MOCK_SYSTEMD_STATE=$systemd_state \
  stop_systemd_unit aws-metadata-agent.socket systemctl
[[ $(<"$systemd_state") == inactive ]] ||
  fail 'successful systemd stop did not reach inactive state'

user_home=$TEMP_ROOT/home
state_dir="$user_home/Library/Application Support/aws-metadata-agent"
agent_file=$user_home/Library/LaunchAgents/com.github.so1omon563.aws-metadata-agent.broker.plist
mkdir -p "$state_dir" "$(dirname "$agent_file")" "$user_home/.aws"
printf '%s\n' user >"$state_dir/user-mode"
printf '%s\n' plist >"$agent_file"
printf '%s\n' '# keep' >"$user_home/.aws/config"

failure_output=$TEMP_ROOT/user-failure
if env PATH="$MOCK_BIN:$PATH" HOME="$user_home" \
  MOCK_SERVICE_LOG="$service_log" MOCK_LAUNCH_STATE=error \
  "$PROJECT_DIR/uninstall.sh" --mode user >"$failure_output" 2>&1; then
  fail 'user uninstall accepted a launchd manager failure'
fi
[[ -e $state_dir/user-mode ]] ||
  fail 'failed user uninstall removed retry-critical state'
[[ -e $agent_file ]] ||
  fail 'failed user uninstall removed the LaunchAgent definition'
if grep -Fq 'user mode uninstalled' "$failure_output"; then
  fail 'failed user uninstall printed success'
fi

env PATH="$MOCK_BIN:$PATH" HOME="$user_home" \
  MOCK_SERVICE_LOG="$service_log" MOCK_LAUNCH_STATE=absent \
  "$PROJECT_DIR/uninstall.sh" --mode user >/dev/null
[[ ! -e $state_dir ]] || fail 'absent user job prevented idempotent cleanup'
[[ ! -e $agent_file ]] ||
  fail 'absent user job left the LaunchAgent definition'

printf '%s\n' 'Uninstall service-stop checks passed.'

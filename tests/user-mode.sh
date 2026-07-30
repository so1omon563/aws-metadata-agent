#!/usr/bin/env bash

set -eu

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_DIR
readonly CONFIG_HELPER=$PROJECT_DIR/libexec/aws-metadata-config
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/aws-metadata-user-mode.XXXXXX")
readonly TEMP_ROOT

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'user-mode test: %s\n' "$1" >&2
  exit 1
}

mode_of() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

mkdir -p "$TEMP_ROOT/aws"
config_target=$TEMP_ROOT/aws/config-target
config_link=$TEMP_ROOT/aws/config
command_path=$TEMP_ROOT/aws-metadata

printf '%s\n' \
  '# existing comment' \
  '[default]' \
  'region = us-west-2' \
  '[profile keep-me]' \
  'region = us-east-1' >"$config_target"
chmod 0640 "$config_target"
ln -s config-target "$config_link"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$command_path"
chmod +x "$command_path"

before_mode=$(mode_of "$config_target")
"$CONFIG_HELPER" add "$config_link" "$command_path"

[[ -L $config_link ]] || fail 'AWS config symlink was replaced'
[[ $(mode_of "$config_target") == "$before_mode" ]] ||
  fail 'AWS config permissions changed'
grep -Fqx '# existing comment' "$config_target" ||
  fail 'existing AWS config content was removed'
[[ $(grep -Fxc '[default]' "$config_target") -eq 1 ]] ||
  fail 'default AWS profile was duplicated'
grep -Fqx "credential_process = \"$command_path\" _credential-process" \
  "$config_target" || fail 'credential_process command is incorrect'

checksum_before=$(shasum -a 256 "$config_target")
"$CONFIG_HELPER" add "$config_link" "$command_path"
checksum_after=$(shasum -a 256 "$config_target")
[[ $checksum_after == "$checksum_before" ]] ||
  fail 'repeated setup changed the AWS config'

awk '{ printf "%s\r\n", $0 }' "$config_target" >"$TEMP_ROOT/crlf-config"
dd if="$TEMP_ROOT/crlf-config" of="$config_target" 2>/dev/null
checksum_before=$(shasum -a 256 "$config_target")
"$CONFIG_HELPER" add "$config_link" "$command_path"
checksum_after=$(shasum -a 256 "$config_target")
[[ $checksum_after == "$checksum_before" ]] ||
  fail 'repeated setup changed a CRLF AWS config'

"$CONFIG_HELPER" remove "$config_link"
[[ -L $config_link ]] || fail 'AWS config symlink was replaced during cleanup'
[[ $(mode_of "$config_target") == "$before_mode" ]] ||
  fail 'AWS config permissions changed during cleanup'
grep -Fqx $'# existing comment\r' "$config_target" ||
  fail 'existing AWS config content was removed during cleanup'
grep -Fqx $'[profile keep-me]\r' "$config_target" ||
  fail 'named AWS profile was removed during cleanup'
if grep -Fq 'aws-metadata-agent user mode' "$config_target"; then
  fail 'owned AWS config block remained after cleanup'
fi
awk '{ if (sub(/\r$/, "") != 1) exit 1 }' "$config_target" ||
  fail 'cleanup changed the CRLF line-ending style'
checksum_before=$(shasum -a 256 "$config_target")
"$CONFIG_HELPER" remove "$config_link"
checksum_after=$(shasum -a 256 "$config_target")
[[ $checksum_after == "$checksum_before" ]] ||
  fail 'repeated cleanup changed a CRLF AWS config'

malformed=$TEMP_ROOT/aws/malformed-crlf
printf '%s\r\n' \
  '# aws-metadata-agent user mode: begin' \
  'credential_process = user-owned' >"$malformed"
checksum_before=$(shasum -a 256 "$malformed")
if "$CONFIG_HELPER" remove "$malformed" >/dev/null 2>&1; then
  fail 'cleanup accepted a malformed CRLF managed block'
fi
checksum_after=$(shasum -a 256 "$malformed")
[[ $checksum_after == "$checksum_before" ]] ||
  fail 'cleanup changed a malformed CRLF managed block'

unmarked=$TEMP_ROOT/aws/unmarked-crlf
printf '%s\r\n' \
  '# aws-metadata-agent user mode: begin user-owned' \
  'credential_process = user-owned' \
  '# aws-metadata-agent user mode: end user-owned' >"$unmarked"
checksum_before=$(shasum -a 256 "$unmarked")
"$CONFIG_HELPER" remove "$unmarked"
checksum_after=$(shasum -a 256 "$unmarked")
[[ $checksum_after == "$checksum_before" ]] ||
  fail 'cleanup changed unmarked CRLF configuration'

created_default=$TEMP_ROOT/aws/created-default
printf '%s\r\n' '# existing comment' >"$created_default"
"$CONFIG_HELPER" add "$created_default" "$command_path"
awk '{ if (sub(/\r$/, "") != 1) exit 1 }' "$created_default" ||
  fail 'setup mixed line endings while adding a default CRLF profile'
printf '%s\r\n' 'region = us-west-2' >>"$created_default"
"$CONFIG_HELPER" remove "$created_default"
grep -Fqx $'[default]\r' "$created_default" ||
  fail 'cleanup removed a default profile with user settings'
grep -Fqx $'region = us-west-2\r' "$created_default" ||
  fail 'cleanup removed a user-added default setting'

conflict=$TEMP_ROOT/aws/conflict
printf '%s\n' \
  '[default]' \
  'credential_process = /usr/local/bin/other-provider' >"$conflict"
if "$CONFIG_HELPER" validate "$conflict" >/dev/null 2>&1; then
  fail 'validation accepted an existing default credential provider'
fi
if "$CONFIG_HELPER" add "$conflict" "$command_path" >/dev/null 2>&1; then
  fail 'setup replaced an existing default credential provider'
fi

credentials_conflict=$TEMP_ROOT/aws/credentials-conflict
printf '%s\n' \
  '[default]' \
  'aws_access_key_id = ASIASYNTHETICONLY' >"$credentials_conflict"
if "$CONFIG_HELPER" validate "$config_link" "$credentials_conflict" \
  >/dev/null 2>&1; then
  fail 'validation accepted default shared credentials'
fi

migration=$TEMP_ROOT/aws/migration
printf '%s\n' \
  '# aws-metadata-agent user mode: begin' \
  '[profile local-metadata]' \
  "credential_process = \"$command_path\" _credential-process" \
  '# aws-metadata-agent user mode: end' >"$migration"
"$CONFIG_HELPER" add "$migration" "$command_path"
grep -Fqx '[default]' "$migration" ||
  fail 'legacy compatibility profile did not migrate to default'
if grep -Fq '[profile local-metadata]' "$migration"; then
  fail 'legacy compatibility profile remained after migration'
fi

server_runas=$TEMP_ROOT/server-aws-runas
server_log=$TEMP_ROOT/server-arguments
server_config=$TEMP_ROOT/server-config
cat >"$server_runas" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"${SERVER_LOG:?}"
EOF
chmod +x "$server_runas"
{
  printf 'AWS_METADATA_MODE=%q\n' user
  printf 'AWS_METADATA_USER=%q\n' "${USER:-test-user}"
  printf 'AWS_METADATA_UID=%q\n' "$(id -u)"
  printf 'AWS_METADATA_HOME=%q\n' "$TEMP_ROOT"
  printf 'AWS_RUNAS=%q\n' "$server_runas"
  printf 'AWS_METADATA_PORT=%q\n' 18080
} >"$server_config"
SERVER_LOG="$server_log" AWS_METADATA_CONFIG="$server_config" \
  "$PROJECT_DIR/libexec/aws-metadata-server"
[[ $(<"$server_log") == '-r serve ecs --port 18080' ]] ||
  fail 'user mode did not start the ECS listener'
sed 's/AWS_METADATA_MODE=user/AWS_METADATA_MODE=system/' \
  "$server_config" >"$TEMP_ROOT/system-server-config"
SERVER_LOG="$server_log" AWS_METADATA_CONFIG="$TEMP_ROOT/system-server-config" \
  "$PROJECT_DIR/libexec/aws-metadata-server"
[[ $(<"$server_log") == '-r serve ec2 --port 18080' ]] ||
  fail 'system mode did not retain the EC2 listener'

if [[ $(uname -s) == Darwin && ! -e /etc/aws-metadata-agent/config ]]; then
  MOCK_BIN=$TEMP_ROOT/mock-bin
  MOCK_HOME=$TEMP_ROOT/managed-home
  MOCK_USER=managed-user
  MOCK_RUNAS=$TEMP_ROOT/aws-runas
  MOCK_CLI=$TEMP_ROOT/aws-metadata
  MOCK_SERVICE_LOG=$TEMP_ROOT/service-log
  mkdir -p "$MOCK_BIN" "$MOCK_HOME/.aws"
  printf '%s\n' '# keep this line' >"$MOCK_HOME/.aws/config"
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$MOCK_RUNAS"
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$MOCK_CLI"
  chmod +x "$MOCK_RUNAS" "$MOCK_CLI"

  cat >"$MOCK_BIN/uname" <<'EOF'
#!/bin/sh
test "${1:-}" = -s
printf '%s\n' Darwin
EOF
  cat >"$MOCK_BIN/dscl" <<'EOF'
#!/bin/sh
printf 'NFSHomeDirectory: %s\n' "${MOCK_HOME:?}"
EOF
  cat >"$MOCK_BIN/id" <<'EOF'
#!/bin/sh
case ${1:-} in
  -u) printf '%s\n' 501 ;;
  -gn) printf '%s\n' staff ;;
  *) exit 2 ;;
esac
EOF
  cat >"$MOCK_BIN/launchctl" <<'EOF'
#!/bin/sh
printf 'launchctl %s\n' "$*" >>"${MOCK_SERVICE_LOG:?}"
state_file=${MOCK_SERVICE_LOG}.launch-state
case $1 in
  bootstrap) : >"$state_file" ;;
  bootout) rm -f "$state_file" ;;
  print) [ -e "$state_file" ] || exit 113 ;;
esac
EOF
  cat >"$MOCK_BIN/curl" <<'EOF'
#!/bin/sh
output_file=''
while [ "$#" -gt 0 ]; do
  case $1 in
    --output)
      shift
      output_file=$1
      ;;
  esac
  shift
done
printf '%s' "${MOCK_CURL_BODY:-{\"role_arn\":\"\"}}" >"$output_file"
printf '%s' "${MOCK_CURL_STATUS:-200}"
EOF
  cat >"$MOCK_BIN/sleep" <<'EOF'
#!/bin/sh
:
EOF
  cat >"$MOCK_BIN/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' 'sudo must not run in user mode' >&2
exit 99
EOF
  chmod +x "$MOCK_BIN"/*

  env \
    PATH="$MOCK_BIN:$PATH" \
    HOME="$MOCK_HOME" \
    USER="$MOCK_USER" \
    MOCK_HOME="$MOCK_HOME" \
    MOCK_SERVICE_LOG="$MOCK_SERVICE_LOG" \
    "$PROJECT_DIR/install.sh" \
      --mode user \
      --package-cli "$MOCK_CLI" \
      --aws-runas "$MOCK_RUNAS" >/dev/null

  state_dir="$MOCK_HOME/Library/Application Support/aws-metadata-agent"
  agent_file="$MOCK_HOME/Library/LaunchAgents/com.github.so1omon563.aws-metadata-agent.broker.plist"
  [[ -f $state_dir/config ]] || fail 'user-mode state was not installed'
  grep -Fqx 'AWS_METADATA_MODE=user' "$state_dir/config" ||
    fail 'user-mode state did not record its mode'
  grep -Fq "$PROJECT_DIR/libexec/aws-metadata-server" "$agent_file" ||
    fail 'LaunchAgent did not use the package-managed server'
  grep -Fqx '[default]' "$MOCK_HOME/.aws/config" ||
    fail 'user-mode setup did not add the default profile'
  grep -Fqx \
    "credential_process = \"$MOCK_CLI\" _credential-process" \
    "$MOCK_HOME/.aws/config" ||
    fail 'user-mode setup did not add the default credential provider'
  if grep -Fq 'sudo ' "$MOCK_SERVICE_LOG"; then
    fail 'user-mode setup invoked sudo'
  fi

  awk '{ printf "%s\r\n", $0 }' \
    "$MOCK_HOME/.aws/config" >"$TEMP_ROOT/managed-crlf-config"
  dd if="$TEMP_ROOT/managed-crlf-config" \
    of="$MOCK_HOME/.aws/config" 2>/dev/null

  env \
    PATH="$MOCK_BIN:$PATH" \
    HOME="$MOCK_HOME" \
    USER="$MOCK_USER" \
    MOCK_SERVICE_LOG="$MOCK_SERVICE_LOG" \
    "$PROJECT_DIR/uninstall.sh" \
      --mode user \
      --package-cli "$MOCK_CLI" >/dev/null

  [[ ! -e $state_dir ]] || fail 'user-mode state remained after uninstall'
  [[ ! -e $agent_file ]] || fail 'user-mode LaunchAgent remained after uninstall'
  grep -Fqx $'# keep this line\r' "$MOCK_HOME/.aws/config" ||
    fail 'uninstall removed unrelated AWS config'
  grep -Fqx $'[default]\r' "$MOCK_HOME/.aws/config" ||
    fail 'uninstall removed the default profile header'
  if grep -Fq 'aws-metadata-agent user mode' "$MOCK_HOME/.aws/config"; then
    fail 'uninstall left the owned AWS config block'
  fi
  awk '{ if (sub(/\r$/, "") != 1) exit 1 }' "$MOCK_HOME/.aws/config" ||
    fail 'uninstall changed the CRLF line-ending style'

  failed_output=$TEMP_ROOT/readiness-failure-output
  if env \
    PATH="$MOCK_BIN:$PATH" \
    HOME="$MOCK_HOME" \
    USER="$MOCK_USER" \
    MOCK_HOME="$MOCK_HOME" \
    MOCK_SERVICE_LOG="$MOCK_SERVICE_LOG" \
    MOCK_CURL_STATUS=503 \
    MOCK_CURL_BODY='wrong listener' \
    "$PROJECT_DIR/install.sh" \
      --mode user \
      --package-cli "$MOCK_CLI" \
      --aws-runas "$MOCK_RUNAS" >"$failed_output" 2>&1; then
    fail 'user-mode setup accepted a non-metadata response'
  fi
  if grep -Fq 'user mode installed' "$failed_output"; then
    fail 'failed readiness printed installation success'
  fi
  if grep -Fq 'credential_process' "$MOCK_HOME/.aws/config"; then
    fail 'failed readiness added the default credential provider'
  fi
  env \
    PATH="$MOCK_BIN:$PATH" \
    HOME="$MOCK_HOME" \
    USER="$MOCK_USER" \
    MOCK_SERVICE_LOG="$MOCK_SERVICE_LOG" \
    "$PROJECT_DIR/uninstall.sh" \
      --mode user \
      --package-cli "$MOCK_CLI" >/dev/null

  printf '%s\n' '# keep this line' >"$MOCK_HOME/.aws/config"
  printf '%s\n' \
    '[default]' \
    'aws_access_key_id = ASIASYNTHETICONLY' >"$MOCK_HOME/.aws/credentials"
  : >"$MOCK_SERVICE_LOG"
  if env \
    PATH="$MOCK_BIN:$PATH" \
    HOME="$MOCK_HOME" \
    USER="$MOCK_USER" \
    MOCK_HOME="$MOCK_HOME" \
    MOCK_SERVICE_LOG="$MOCK_SERVICE_LOG" \
    "$PROJECT_DIR/install.sh" \
      --mode user \
      --package-cli "$MOCK_CLI" \
      --aws-runas "$MOCK_RUNAS" >/dev/null 2>&1; then
    fail 'user-mode setup accepted default shared credentials'
  fi
  [[ ! -e $state_dir ]] ||
    fail 'conflicting setup left user-mode state'
  [[ ! -e $agent_file ]] ||
    fail 'conflicting setup left a user-mode LaunchAgent'
  [[ ! -s $MOCK_SERVICE_LOG ]] ||
    fail 'conflicting setup activated the user-mode broker'
fi

printf '%s\n' 'User-mode config checks passed.'

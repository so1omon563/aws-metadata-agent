#!/usr/bin/env bash

set -eu

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_DIR
readonly SERVICE_DIR=/usr/local/libexec/aws-metadata-agent

assert_contains() {
  local file=$1
  local expected=$2

  if ! grep -Fq -- "$expected" "$file"; then
    printf 'Expected %s to contain: %s\n' "$file" "$expected" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file=$1
  local unexpected=$2

  if grep -Fq -- "$unexpected" "$file"; then
    printf 'Expected %s not to contain: %s\n' "$file" "$unexpected" >&2
    exit 1
  fi
}

assert_contains \
  "$PROJECT_DIR/launchd/com.github.so1omon563.aws-metadata-agent.broker.plist" \
  "$SERVICE_DIR/aws-metadata-server"
assert_contains \
  "$PROJECT_DIR/launchd/com.github.so1omon563.aws-metadata-agent.forwarder.plist" \
  "$SERVICE_DIR/aws-metadata-forwarder"
assert_contains \
  "$PROJECT_DIR/launchd/com.github.so1omon563.aws-metadata-agent.proxy.plist" \
  '<string>169.254.169.254</string>'
assert_contains \
  "$PROJECT_DIR/launchd/com.github.so1omon563.aws-metadata-agent.proxy.plist" \
  '<string>127.0.0.1</string>'
assert_contains \
  "$PROJECT_DIR/launchd/com.github.so1omon563.aws-metadata-agent.proxy.plist" \
  '<string>nobody</string>'
assert_not_contains \
  "$PROJECT_DIR/launchd/com.github.so1omon563.aws-metadata-agent.proxy.plist" \
  'StandardErrorPath'
assert_contains \
  "$PROJECT_DIR/install.sh" \
  'com.github.so1omon563.aws-metadata-agent.broker'
assert_contains \
  "$PROJECT_DIR/install.sh" \
  'com.github.aws-metadata-agent.broker'
assert_contains \
  "$PROJECT_DIR/uninstall.sh" \
  'com.github.so1omon563.aws-metadata-agent.broker'
assert_contains \
  "$PROJECT_DIR/uninstall.sh" \
  'com.github.aws-metadata-agent.broker'
assert_contains \
  "$PROJECT_DIR/systemd/aws-metadata-agent.service" \
  "ExecStart=$SERVICE_DIR/aws-metadata-server"
assert_contains \
  "$PROJECT_DIR/systemd/aws-metadata-agent.socket" \
  'ListenStream=169.254.169.254:80'
assert_contains \
  "$PROJECT_DIR/systemd/aws-metadata-agent-proxy.service" \
  '__SYSTEMD_SOCKET_PROXYD__ 127.0.0.1:18080'
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/install.sh" \
  'proxy=$(find_systemd_socket_proxyd || true)'
assert_contains \
  "$PROJECT_DIR/install.sh" \
  '/usr/lib/systemd/systemd-socket-proxyd'
assert_contains \
  "$PROJECT_DIR/install.sh" \
  '/lib/systemd/systemd-socket-proxyd'
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/libexec/aws-metadata-server" \
  '[[ $(id -u) != "$AWS_METADATA_UID" ]]'
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/libexec/aws-metadata-server" \
  'serve ec2 --port "${AWS_METADATA_PORT:-18080}"'
assert_not_contains "$PROJECT_DIR/install.sh" '--profile'
assert_not_contains "$PROJECT_DIR/install.sh" 'AWS_METADATA_PROFILE'
# shellcheck disable=SC2016
assert_not_contains "$PROJECT_DIR/install.sh" 'install -m 0755 "$PROJECT_DIR/bin/runas.sh"'
assert_not_contains "$PROJECT_DIR/libexec/aws-metadata-server" 'AWS_METADATA_PROFILE'
assert_not_contains "$PROJECT_DIR/install.sh" 'launchctl kickstart'
assert_not_contains "$PROJECT_DIR/README.md" 'scoped PF'
assert_contains \
  "$PROJECT_DIR/install.sh" \
  'http://169.254.169.254/profile'
assert_contains \
  "$PROJECT_DIR/install.sh" \
  'launchctl_bootstrap_with_retry'
assert_contains "$PROJECT_DIR/install.sh" "--noproxy '*'"
assert_contains "$PROJECT_DIR/bin/aws-metadata" "--noproxy '*'"
# The following strings intentionally contain literal shell variables.
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/install.sh" \
  'readonly SERVICE_AWS_RUNAS=$SERVICE_DIR/aws-runas'
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/install.sh" \
  'install -m 0644 "$PROJECT_DIR/VERSION" "$SERVICE_VERSION"'
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/install.sh" \
  'printf '\''AWS_METADATA_CONFIG_VERSION=%q\n'\'' "$CONFIG_SCHEMA_VERSION"'
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/install.sh" \
  'if ((prior_config_version > CONFIG_SCHEMA_VERSION)); then'
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/bin/aws-metadata" \
  'exec "$installer" --package-cli "$PACKAGE_CLI" "$@"'
assert_contains \
  "$PROJECT_DIR/install.sh" \
  'AWS_METADATA_CLI_INSTALLED=%q'
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/install.sh" \
  'elif [[ -n $package_cli && /usr/local/bin/aws-metadata != "$package_cli" ]]; then'
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/uninstall.sh" \
  'if [[ ${AWS_METADATA_CLI_INSTALLED:-yes} == yes ]]; then'
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/bin/aws-metadata" \
  'exec "$uninstaller" --package-cli "$PACKAGE_CLI" "$@"'
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/install.sh" \
  'printf '\''AWS_METADATA_UID=%q\n'\'' "$target_uid"'
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/install.sh" \
  '$target_home/.local/bin/aws-runas'
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/bootstrap.sh" \
  'export PATH="$HOME"%q:"$PATH"'
# The following assertions intentionally contain literal shell expressions.
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/install.sh" \
  'target_home=$(macos_home_directory "$target_user")'
# shellcheck disable=SC2016
assert_contains \
  "$PROJECT_DIR/install.sh" \
  'log_path_replacement=$(sed_replacement_escape "$log_path_xml")'
# The assertion intentionally searches for a literal awk field expression.
# shellcheck disable=SC2016
assert_not_contains \
  "$PROJECT_DIR/install.sh" \
  'awk '\''{print $2}'\'''

printf '%s\n' 'Installation layout checks passed.'

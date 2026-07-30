#!/usr/bin/env bash

set -eu

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly PROJECT_DIR
readonly CONFIG_FILE=/etc/aws-metadata-agent/config
readonly USER_STATE_RELATIVE='Library/Application Support/aws-metadata-agent'
readonly BROKER_LABEL=com.github.so1omon563.aws-metadata-agent.broker
package_cli=''
uninstall_mode=system

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [--mode system|user] [--package-cli PATH]

System mode removes privileged service state. User mode removes only the
current user's LaunchAgent, user-mode state, and project-owned default
credential provider. Upstream aws-runas caches are kept.
EOF
}

stop_launchd_job() {
  local job=$1
  local status=0

  launchctl print "$job" >/dev/null 2>&1 || status=$?
  case $status in
    0) ;;
    113) return 0 ;;
    *)
      printf 'Unable to inspect launchd job %s.\n' "$job" >&2
      return 1
      ;;
  esac

  if ! launchctl bootout "$job" >/dev/null 2>&1; then
    printf 'Unable to stop launchd job %s.\n' "$job" >&2
    return 1
  fi

  status=0
  launchctl print "$job" >/dev/null 2>&1 || status=$?
  if [[ $status -ne 113 ]]; then
    printf 'Launchd job %s remains active.\n' "$job" >&2
    return 1
  fi
}

stop_systemd_unit() {
  local unit=$1
  local status=0
  shift

  "$@" is-active --quiet "$unit" >/dev/null 2>&1 || status=$?
  case $status in
    0|3) ;;
    4) return 0 ;;
    *)
      printf 'Unable to inspect systemd unit %s.\n' "$unit" >&2
      return 1
      ;;
  esac

  if ! "$@" disable --now "$unit" >/dev/null 2>&1; then
    printf 'Unable to stop systemd unit %s.\n' "$unit" >&2
    return 1
  fi

  status=0
  "$@" is-active --quiet "$unit" >/dev/null 2>&1 || status=$?
  if [[ $status -ne 3 && $status -ne 4 ]]; then
    printf 'Systemd unit %s remains active.\n' "$unit" >&2
    return 1
  fi
}

uninstall_user_mode() {
  local target_home=${HOME:-}
  local target_uid state_dir marker_file agent_file aws_config

  if [[ $(uname -s) != Darwin ]]; then
    printf '%s\n' 'User mode is currently supported only on macOS.' >&2
    return 2
  fi
  if [[ -z $target_home || $target_home != /* ]]; then
    printf '%s\n' 'Unable to determine the current user home directory.' >&2
    return 2
  fi

  target_uid=$(id -u)
  state_dir=$target_home/$USER_STATE_RELATIVE
  marker_file=$state_dir/user-mode
  agent_file=$target_home/Library/LaunchAgents/$BROKER_LABEL.plist
  aws_config=$target_home/.aws/config

  if [[ ! -e $marker_file ]]; then
    printf '%s\n' 'aws-metadata-agent user mode is not installed.'
    return 0
  fi

  stop_launchd_job "gui/$target_uid/$BROKER_LABEL"
  "$PROJECT_DIR/libexec/aws-metadata-config" remove "$aws_config"
  rm -f "$agent_file"
  rm -rf "$state_dir"
  printf '%s\n' 'aws-metadata-agent user mode uninstalled.'
}

if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
  return 0
fi

while (($#)); do
  case $1 in
    --mode)
      shift
      uninstall_mode=${1:?--mode requires a value}
      ;;
    --package-cli)
      shift
      package_cli=${1:?--package-cli requires a value}
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ $uninstall_mode != system && $uninstall_mode != user ]]; then
  printf 'Unsupported uninstall mode: %s.\n' "$uninstall_mode" >&2
  exit 2
fi

if [[ -n $package_cli && $package_cli != /* ]]; then
  printf '%s\n' '--package-cli requires an absolute path.' >&2
  exit 2
fi
if [[ -n $package_cli && ! -x $package_cli ]]; then
  printf 'The package-managed command is not executable: %s\n' \
    "$package_cli" >&2
  exit 2
fi

if [[ $uninstall_mode == user ]]; then
  uninstall_user_mode
  exit $?
fi

if ((EUID != 0)); then
  sudo_args=("$0")
  if [[ -n $package_cli ]]; then
    sudo_args+=(--package-cli "$package_cli")
  fi
  exec sudo "${sudo_args[@]}"
fi

AWS_METADATA_USER=${SUDO_USER:-}
AWS_METADATA_UID=''
AWS_METADATA_HOME=''
AWS_METADATA_LINGER_WAS_ENABLED=''
AWS_METADATA_CLI_INSTALLED=''
if [[ -r $CONFIG_FILE ]]; then
  # Root-owned installer state; contains paths and account names, not secrets.
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi
if [[ -z ${AWS_METADATA_CLI_INSTALLED:-} ]]; then
  if [[ -r $CONFIG_FILE ]]; then
    # v0.1.0 source installations predate the ownership marker.
    AWS_METADATA_CLI_INSTALLED=yes
  elif [[ -n $package_cli ]]; then
    AWS_METADATA_CLI_INSTALLED=no
  else
    AWS_METADATA_CLI_INSTALLED=yes
  fi
fi

case $(uname -s) in
  Darwin)
    if [[ -n ${AWS_METADATA_UID:-} ]]; then
      stop_launchd_job \
        "gui/$AWS_METADATA_UID/com.github.so1omon563.aws-metadata-agent.broker"
      launchctl bootout \
        "gui/$AWS_METADATA_UID/com.github.aws-metadata-agent.broker" \
        >/dev/null 2>&1 || true
    fi
    stop_launchd_job \
      system/com.github.so1omon563.aws-metadata-agent.forwarder
    stop_launchd_job system/com.github.so1omon563.aws-metadata-agent.proxy
    launchctl bootout system/com.github.aws-metadata-agent.forwarder \
      >/dev/null 2>&1 || true
    launchctl bootout system/com.github.aws-metadata-agent.proxy \
      >/dev/null 2>&1 || true
    launchctl bootout system/com.github.aws-metadata-agent >/dev/null 2>&1 || true
    rm -f \
      /Library/LaunchDaemons/com.github.so1omon563.aws-metadata-agent.forwarder.plist
    rm -f /Library/LaunchDaemons/com.github.aws-metadata-agent.forwarder.plist
    rm -f /Library/LaunchDaemons/com.github.aws-metadata-agent.plist
    rm -rf '/Library/Application Support/aws-metadata-agent'
    if [[ -n ${AWS_METADATA_HOME:-} ]]; then
      rm -f \
        "$AWS_METADATA_HOME/Library/LaunchAgents/com.github.so1omon563.aws-metadata-agent.broker.plist"
      rm -f "$AWS_METADATA_HOME/Library/LaunchAgents/com.github.aws-metadata-agent.broker.plist"
    fi
    /sbin/pfctl -a com.apple/aws-metadata-agent -F all >/dev/null 2>&1 || true
    if [[ -r /var/run/aws-metadata-agent/pf-token ]]; then
      /sbin/pfctl -X "$(</var/run/aws-metadata-agent/pf-token)" >/dev/null 2>&1 || true
    fi
    if [[ -f /var/run/aws-metadata-agent/lo0-alias-created ]]; then
      /sbin/ifconfig lo0 -alias 169.254.169.254 >/dev/null 2>&1 || true
    fi
    rm -rf /var/run/aws-metadata-agent
    ;;
  Linux)
    if [[ -n ${AWS_METADATA_UID:-} && -n ${AWS_METADATA_USER:-} ]]; then
      stop_systemd_unit aws-metadata-agent.service \
        sudo -u "$AWS_METADATA_USER" \
        env XDG_RUNTIME_DIR="/run/user/$AWS_METADATA_UID" systemctl --user
    fi
    stop_systemd_unit aws-metadata-agent.socket systemctl
    stop_systemd_unit aws-metadata-agent.service systemctl
    stop_systemd_unit aws-metadata-agent-address.service systemctl
    rm -f /etc/systemd/system/aws-metadata-agent.service
    rm -f /etc/systemd/system/aws-metadata-agent.socket
    rm -f /etc/systemd/system/aws-metadata-agent-address.service
    if [[ -n ${AWS_METADATA_HOME:-} ]]; then
      rm -f "$AWS_METADATA_HOME/.config/systemd/user/aws-metadata-agent.service"
    fi
    systemctl daemon-reload
    if [[ ${AWS_METADATA_LINGER_WAS_ENABLED:-yes} == no && \
          -n ${AWS_METADATA_USER:-} ]]; then
      loginctl disable-linger "$AWS_METADATA_USER"
    fi
    ;;
  *)
    printf '%s\n' 'Only macOS and Linux are supported.' >&2
    exit 2
    ;;
esac

if [[ ${AWS_METADATA_CLI_INSTALLED:-yes} == yes ]]; then
  rm -f /usr/local/bin/aws-metadata
fi
rm -f /usr/local/bin/runas.sh
rm -rf /usr/local/libexec/aws-metadata-agent
rm -rf /etc/aws-metadata-agent

printf '%s\n' 'aws-metadata-agent uninstalled.'

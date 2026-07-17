#!/usr/bin/env bash

set -eu

readonly CONFIG_FILE=/etc/aws-metadata-agent/config
package_cli=''

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [--package-cli PATH]

Stops and removes aws-metadata-agent services, root-owned executables, and
installer state. User-owned AWS configuration and aws-runas caches are kept.
EOF
}

while (($#)); do
  case $1 in
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

if [[ -n $package_cli && $package_cli != /* ]]; then
  printf '%s\n' '--package-cli requires an absolute path.' >&2
  exit 2
fi
if [[ -n $package_cli && ! -x $package_cli ]]; then
  printf 'The package-managed command is not executable: %s\n' \
    "$package_cli" >&2
  exit 2
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
      launchctl bootout \
        "gui/$AWS_METADATA_UID/com.github.so1omon563.aws-metadata-agent.broker" \
        >/dev/null 2>&1 || true
      launchctl bootout \
        "gui/$AWS_METADATA_UID/com.github.aws-metadata-agent.broker" \
        >/dev/null 2>&1 || true
    fi
    launchctl bootout system/com.github.so1omon563.aws-metadata-agent.forwarder \
      >/dev/null 2>&1 || true
    launchctl bootout system/com.github.so1omon563.aws-metadata-agent.proxy \
      >/dev/null 2>&1 || true
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
      sudo -u "$AWS_METADATA_USER" env XDG_RUNTIME_DIR="/run/user/$AWS_METADATA_UID" \
        systemctl --user disable --now aws-metadata-agent.service \
        >/dev/null 2>&1 || true
    fi
    systemctl disable --now aws-metadata-agent.socket \
      aws-metadata-agent-address.service >/dev/null 2>&1 || true
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

#!/usr/bin/env bash

set -eu
set -o pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly PROJECT_DIR
target_user=${SUDO_USER:-${USER:-}}
target_home=''
target_uid=''
linux_linger_was_enabled=''
aws_runas=''
user_path=${AWS_METADATA_USER_PATH:-$PATH}
readonly SERVICE_DIR=/usr/local/libexec/aws-metadata-agent
readonly SERVICE_AWS_RUNAS=$SERVICE_DIR/aws-runas
readonly SERVICE_SERVER=$SERVICE_DIR/aws-metadata-server
readonly SERVICE_FORWARDER=$SERVICE_DIR/aws-metadata-forwarder
readonly SERVICE_NETWORK=$SERVICE_DIR/aws-metadata-network

macos_home_directory() {
  local record

  record=$(dscl . -read "/Users/$1" NFSHomeDirectory 2>/dev/null) || return 1
  record=${record#*:}
  # Remove only the attribute separator whitespace. Preserve spaces and other
  # valid characters in the home-directory path itself.
  record=${record#"${record%%[![:space:]]*}"}
  printf '%s\n' "$record"
}

xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

sed_replacement_escape() {
  printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

find_systemd_socket_proxyd() {
  local candidate

  candidate=$(command -v systemd-socket-proxyd || true)
  if [[ -n $candidate ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  for candidate in \
    /usr/lib/systemd/systemd-socket-proxyd \
    /lib/systemd/systemd-socket-proxyd; do
    if [[ -x $candidate ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

usage() {
  cat <<'EOF'
Usage: ./install.sh [--user USER] [--aws-runas PATH]

Installs a user-owned aws-runas credential broker plus the minimum privileged
network forwarding needed for the standard 169.254.169.254:80 endpoint.
Administrator access is required during installation.
EOF
}

launchctl_bootstrap_with_retry() {
  local domain=$1
  local plist=$2
  local label=$3
  local bootstrap_output=''

  for _ in {1..20}; do
    if bootstrap_output=$(launchctl bootstrap "$domain" "$plist" 2>&1); then
      return 0
    fi
    sleep 0.1
  done

  printf 'Unable to bootstrap launchd service %s:\n%s\n' \
    "$label" "$bootstrap_output" >&2
  return 1
}

while (($#)); do
  case $1 in
    --user)
      shift
      target_user=${1:?--user requires a value}
      ;;
    --aws-runas)
      shift
      aws_runas=${1:?--aws-runas requires a value}
      ;;
    --user-path)
      shift
      user_path=${1:?--user-path requires a value}
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

if [[ -z $target_user || $target_user == root ]]; then
  printf '%s\n' 'Unable to identify the non-root user who owns the AWS configuration.' >&2
  printf '%s\n' 'Run without sudo or provide --user USER.' >&2
  exit 2
fi

if [[ -z $aws_runas ]]; then
  aws_runas=$(command -v aws-runas || true)
fi

case $(uname -s) in
  Darwin)
    target_home=$(macos_home_directory "$target_user")
    target_uid=$(id -u "$target_user")
    ;;
  Linux)
    target_home=$(getent passwd "$target_user" | awk -F: '{print $6}')
    target_uid=$(id -u "$target_user")
    linux_linger_was_enabled=$(loginctl show-user "$target_user" \
      --property=Linger --value 2>/dev/null || printf 'no')
    ;;
  *)
    printf '%s\n' 'Only macOS and Linux are supported.' >&2
    exit 2
    ;;
esac

if [[ -z $target_home || ! -d $target_home ]]; then
  printf 'Unable to determine the home directory for %s.\n' "$target_user" >&2
  exit 2
fi

if [[ -z $aws_runas && -x $target_home/.local/bin/aws-runas ]]; then
  aws_runas=$target_home/.local/bin/aws-runas
fi
if [[ -z $aws_runas || ! -x $aws_runas ]]; then
  printf '%s\n' 'aws-runas was not found in PATH or ~/.local/bin.' >&2
  printf '%s\n' 'Run ./bootstrap.sh or provide --aws-runas PATH.' >&2
  exit 2
fi

if ((EUID != 0)); then
  sudo_args=(
    "$0"
    --user "$target_user"
    --aws-runas "$aws_runas"
    --user-path "$user_path"
  )
  exec sudo "${sudo_args[@]}"
fi

# Preserve the pre-install linger state across upgrades so uninstall can undo
# only the change originally made by this project.
if [[ $(uname -s) == Linux && -r /etc/aws-metadata-agent/config ]]; then
  prior_linger=$(awk -F= '$1 == "AWS_METADATA_LINGER_WAS_ENABLED" { print $2 }' \
    /etc/aws-metadata-agent/config)
  if [[ $prior_linger == yes || $prior_linger == no ]]; then
    linux_linger_was_enabled=$prior_linger
  fi
fi

case $(uname -s) in
  Darwin) root_group=wheel ;;
  Linux) root_group=root ;;
esac
target_group=$(id -gn "$target_user")

install -d -m 0755 /usr/local/bin /usr/local/libexec
install -d -o root -g "$root_group" -m 0755 \
  "$SERVICE_DIR" /etc/aws-metadata-agent
install -m 0755 "$PROJECT_DIR/bin/aws-metadata" /usr/local/bin/aws-metadata
# Remove the compatibility shim installed by earlier versions. Personal
# scripts such as ~/bin/runas.sh are intentionally untouched.
rm -f /usr/local/bin/runas.sh
install -m 0755 "$PROJECT_DIR/libexec/aws-metadata-server" "$SERVICE_SERVER"
install -m 0755 "$PROJECT_DIR/libexec/aws-metadata-forwarder" "$SERVICE_FORWARDER"
install -m 0755 "$PROJECT_DIR/libexec/aws-metadata-network" "$SERVICE_NETWORK"
if [[ $aws_runas != "$SERVICE_AWS_RUNAS" ]]; then
  install -m 0755 "$aws_runas" "$SERVICE_AWS_RUNAS"
fi
chown root:"$root_group" \
  "$SERVICE_SERVER" "$SERVICE_FORWARDER" "$SERVICE_NETWORK" "$SERVICE_AWS_RUNAS"
chmod 0755 \
  "$SERVICE_SERVER" "$SERVICE_FORWARDER" "$SERVICE_NETWORK" "$SERVICE_AWS_RUNAS"

{
  printf 'AWS_METADATA_USER=%q\n' "$target_user"
  printf 'AWS_METADATA_UID=%q\n' "$target_uid"
  printf 'AWS_METADATA_HOME=%q\n' "$target_home"
  printf 'AWS_RUNAS=%q\n' "$SERVICE_AWS_RUNAS"
  printf 'AWS_METADATA_PORT=%q\n' '18080'
  printf 'AWS_METADATA_LINGER_WAS_ENABLED=%q\n' "$linux_linger_was_enabled"
} >/etc/aws-metadata-agent/config
chown root:"$root_group" /etc/aws-metadata-agent/config
chmod 0644 /etc/aws-metadata-agent/config

case $(uname -s) in
  Darwin)
    log_path_xml=$(xml_escape "$target_home/Library/Logs/aws-metadata-agent.log")
    log_path_replacement=$(sed_replacement_escape "$log_path_xml")
    agent_dir=$target_home/Library/LaunchAgents
    log_dir=$target_home/Library/Logs
    agent_file=$agent_dir/com.github.so1omon563.aws-metadata-agent.broker.plist
    forwarder_file=/Library/LaunchDaemons/com.github.so1omon563.aws-metadata-agent.forwarder.plist
    proxy_dir='/Library/Application Support/aws-metadata-agent'
    proxy_file=$proxy_dir/com.github.so1omon563.aws-metadata-agent.proxy.plist
    legacy_agent_file=$agent_dir/com.github.aws-metadata-agent.broker.plist
    legacy_forwarder_file=/Library/LaunchDaemons/com.github.aws-metadata-agent.forwarder.plist
    legacy_proxy_file=$proxy_dir/com.github.aws-metadata-agent.proxy.plist

    install -d -o "$target_user" -g "$target_group" -m 0755 "$agent_dir" "$log_dir"
    sed "s|__LOG_PATH__|$log_path_replacement|g" \
      "$PROJECT_DIR/launchd/com.github.so1omon563.aws-metadata-agent.broker.plist" \
      >"$agent_file"
    chown "$target_user":"$target_group" "$agent_file"
    chmod 0644 "$agent_file"

    launchctl bootout \
      "gui/$target_uid/com.github.so1omon563.aws-metadata-agent.broker" \
      >/dev/null 2>&1 || true
    launchctl bootout \
      "gui/$target_uid/com.github.aws-metadata-agent.broker" \
      >/dev/null 2>&1 || true
    launchctl bootout system/com.github.so1omon563.aws-metadata-agent.forwarder \
      >/dev/null 2>&1 || true
    launchctl bootout system/com.github.so1omon563.aws-metadata-agent.proxy \
      >/dev/null 2>&1 || true
    # Remove jobs and files from the generic pre-publication namespace, plus
    # the root-running service used by pre-privilege-separation builds.
    launchctl bootout system/com.github.aws-metadata-agent >/dev/null 2>&1 || true
    launchctl bootout system/com.github.aws-metadata-agent.forwarder \
      >/dev/null 2>&1 || true
    launchctl bootout system/com.github.aws-metadata-agent.proxy \
      >/dev/null 2>&1 || true
    rm -f \
      /Library/LaunchDaemons/com.github.aws-metadata-agent.plist \
      "$legacy_agent_file" "$legacy_forwarder_file" "$legacy_proxy_file"
    # Clean up PF state left by the earlier redirect-based implementation.
    /sbin/pfctl -a com.apple/aws-metadata-agent -F all >/dev/null 2>&1 || true
    if [[ -r /var/run/aws-metadata-agent/pf-token ]]; then
      /sbin/pfctl -X "$(</var/run/aws-metadata-agent/pf-token)" >/dev/null 2>&1 || true
      rm -f /var/run/aws-metadata-agent/pf-token
    fi
    install -o root -g wheel -m 0644 \
      "$PROJECT_DIR/launchd/com.github.so1omon563.aws-metadata-agent.forwarder.plist" \
      "$forwarder_file"
    install -d -o root -g wheel -m 0755 "$proxy_dir"
    install -o root -g wheel -m 0644 \
      "$PROJECT_DIR/launchd/com.github.so1omon563.aws-metadata-agent.proxy.plist" \
      "$proxy_file"
    rm -f /etc/aws-metadata-agent/pf.conf
    launchctl_bootstrap_with_retry \
      "gui/$target_uid" "$agent_file" \
      com.github.so1omon563.aws-metadata-agent.broker
    launchctl_bootstrap_with_retry \
      system "$forwarder_file" \
      com.github.so1omon563.aws-metadata-agent.forwarder

    metadata_ready=false
    printf '%s' 'Waiting for the metadata endpoint'
    for _ in {1..50}; do
      if curl --silent --show-error --noproxy '*' \
        --connect-timeout 1 --max-time 2 \
        --output /dev/null http://169.254.169.254/profile 2>/dev/null; then
        metadata_ready=true
        break
      fi
      printf '.'
      sleep 0.1
    done
    printf '\n'
    if [[ $metadata_ready != true ]]; then
      printf '%s\n' \
        'Installation did not make http://169.254.169.254 reachable.' >&2
      printf '%s\n' \
        'Review /var/log/aws-metadata-agent-forwarder.log for launchd errors.' >&2
      exit 1
    fi
    ;;
  Linux)
    proxy=$(find_systemd_socket_proxyd || true)
    if [[ -z $proxy ]]; then
      printf '%s\n' 'systemd-socket-proxyd is required but was not found.' >&2
      exit 2
    fi

    # Stop either an older root broker or the current socket proxy before
    # replacing the system unit with the privilege-separated definition.
    systemctl stop aws-metadata-agent.service >/dev/null 2>&1 || true

    user_unit_dir=$target_home/.config/systemd/user
    install -d -o "$target_user" -g "$target_group" -m 0755 \
      "$target_home/.config" "$target_home/.config/systemd" "$user_unit_dir"
    install -o "$target_user" -g "$target_group" -m 0644 \
      "$PROJECT_DIR/systemd/aws-metadata-agent.service" \
      "$user_unit_dir/aws-metadata-agent.service"
    install -o root -g root -m 0644 \
      "$PROJECT_DIR/systemd/aws-metadata-agent-address.service" \
      /etc/systemd/system/aws-metadata-agent-address.service
    install -o root -g root -m 0644 \
      "$PROJECT_DIR/systemd/aws-metadata-agent.socket" \
      /etc/systemd/system/aws-metadata-agent.socket
    sed "s|__SYSTEMD_SOCKET_PROXYD__|$proxy|g" \
      "$PROJECT_DIR/systemd/aws-metadata-agent-proxy.service" \
      >/etc/systemd/system/aws-metadata-agent.service
    chown root:root /etc/systemd/system/aws-metadata-agent.service
    chmod 0644 /etc/systemd/system/aws-metadata-agent.service

    loginctl enable-linger "$target_user"
    systemctl daemon-reload
    sudo -u "$target_user" env XDG_RUNTIME_DIR="/run/user/$target_uid" \
      systemctl --user daemon-reload
    sudo -u "$target_user" env XDG_RUNTIME_DIR="/run/user/$target_uid" \
      systemctl --user enable aws-metadata-agent.service
    sudo -u "$target_user" env XDG_RUNTIME_DIR="/run/user/$target_uid" \
      systemctl --user restart aws-metadata-agent.service
    systemctl enable aws-metadata-agent-address.service aws-metadata-agent.socket
    systemctl restart aws-metadata-agent-address.service aws-metadata-agent.socket
    ;;
esac

printf 'aws-metadata-agent installed for %s.\n' "$target_user"
printf '%s\n' 'The credential broker runs as that user; only networking runs as root.'
printf '%s\n' 'Run: aws-metadata status'
printf '%s\n' 'Open: http://169.254.169.254'
case :${user_path}: in
  *:/usr/local/bin:*) ;;
  *)
    printf '%s\n' 'WARNING: /usr/local/bin is not in the user PATH.' >&2
    printf '%s\n' 'For zsh, add this line to ~/.zprofile:' >&2
    # shellcheck disable=SC2016
    printf '%s\n' '  export PATH="/usr/local/bin:$PATH"' >&2
    ;;
esac

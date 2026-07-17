#!/usr/bin/env bash

set -eu

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_DIR

for script in \
  "$PROJECT_DIR/bin/aws-metadata" \
  "$PROJECT_DIR/libexec/aws-metadata-server" \
  "$PROJECT_DIR/libexec/aws-metadata-forwarder" \
  "$PROJECT_DIR/libexec/aws-metadata-network" \
  "$PROJECT_DIR/bootstrap.sh" \
  "$PROJECT_DIR/install-release.sh" \
  "$PROJECT_DIR/install.sh" \
  "$PROJECT_DIR/uninstall.sh" \
  "$PROJECT_DIR/tests/cli.sh" \
  "$PROJECT_DIR/tests/layout.sh" \
  "$PROJECT_DIR/tests/release-installer.sh" \
  "$PROJECT_DIR/tests/fixtures/curl"; do
  bash -n "$script"
done

sh -n "$PROJECT_DIR/install-release.sh"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint \
    "$PROJECT_DIR/launchd/com.github.so1omon563.aws-metadata-agent.broker.plist"
  plutil -lint \
    "$PROJECT_DIR/launchd/com.github.so1omon563.aws-metadata-agent.forwarder.plist"
  plutil -lint \
    "$PROJECT_DIR/launchd/com.github.so1omon563.aws-metadata-agent.proxy.plist"
fi

printf '%s\n' 'Syntax checks passed.'

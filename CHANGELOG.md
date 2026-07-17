# Changelog

## v0.1.0 - 2026-07-16

Initial release of `aws-metadata-agent`.

### Added

- Privilege-separated `launchd` and systemd services that expose `aws-runas`
  through the standard EC2 metadata endpoint at `169.254.169.254`.
- Checksum-verified bootstrap of the pinned upstream `aws-runas` 3.9.0
  release.
- The `aws-metadata` command for service health, profile selection, browser
  authentication, refresh, logs, and diagnostics.
- Root-owned service executables and minimal privileged forwarding layers that
  keep AWS profile and credential access in the installing user's process.
- Credential-free local tests and hosted macOS and Ubuntu CI.

### Supported hosts

- Apple Silicon macOS 26 with `launchd`, validated on macOS 26.5.2.
- Ubuntu 24.04 LTS ARM64 with systemd, validated on Ubuntu 24.04.4.

Other host configurations and Linux container-runtime access remain
unverified. The metadata endpoint exposes one globally active profile, and the
active selection must be restored after the broker restarts.

# Changelog

All notable changes to this project are documented here. Changes remain under
`Unreleased` until a tagged release is prepared.

## [Unreleased]

## [0.2.1] - 2026-07-17

### Added

- An inspect-first direct release installer that requires an explicit version,
  verifies a project-uploaded release archive against its published SHA-256,
  and fails closed before handing off to the existing privileged installer.
- An integration-focused `aws-runas` configuration guide with sanitized
  IAM, browser-SAML, OIDC, and metadata-consumer examples plus direct links to
  the authoritative upstream documentation.
- Automated release preparation, semantic-version tagging, verified GitHub
  release assets, and tested Homebrew tap publication.

### Changed

- Reorganized the README around project purpose, operation, support,
  installation, usage, architecture, maintenance, operational considerations,
  and development while retaining the detailed engineering content.
- Clarified the Homebrew package-installation, privileged service-setup, and
  conditional browser-authentication permission boundaries.

### Fixed

- Interactive browser-based profile selection now keeps its HTTP request alive
  for the configured authentication wait, including longer password-recovery
  flows, while noninteractive selection retains its short bounded timeout.

### Supported hosts

- Apple Silicon macOS 26 with `launchd`.
- Ubuntu 24.04 LTS ARM64 with systemd.

This release does not expand the host support boundary established by v0.1.0.

## [0.2.0] - 2026-07-16

### Added

- A project version source, installed version reporting, and a documented
  upgrade, rollback, configuration-schema, and release policy.
- A private vulnerability-reporting policy for coordinated disclosure.
- A package-manager-safe `aws-metadata setup` and `aws-metadata uninstall`
  interface that keeps Homebrew installation unprivileged and leaves command
  ownership with Homebrew.

### Supported hosts

- Apple Silicon macOS 26 with `launchd`.
- Ubuntu 24.04 LTS ARM64 with systemd.

This release does not expand the host support boundary established by v0.1.0.

## [0.1.0] - 2026-07-16

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

[Unreleased]: https://github.com/so1omon563/aws-metadata-agent/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/so1omon563/aws-metadata-agent/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/so1omon563/aws-metadata-agent/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/so1omon563/aws-metadata-agent/releases/tag/v0.1.0

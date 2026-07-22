# Changelog

All notable changes to this project are documented here. Changes remain under
`Unreleased` until a tagged release is prepared.

## [Unreleased]

### Fixed

- `aws-metadata clear` no longer prints transient curl transport errors while
  waiting for the user broker to restart, while initial endpoint failures
  retain their diagnostics.

## [0.3.3] - 2026-07-22

### Added

- `aws-metadata active-profile` prints only the exact live upstream profile
  name for Starship, zsh, Bash, fish, editor, and status-bar integrations. The
  uncached lookup uses one bounded IMDS role-name request, stays silent when
  inactive or unavailable, and prevents invalid timeout overrides from
  disabling its prompt-safety deadline.

## [0.3.2] - 2026-07-22

### Added

- `aws-metadata status` now reports the exact active upstream profile name
  alongside the existing live profile details in text and JSON output. The
  name is read from the standard IMDS role-name path without persisting profile
  state.

## [0.3.1] - 2026-07-21

### Added

- An idempotent `aws-metadata clear` command that returns the user broker to
  healthy no-profile state without administrator access, bounds restart and
  recovery time, verifies the result, and does not print the prior profile.

### Changed

- Reorganized documentation into a focused landing page, unbranched quick
  start, concept guide, consolidated verification checklist, symptom-first
  troubleshooting router, and explicit guide/reference hierarchy.
- Made direct-release examples version-neutral while preserving explicit
  inspect-first version selection, and added release validation that rejects
  stale numeric pins in guarded user documentation.

## [0.3.0] - 2026-07-20

### Added

- Actionable profile-selection failures and a bounded, redacted
  `aws-metadata errors` command that classifies recent broker authentication
  failures without printing raw sensitive log lines.
- Direct Stream Deck and GUI automation guidance using the package-managed
  `aws-metadata` CLI, without a wrapper script or terminal window.
- First-class zsh, Bash, and fish PATH and completion setup through
  `bootstrap.sh --configure-shell`, including reviewed completion integrity,
  isolated-shell regression coverage, and unsupported-shell no-op behavior.
- Recurring Docker Engine default-bridge validation on a GitHub-hosted Ubuntu
  24.04 runner, with an immutable credential-free fixture and documented
  container-runtime evidence boundaries.
- End-user documentation organized around suitability, trust boundaries,
  supported installation, upstream profile validation, expected no-profile
  state, provider-isolated AWS identity verification, consumer integration,
  troubleshooting, lifecycle, and maintenance.
- Dedicated documentation index, getting-started guide, CLI reference,
  consumer recipes, troubleshooting guide, contributor guide, and maintainer
  release process.

### Changed

- User upgrade and rollback procedures are separated from release automation;
  architecture and security guides now own detailed topology, IMDS
  compatibility, threat assumptions, state lifetime, and failure behavior.
- Release preparation now keeps the README's pinned Linux quick-start version
  synchronized with direct-install and helper examples.

## [0.2.2] - 2026-07-17

### Fixed

- Interactive browser-based profile selection retries one confirmed transient
  STS 408 after a cold browser login, allowing the newly persisted browser
  session to complete the credential exchange without a second user command.
- Homebrew publication waits for the tap's required test to register before
  watching its result, avoiding a race immediately after opening the tap pull
  request while retaining the protected merge gate.

### Supported hosts

- Apple Silicon macOS 26 with `launchd`.
- Ubuntu 24.04 LTS ARM64 with systemd.

This release does not expand the host support boundary established by v0.1.0.

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

[Unreleased]: https://github.com/so1omon563/aws-metadata-agent/compare/v0.3.3...HEAD
[0.3.3]: https://github.com/so1omon563/aws-metadata-agent/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/so1omon563/aws-metadata-agent/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/so1omon563/aws-metadata-agent/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/so1omon563/aws-metadata-agent/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/so1omon563/aws-metadata-agent/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/so1omon563/aws-metadata-agent/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/so1omon563/aws-metadata-agent/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/so1omon563/aws-metadata-agent/releases/tag/v0.1.0

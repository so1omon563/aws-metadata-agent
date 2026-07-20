# Documentation

The documentation is organized around the path from deciding whether the
project fits to operating it safely.

## Getting started

1. [Getting started](getting-started.md) — choose a supported installation,
   reach expected no-profile state, select one upstream profile, and verify an
   AWS client through metadata.
2. [Homebrew installation](homebrew.md) — supported macOS package, trust,
   setup, browser permission, recovery, upgrade, and uninstall.
3. [Direct release installation](direct-install.md) — supported Ubuntu ARM64
   and secondary macOS inspect-first installation.
4. [Configure aws-runas](aws-runas-configuration.md) — upstream profile
   ownership, sanitized IAM/SAML/OIDC patterns, and official references.

## Use the service

- [CLI reference](cli-reference.md) — command behavior, interactive versus
  automation defaults, diagnostics, and exit codes.
- [Consumer recipes](consumers.md) — AWS CLI, AWS Toolkit for Visual Studio
  Code, SDKs, containers, coding agents, and GUI automation.
- [Container runtime validation](container-runtimes.md) — exact evidence
  boundaries, reproducible routing checks, and runtime caveats.
- [Stream Deck integration](stream-deck.md) — validated macOS GUI automation.

## Operate and understand it

- [Troubleshooting](troubleshooting.md) — a boundary-oriented decision tree,
  browser failures, credential precedence, and partial-install recovery.
- [Upgrades, rollback, and uninstall](upgrades.md) — user procedures by
  installation method.
- [Architecture](architecture.md) — process ownership, files, service startup,
  forwarding, protocol compatibility, failure behavior, concurrency, and
  lifecycle.
- [Security model](security.md) — threat assumptions, credential exposure,
  unauthenticated local switching, privilege boundaries, and a pre-install
  checklist.

## Maintain the project

- [Contributing](../CONTRIBUTING.md) — development checks, sanitized examples,
  and pull-request expectations.
- [Release process](releasing.md) — version staging, CI, GitHub Release assets,
  and Homebrew publication.
- [Security policy](../SECURITY.md) — private vulnerability reporting.
- [Changelog](../CHANGELOG.md) — release-specific changes and validation.

[Back to the project README](../README.md)

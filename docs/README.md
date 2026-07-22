# Documentation

Use this index to stay at the right level: follow a guide to complete a task,
read a concept page to build a mental model, or open reference material for an
exact contract.

## Start here

1. [Getting started](getting-started.md) — install on a supported host,
   configure one upstream profile, select it, and reach a working AWS client.
2. [Concepts](concepts.md) — understand the canonical metadata interface, the
   three profile roles, global selection, and state lifetime.
3. [Verification](verification.md) — prove service, endpoint, profile,
   credentials, and optional consumer boundaries in one checklist.

## Guides

- [Homebrew installation](homebrew.md) — install and set up the supported
  macOS package.
- [Direct release installation](direct-install.md) — inspect and install a
  verified release on supported Ubuntu ARM64 or macOS.
- [Configure aws-runas](aws-runas-configuration.md) — define upstream IAM,
  SAML, OIDC, and consumer compatibility profiles.
- [Consumer recipes](consumers.md) — connect AWS CLI, SDKs, VS Code, coding
  agents, containers, and GUI automation.
- [Shell prompt integration](shell-prompts.md) — display the exact live active
  profile in Starship, zsh, Bash, or fish.
- [Stream Deck integration](stream-deck.md) — invoke the CLI from a validated
  macOS GUI action.
- [Troubleshooting](troubleshooting.md) — start from a visible symptom and
  isolate the failing boundary.

## Concepts

- [Concepts](concepts.md) — user-facing credential and profile model.
- [Container runtime validation](container-runtimes.md) — evidence boundaries
  and runtime-specific routing behavior.

## Reference

- [CLI reference](cli-reference.md) — commands, interaction defaults, JSON,
  diagnostics, and exit codes.
- [Upgrades, rollback, and uninstall](upgrades.md) — lifecycle procedures by
  installation method.
- [Changelog](../CHANGELOG.md) — release-specific changes and validation.

## Architecture and security

- [Architecture](architecture.md) — process ownership, installed files,
  startup, forwarding, protocol compatibility, and failure behavior.
- [Security model](security.md) — threat assumptions, credential exposure,
  privilege boundaries, browser authentication, and pre-install review.
- [Security policy](../SECURITY.md) — supported security-fix versions and
  private vulnerability reporting.

## Maintenance

- [Contributing](../CONTRIBUTING.md) — development checks, sanitized examples,
  and pull-request expectations.
- [Release process](releasing.md) — release preparation, validation, GitHub
  assets, and Homebrew publication.

[Back to the project README](../README.md)

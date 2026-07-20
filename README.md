# aws-metadata-agent

`aws-metadata-agent` makes a developer workstation behave like an EC2 instance
from the perspective of AWS credential discovery.

It exposes temporary credentials from a user-owned
[`aws-runas`](https://mmmorris1975.github.io/aws-runas/) profile through the
standard EC2 instance metadata endpoint. AWS CLI, SDKs, VS Code, containers,
coding agents, and other local tools can then use `http://169.254.169.254`
without project-specific wrappers, credential environment variables, mounted
AWS files, or custom SDK endpoints.

```text
Developer selects an aws-runas profile
                  |
                  v
        aws-metadata-agent
                  |
                  v
        169.254.169.254 (IMDS)
                  |
                  v
   AWS CLI / SDK / VS Code / containers
```

The metadata endpoint becomes the canonical credential interface on the
workstation. Applications continue to use the same credential-discovery path
they would use on EC2.

## Is this for me?

| Good fit | Use another approach when |
| --- | --- |
| An application expects EC2 instance metadata credentials. | Ordinary AWS CLI profile switching already meets the need. |
| A GUI application does not inherit shell credential variables. | Different consumers must use different roles concurrently. |
| Trusted containers should receive temporary credentials without AWS file mounts. | Untrusted local processes or containers can reach the metadata address. |
| Several trusted tools should use one standard credential endpoint. | Workstation-hosted metadata services are prohibited by local policy. |
| Browser-based SAML/OIDC or MFA must remain in the developer's login session. | Profile selection must persist across broker restarts or reboots. |

This project is intended for a trusted, single-developer workstation. It is
not a per-application credential-isolation system.

## Know before installing

- One `aws-runas` profile is active globally. The latest successful selection
  affects every host application and container using the endpoint.
- The active selection is process state. Native services return after logout
  or reboot, but the profile must be selected again after the broker restarts.
- Any process or container that can reach `169.254.169.254` may be able to
  obtain credentials for the active profile or request a profile change.
- Authentication remains in the developer account. The privileged layer owns
  installed code and link-local forwarding, not AWS configuration, browser
  state, or credentials.

Read the complete [security model](docs/security.md) before exposing the
endpoint to software you do not fully trust.

## Supported platforms

| Capability | Apple Silicon macOS 26 | Ubuntu 24.04 ARM64 | Other hosts |
| --- | --- | --- | --- |
| Native install and uninstall | Validated | Validated | Unverified |
| Logout or reboot service persistence | Validated | Validated | Unverified |
| Browser-backed SAML/OIDC | Validated | Unverified | Unverified |
| Standard AWS CLI metadata discovery | Validated | Validated | Unverified |
| Container routing | Docker Desktop validated | Separate Docker Engine x86_64 CI routing evidence | Runtime-specific and unverified |
| Stream Deck automation | Validated | Not applicable | Unverified |

Supported hosts require Bash 3.2 or newer, `aws-runas` 3.9.0, `curl`, and
administrator access during native service setup. Ubuntu additionally
requires systemd with a working user manager, `ip`, `systemctl`, `loginctl`,
`sudo`, and `systemd-socket-proxyd`. `unzip` is required only when bootstrapping
`aws-runas`.

Docker Engine routing is also checked on a GitHub-hosted Ubuntu 24.04 x86_64
runner. That evidence covers container-to-host routing, not native installation
on x86_64. Other versions, architectures, distributions, and runtimes may work
but are outside the current support claim. See the [changelog](CHANGELOG.md)
for release-specific validation.

## Quick start

The complete happy path is in [Getting started](docs/getting-started.md):

1. Install the supported package or release.
2. Confirm one upstream `aws-runas` profile.
3. Set up and check the native service.
4. Select the profile.
5. Run the [verification checklist](docs/verification.md).

For supported macOS, review and trust the tap, install the unprivileged
package, and run the separate service setup:

```sh
brew trust --tap so1omon563/aws-metadata-agent
brew tap so1omon563/aws-metadata-agent
brew install aws-metadata-agent
aws-metadata setup
```

`brew install` does not use `sudo`, install `aws-runas`, change networking, or
load services. `aws-metadata setup` conditionally bootstraps `aws-runas` and
then requests administrator access for native service installation. See
[Homebrew installation](docs/homebrew.md) for the exact setup, trust, browser
permission, recovery, and uninstall behavior.

For supported Ubuntu ARM64, follow the checksum-verified, inspect-first
[direct release installation](docs/direct-install.md). Direct installation
does not bootstrap `aws-runas` automatically.

After installation, select a configured upstream profile:

```sh
aws-metadata status
aws-metadata diagnose
aws-metadata use example-nonprod
```

A newly started broker with no selected profile is healthy. Configure and test
the upstream profile first if selection fails; see
[Configure aws-runas](docs/aws-runas-configuration.md) and the authoritative
[upstream documentation](https://mmmorris1975.github.io/aws-runas/).

## Documentation

Start with the [documentation index](docs/README.md).

| Goal | Page |
| --- | --- |
| Install, configure one profile, and reach a working client | [Getting started](docs/getting-started.md) |
| Understand the profile and credential mental model | [Concepts](docs/concepts.md) |
| Prove each boundary works | [Verification](docs/verification.md) |
| Configure upstream authentication and roles | [Configure aws-runas](docs/aws-runas-configuration.md) |
| Connect AWS CLI, VS Code, SDKs, containers, or automation | [Consumer recipes](docs/consumers.md) |
| Look up command behavior and exit codes | [CLI reference](docs/cli-reference.md) |
| Start from a visible failure symptom | [Troubleshooting](docs/troubleshooting.md) |
| Understand processes, files, forwarding, and lifecycle | [Architecture](docs/architecture.md) |
| Evaluate credential exposure and privilege boundaries | [Security model](docs/security.md) |
| Upgrade, roll back, or uninstall | [Upgrades and rollback](docs/upgrades.md) |

## Development and maintenance

Run the credential-free checks with:

```sh
make test
```

Development and pull-request guidance lives in
[CONTRIBUTING.md](CONTRIBUTING.md). Maintainers should use the
[release process](docs/releasing.md); suspected vulnerabilities should be
reported privately through [SECURITY.md](SECURITY.md).

## License

The original project code is available under the [MIT License](LICENSE).
Third-party attribution for the separately downloaded `aws-runas` dependency
is recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

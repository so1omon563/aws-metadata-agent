# aws-metadata-agent

Run the `aws-runas` EC2 metadata credential service as a native background
service on macOS or Linux while retaining the standard
`http://169.254.169.254` endpoint.

This project is intended for developer workstations where applications such as
VS Code, containers, SDKs, and coding agents need to discover AWS credentials
through the normal EC2 instance metadata provider chain.

## How it works

`aws-metadata-agent` keeps `aws-runas` running as a developer-owned credential
broker and exposes it through the standard EC2 metadata endpoint.

The broker handles active-profile selection, SAML/OIDC authentication, and MFA.
Native `launchd` or systemd components keep the broker running and provide the
minimum privileged networking needed to forward `169.254.169.254:80` to it.
The detailed process and filesystem boundaries are described in
[Architecture](#architecture).

Applications continue to use the standard EC2 metadata endpoint exactly as
they would on an EC2 instance, without requiring project-specific wrappers,
credential environment variables, or SDK endpoint configuration.

## Supported platforms

The `v0.2.0` support boundary remains limited to the two host configurations
that have passed end-to-end validation:

- Apple Silicon macOS 26 with `launchd`, tested on macOS 26.5.2 with
  `aws-runas` 3.9.0. Validation covered installation, no-profile startup,
  profile selection, browser-based authentication, standard AWS CLI credential
  discovery, reboot persistence, Docker Desktop access, uninstall, and clean
  reinstall.
- Ubuntu 24.04 LTS ARM64 with systemd, tested on Ubuntu 24.04.4 in UTM with
  `aws-runas` 3.9.0. Validation covered checksum-verified bootstrap,
  installation, no-profile startup, profile selection, standard AWS CLI
  credential discovery, logout/reboot service persistence, and clean
  uninstall.

Other macOS versions and architectures, other Linux distributions and
architectures, and Linux container-runtime access may work but are not part of
the `v0.2.0` support claim. The active profile is process state: after a service
restart or reboot, select the profile again before requesting credentials.

## Requirements

For a supported host configuration:

- Apple Silicon macOS 26 with `launchd`; or
- Ubuntu 24.04 LTS ARM64 with systemd

Both platforms require:

- Bash 3.2 or newer
- `aws-runas`
- `curl`
- `unzip` when using the optional bootstrap command
- Administrator access during installation

Linux installation additionally requires `ip`, `systemctl`, `loginctl`,
`sudo`, a running system systemd manager, and a working systemd user manager.
The installer finds `systemd-socket-proxyd` in `PATH` or in standard systemd
private executable directories such as Ubuntu's `/usr/lib/systemd`.

No terminal multiplexer is required.

## Installation

### Homebrew on macOS

Homebrew is the primary installation path on supported macOS hosts:

```sh
brew trust --tap so1omon563/aws-metadata-agent
brew tap so1omon563/aws-metadata-agent
brew install aws-metadata-agent
aws-metadata setup
```

The formula installation is unprivileged. The explicit setup command invokes
the reviewed installer for the link-local address and launchd services. If
needed, it downloads `aws-runas` directly from the official upstream release
through the existing checksum-verified bootstrap; the formula does not bundle
or mirror it.

See [docs/homebrew.md](docs/homebrew.md) for trust, upgrade, rollback,
uninstall, and recovery instructions.

### Direct release install

For supported Linux hosts, or as a secondary macOS option, use an explicitly
pinned release. The recommended flow downloads the project-uploaded release
archive and its published SHA-256, verifies it, and gives you a chance to
inspect the existing installer before execution.

See [docs/direct-install.md](docs/direct-install.md) for the complete
inspect-first commands, the small `install-release.sh` helper, the explicit
warning before its optional piped form, and rollback and uninstall guidance.

### Source install

```sh
./install.sh
```

Run the installer on the host operating system, not inside a container. On
Linux, the host must provide the system and user systemd managers described in
the requirements above. Containers remain useful as consumers of the metadata
endpoint, but they are not a supported installation target.

The installer searches both `PATH` and `$HOME/.local/bin/aws-runas`, so a shell
restart is not required immediately after bootstrapping.

### Installing the upstream dependency

If `aws-runas` is not already installed, the optional bootstrap command
downloads a pinned, unmodified release directly from the upstream project and
verifies it against the upstream SHA-256 checksum file:

```sh
./bootstrap.sh
```

Preview the URLs and destination without downloading anything:

```sh
./bootstrap.sh --dry-run
```

To install another upstream release or use a user-owned binary directory:

```sh
./bootstrap.sh --version 3.9.0
```

The bootstrapper does not package or mirror `aws-runas`. It downloads from
the official [aws-runas repository](https://github.com/mmmorris1975/aws-runas),
prints the upstream source, and retains the upstream MIT attribution in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The default bootstrap destination is `$HOME/.local/bin`. If that directory is
not in `PATH`, the command prints the exact zsh configuration line to add. It
does not modify shell startup files.

To configure zsh explicitly and idempotently:

```sh
./bootstrap.sh --configure-shell
```

This adds managed blocks to `~/.zprofile` for PATH and `~/.zshrc` for
completion, then installs the upstream completion under
`~/.local/share/aws-runas`. Existing content outside those marked blocks is
preserved. Shell files are never modified without `--configure-shell`.

Existing hand-written `aws-runas` configuration outside the managed blocks is
never removed. Bootstrap warns when it detects such configuration so the user
can review possible duplicate completion loading.

Because completion files are sourced as shell code, the bootstrapper records
and verifies a reviewed SHA-256 checksum for each supported completion version.
It refuses to configure completion for an unreviewed version even if that
version's binary can be downloaded successfully.

### Configure aws-runas

Profiles remain user-owned upstream configuration. Before selecting a profile,
configure it in the standard AWS files used by `aws-runas`. See
[Configure aws-runas](docs/aws-runas-configuration.md) for sanitized IAM, SAML,
and OIDC examples, the project/upstream ownership boundary, and direct links to
the authoritative [aws-runas documentation](https://mmmorris1975.github.io/aws-runas/).

## Usage

Switch profiles interactively. This opens the browser when authentication is
required and waits up to 300 seconds by default:

```sh
aws-metadata use my-profile
```

The lower-level command is automation-safe by default and reports
authentication as a nonzero exit:

```sh
aws-metadata profile my-profile --no-open --json
aws-metadata profile my-profile --open --wait 300
```

Existing personal `runas.sh PROFILE` scripts can continue posting to the
metadata endpoint, but the package does not install that user-specific
compatibility command.

Other commands:

```sh
aws-metadata open
aws-metadata refresh
aws-metadata status
aws-metadata status --json
aws-metadata logs
aws-metadata diagnose
aws-metadata version
aws-metadata setup
aws-metadata uninstall
```

Exit codes used by `profile`:

| Code | Meaning |
| ---: | --- |
| 0 | Profile selected and credentials are ready |
| 2 | Invalid command-line usage |
| 3 | Metadata service unavailable |
| 4 | Browser authentication required |
| 5 | Authentication wait timed out |
| 6 | Unexpected HTTP response |

### Browser authentication

`aws-runas` provides its browser interface at:

```text
http://169.254.169.254
```

That interface handles active-profile selection, SAML/OIDC authentication, and
MFA without requiring the server process to remain attached to a terminal.

When testing an unprivileged broker directly, custom AWS SDK endpoints must
include the trailing slash:

```sh
AWS_EC2_METADATA_SERVICE_ENDPOINT=http://127.0.0.1:18080/ aws sts get-caller-identity
```

After a full install, applications use the standard endpoint and do not need
that variable.

## Architecture

This section describes the privilege boundaries and service layout used to
expose the EC2 metadata endpoint while keeping AWS authentication in the
developer's account.

```text
Application / AWS SDK / AWS CLI
              |
              v
      169.254.169.254:80
              |
              v
  Privileged forwarding layer
 (launchd or systemd socket)
              |
              v
       127.0.0.1:18080
              |
              v
aws-runas broker (developer account)
              |
              v
 AWS authentication and credentials
```

### Installed layout

The installer finds the current `aws-runas` executable and installs:

- `aws-metadata` into `/usr/local/bin`
- the release version into `/usr/local/libexec/aws-metadata-agent/VERSION`
- a protected copy of `aws-runas` under
  `/usr/local/libexec/aws-metadata-agent`, executed as the installing user
- a user LaunchAgent on macOS or user systemd service on Linux
- a minimal privileged link-local forwarding service
- a configuration file at `/etc/aws-metadata-agent/config`

### Privilege separation

The service never executes `aws-runas` from a user-writable directory. The
installer copies the selected binary into its root-owned `libexec` directory
and uses that absolute path from the service definition. The process itself
runs with the developer's uid, so cache files and browser authentication stay
in the developer account. It listens only on `127.0.0.1:18080`.

The installer never installs, stores, or selects an AWS profile. Profiles are
user-specific and are selected after installation with `aws-metadata use`.
The installer also does not modify shell startup files and does not initialize
or publish a Git repository.

### Platform forwarding

On macOS, a small root LaunchDaemon creates the loopback alias and asks launchd
to own `169.254.169.254:80`. For each accepted connection, launchd runs the
system `nc` command as `nobody` to connect it to the user broker. On Linux, a
root oneshot service owns the loopback address and a systemd socket forwards
port 80 through `systemd-socket-proxyd`. Neither privileged component reads
AWS configuration or credential files.

Architecture-specific security properties and limitations are documented in
[docs/security.md](docs/security.md). The broader component and data flow is
documented in [docs/architecture.md](docs/architecture.md).

## Maintenance

Use `aws-metadata version` to identify the installed release. See
[docs/upgrades.md](docs/upgrades.md) for the versioning, in-place upgrade,
rollback, uninstall, and release policy.

### Uninstall

For a Homebrew installation, remove service state before the formula:

```sh
aws-metadata uninstall
brew uninstall aws-metadata-agent
```

For a source installation:

```sh
./uninstall.sh
```

### Security reports

Report suspected vulnerabilities privately as described in
[SECURITY.md](SECURITY.md).

## Operational considerations

### One active profile

EC2 metadata exposes one globally active profile. If a Stream Deck action,
VS Code, and a coding agent change profiles concurrently, the most recent
selection wins. See [docs/architecture.md](docs/architecture.md) for the
planned lease/locking design.

### Containers

The standard metadata endpoint has been validated from Docker Desktop on the
tested Apple Silicon macOS setup. No AWS credential environment variables or
mounted AWS configuration files were needed in that validation.

Container runtimes and host configurations vary in how they route the reserved
metadata address. Test the runtime used by your team; a container may need an
explicit route to the host or may reserve `169.254.169.254` for its own
metadata proxy. The installer does not change Docker, Podman, or Kubernetes
networking. Linux container runtime access remains separately unverified.

## Development

Run the local, credential-free checks with:

```sh
make test
```

The CLI tests use a fake `curl` executable and do not contact AWS or the local
metadata address.

## License

The original project code is available under the [MIT License](LICENSE).
Third-party attribution for the separately downloaded `aws-runas` dependency
is recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

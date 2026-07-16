# aws-metadata-agent

Run the `aws-runas` EC2 metadata credential service as a native background
service on macOS or Linux while retaining the standard
`http://169.254.169.254` endpoint.

This project is intended for developer workstations where applications such as
VS Code, containers, SDKs, and coding agents need to discover AWS credentials
through the normal EC2 instance metadata provider chain.

## Status

The privilege-separated macOS path has been validated on Apple Silicon with
`aws-runas` 3.9.0, including installation, profile selection, browser-based
authentication, AWS CLI credential discovery, reboot persistence, Docker
Desktop access, uninstall, and clean reinstall.

Linux support is implemented but has not yet been integration-tested on a real
systemd workstation or VM. Treat Linux as experimental until its install,
profile selection, IMDS access, logout/reboot persistence, and uninstall paths
have been validated on a representative distribution.

## Requirements

- macOS with `launchd`, or Linux with systemd
- Bash 3.2 or newer
- `aws-runas`
- `curl`
- `unzip` when using the optional bootstrap command
- Administrator access during installation

No terminal multiplexer is required.

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
`mmmorris1975/aws-runas`, prints the upstream source, and retains the upstream
MIT attribution in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

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

## Install

```sh
./install.sh
```

The installer finds the current `aws-runas` executable and installs:

- `aws-metadata` into `/usr/local/bin`
- a protected copy of `aws-runas` under
  `/usr/local/libexec/aws-metadata-agent`, executed as the installing user
- a user LaunchAgent on macOS or user systemd service on Linux
- a minimal privileged link-local forwarding service
- a configuration file at `/etc/aws-metadata-agent/config`

The service never executes `aws-runas` from a user-writable directory. The
installer copies the selected binary into its root-owned `libexec` directory
and uses that absolute path from the service definition. The process itself
runs with the developer's uid, so cache files and browser authentication stay
in the developer account. It listens only on `127.0.0.1:18080`.

On macOS, a small root LaunchDaemon creates the loopback alias and asks launchd
to own `169.254.169.254:80`. For each accepted connection, launchd runs the
system `nc` command as `nobody` to connect it to the user broker. On Linux, a
root oneshot service owns the loopback address and a systemd socket forwards
port 80 through `systemd-socket-proxyd`. Neither privileged component reads
AWS configuration or credential files.

The installer searches both `PATH` and `$HOME/.local/bin/aws-runas`, so a shell
restart is not required immediately after bootstrapping.

The installer never installs, stores, or selects an AWS profile. Profiles are
user-specific and are selected after installation with `aws-metadata use`.
The installer also does not modify shell startup files and does not initialize
or publish a Git repository.

## Development

Run the local, credential-free checks with:

```sh
make test
```

The CLI tests use a fake `curl` executable and do not contact AWS or the local
metadata address.

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

## Authentication

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

## Containers

The standard metadata endpoint has been validated from Docker Desktop on the
tested Apple Silicon macOS setup. No AWS credential environment variables or
mounted AWS configuration files were needed in that validation.

Container runtimes and host configurations vary in how they route the reserved
metadata address. Test the runtime used by your team; a container may need an
explicit route to the host or may reserve `169.254.169.254` for its own
metadata proxy. The installer does not change Docker, Podman, or Kubernetes
networking. Linux container access remains unverified with the rest of the
Linux integration path.

## Important limitation

EC2 metadata exposes one globally active profile. If a Stream Deck action,
VS Code, and a coding agent change profiles concurrently, the most recent
selection wins. See [docs/architecture.md](docs/architecture.md) for the
planned lease/locking design.

## Uninstall

```sh
./uninstall.sh
```

## License

The original project code is available under the [MIT License](LICENSE).
Third-party attribution for the separately downloaded `aws-runas` dependency
is recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

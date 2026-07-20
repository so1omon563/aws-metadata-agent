# aws-metadata-agent

Expose temporary credentials from a user-owned [`aws-runas`](https://mmmorris1975.github.io/aws-runas/)
profile through the standard EC2 instance metadata endpoint on a macOS or
Linux developer workstation.

`aws-metadata-agent` fills the gap between the upstream credential broker and
applications that only know how to use the normal AWS credential provider
chain. VS Code, containers, SDKs, coding agents, and other local tools can use
`http://169.254.169.254` without project-specific wrappers, credential
environment variables, mounted AWS files, or custom SDK endpoints.

## Is this for me?

| Good fit | Use another approach when |
| --- | --- |
| An application expects EC2 instance metadata credentials. | Ordinary AWS CLI profile switching already meets the need. |
| A GUI application does not inherit shell credential variables. | Different consumers must use different roles concurrently. |
| Trusted containers should receive temporary credentials without AWS file mounts. | Untrusted local processes or containers can reach the metadata address. |
| Several trusted tools should use one standard credential endpoint. | Workstation-hosted metadata services are prohibited by local policy. |
| Browser-based SAML/OIDC or MFA must remain in the developer's login session. | Profile selection must persist across broker restarts or reboots. |
| The host matches a validated macOS or Ubuntu configuration. | Windows or an unvalidated host is required as a supported target. |

This project is intended for a trusted, single-developer workstation. It is
not a per-application credential-isolation system.

## Important behavior and trust model

Before installing, understand these product boundaries:

- **One profile is active globally.** The most recent successful profile
  selection affects every host application and container using this endpoint.
- **The active selection is process state.** Native services restart after
  logout or reboot, but the profile must be selected again after the broker
  restarts.
- **Credentials are intentionally reachable.** Any process or container that
  can reach `169.254.169.254` may be able to obtain credentials for the active
  profile.
- **Local profile switching is intentionally unauthenticated.** A caller that
  can reach the local metadata HTTP API can request another configured profile.
- **Authentication remains unprivileged.** `aws-runas`, its browser session,
  AWS configuration, and caches remain in the developer account. Root owns
  only the installed executable copies and link-local forwarding layer.
- **Support claims are evidence-bound.** Other hosts and runtimes may work, but
  unvalidated configurations are not presented as supported.

Read the complete [security model](docs/security.md) before exposing the
endpoint to containers or other software you do not fully trust.

## How it works

There are three distinct profile concepts:

```text
upstream aws-runas profile       example-nonprod in ~/.aws/config
                                       |
                                       | aws-metadata use example-nonprod
                                       v
active agent profile             one globally exposed identity
                                       |
                                       | EC2 metadata credential provider
                                       v
consumer compatibility profile  local-metadata (optional)
```

The **upstream profile** defines how `aws-runas` authenticates and assumes a
role. The **active agent profile** is the one upstream profile currently
exposed at the metadata endpoint. An optional **consumer compatibility
profile**, such as `local-metadata`, tells a profile-oriented tool like the AWS
Toolkit for Visual Studio Code to use EC2 metadata.

Applications do not select `example-nonprod`. The agent selects it globally;
applications consume whichever upstream profile is currently active. Most AWS
SDKs and tools that already use the default credential provider chain do not
need a consumer compatibility profile.

The developer-owned broker listens on `127.0.0.1:18080`. Native `launchd` or
systemd components keep it running and provide the minimum privileged
networking needed to forward `169.254.169.254:80` to it. See
[Architecture](docs/architecture.md) for the complete topology, installed
layout, startup order, protocol boundary, and lifecycle.

## Supported platforms

The current `0.2.x` line is supported only on the two host configurations that
have passed end-to-end validation:

- **Apple Silicon macOS 26 with `launchd`.** Tested on the marketing
  `ProductVersion` reported by `sw_vers` as macOS 26.5.2, with `aws-runas`
  3.9.0. Validation covered installation, expected no-profile startup, profile
  selection, browser authentication, standard AWS CLI credential discovery,
  reboot persistence, Docker Desktop access, uninstall, and clean reinstall.
- **Ubuntu 24.04 LTS ARM64 with systemd.** Tested on Ubuntu 24.04.4 in UTM with
  `aws-runas` 3.9.0. Validation covered checksum-verified bootstrap,
  installation, expected no-profile startup, profile selection, standard AWS
  CLI credential discovery, logout/reboot service persistence, and clean
  uninstall.

| Capability | Apple Silicon macOS 26 | Ubuntu 24.04 ARM64 | Other hosts |
| --- | --- | --- | --- |
| Native install and uninstall | Validated | Validated | Unverified |
| Logout or reboot service persistence | Validated | Validated | Unverified |
| Browser-backed SAML/OIDC | Validated | Unverified | Unverified |
| Standard AWS CLI metadata discovery | Validated | Validated | Unverified |
| Container routing | Docker Desktop validated | Separate Docker Engine x86_64 CI routing evidence | Runtime-specific and unverified |
| Stream Deck automation | Validated | Not applicable | Unverified |

Docker Engine routing is checked separately on a GitHub-hosted Ubuntu 24.04
x86_64 runner. That evidence proves default-bridge access to a host-owned
metadata address; it does not expand the supported Linux installation host to
x86_64. Podman and Kubernetes remain unverified.

The support boundary was established by the initial supported-host releases
and retained through the current patch line. Release-specific changes and
validation are recorded in the [changelog](CHANGELOG.md). Other versions,
architectures, distributions, and runtimes may work but are not part of the
support claim.

## Requirements

For a supported host configuration:

- Apple Silicon macOS 26 with `launchd`; or
- Ubuntu 24.04 LTS ARM64 with systemd.

Both platforms require:

- Bash 3.2 or newer;
- `aws-runas` 3.9.0;
- `curl`;
- `unzip` when bootstrapping `aws-runas`; and
- administrator access during native service installation.

Linux additionally requires `ip`, `systemctl`, `loginctl`, `sudo`, a running
system systemd manager, and a working systemd user manager. The installer
finds `systemd-socket-proxyd` in `PATH` or standard systemd private executable
directories such as Ubuntu's `/usr/lib/systemd`.

No terminal multiplexer is required.

## Choose an installation path

| Situation | Recommended path |
| --- | --- |
| Supported Apple Silicon macOS | [Homebrew](docs/homebrew.md) |
| Supported Ubuntu ARM64 | [Pinned direct release](docs/direct-install.md) |
| Reviewing or developing the source | Run `./install.sh` from a reviewed checkout |
| `aws-runas` is missing | Let Homebrew setup bootstrap it, or run the release's `bootstrap.sh` before a direct/source install |

`bootstrap.sh` installs the upstream dependency; it is not another way to
install `aws-metadata-agent`.

## Quick start

The complete walkthrough, expected output, profile model, state lifecycle, and
verification cautions are in [Getting started](docs/getting-started.md). The
commands below are the supported golden paths.

### macOS with Homebrew

Review the [tap repository](https://github.com/so1omon563/homebrew-aws-metadata-agent),
then install the unprivileged package and run the separate privileged setup:

```sh
brew trust --tap so1omon563/aws-metadata-agent
brew tap so1omon563/aws-metadata-agent
brew install aws-metadata-agent
aws-metadata setup
```

`brew install` does not use `sudo`, install `aws-runas`, change networking, or
load services. `aws-metadata setup` conditionally bootstraps `aws-runas`, then
requests administrator access for the root-owned service payload, link-local
address, and launchd services. The broker still runs as the installing user.

See [Homebrew installation](docs/homebrew.md) for the tap trust lifecycle,
what to inspect, browser App Management permission, recovery, upgrade,
rollback, and uninstall.

### Ubuntu ARM64 from a pinned release

Pin the current documented release, verify the project-uploaded archive, and
inspect both scripts before execution:

```bash
version=0.3.0
archive="aws-metadata-agent-v${version}.tar.gz"
checksum="${archive}.sha256"
release_url="https://github.com/so1omon563/aws-metadata-agent/releases/download/v${version}"

curl --proto '=https' --tlsv1.2 --fail --location --show-error \
  --output "$archive" "$release_url/$archive"
curl --proto '=https' --tlsv1.2 --fail --location --show-error \
  --output "$checksum" "$release_url/$checksum"
sha256sum -c "$checksum"
tar -xzf "$archive"
cd "aws-metadata-agent-${version}"
less bootstrap.sh install.sh

if ! command -v aws-runas >/dev/null 2>&1 && \
   [[ ! -x "$HOME/.local/bin/aws-runas" ]]; then
  ./bootstrap.sh
fi
./install.sh
```

The direct installer does not bootstrap `aws-runas` automatically. It does
search both `PATH` and `~/.local/bin`, so no shell restart is required between
bootstrap and installation. See [Direct release installation](docs/direct-install.md)
for prerequisites, the inspect-first helper, checksum and archive guarantees,
and the prominently warned optional piped form.

### Configure, select, and verify

After either installation path, configure or confirm one user-owned upstream
profile. Test it directly before involving the metadata service:

```sh
aws_runas=$(command -v aws-runas 2>/dev/null || \
  printf '%s\n' "$HOME/.local/bin/aws-runas")
test -x "$aws_runas"
"$aws_runas" -r example-nonprod /usr/bin/true
printf 'exit=%s\n' "$?"
```

An exit code of `0` confirms that upstream can obtain credentials. If the
profile is not configured yet, follow [Configure aws-runas](docs/aws-runas-configuration.md)
and the authoritative [upstream documentation](https://mmmorris1975.github.io/aws-runas/).

Verify the installed service before selecting a profile:

```sh
aws-metadata status
aws-metadata diagnose
```

A new or restarted broker should report that the metadata service is running
and no profile is selected. That is a healthy state. Select the upstream
profile and verify it is ready:

```sh
aws-metadata use example-nonprod
aws-metadata status
```

Finally, make one AWS identity request while excluding the common providers
that could mask whether the CLI reached metadata:

```sh
env \
  -u AWS_PROFILE \
  -u AWS_DEFAULT_PROFILE \
  -u AWS_ACCESS_KEY_ID \
  -u AWS_SECRET_ACCESS_KEY \
  -u AWS_SESSION_TOKEN \
  -u AWS_SECURITY_TOKEN \
  -u AWS_ROLE_ARN \
  -u AWS_WEB_IDENTITY_TOKEN_FILE \
  -u AWS_CONTAINER_CREDENTIALS_FULL_URI \
  -u AWS_CONTAINER_CREDENTIALS_RELATIVE_URI \
  -u AWS_EC2_METADATA_SERVICE_ENDPOINT \
  AWS_CONFIG_FILE=/dev/null \
  AWS_SHARED_CREDENTIALS_FILE=/dev/null \
  AWS_EC2_METADATA_DISABLED=false \
  aws sts get-caller-identity --region us-east-1
```

This command makes an AWS STS request and prints identity information, not
credentials. Confirm the expected account and role locally; do not paste real
identity output into issues or logs. AWS tools use ordered credential provider
chains, so a plain successful `aws sts get-caller-identity` does not by itself
prove that metadata supplied the credentials.

## Documentation

Start with the [documentation index](docs/README.md).

| Goal | Guide |
| --- | --- |
| Complete first installation and verification | [Getting started](docs/getting-started.md) |
| Configure an upstream profile | [Configure aws-runas](docs/aws-runas-configuration.md) |
| Understand each command | [CLI reference](docs/cli-reference.md) |
| Connect AWS CLI, VS Code, SDKs, containers, or automation | [Consumer recipes](docs/consumers.md) |
| Diagnose installation or authentication failures | [Troubleshooting](docs/troubleshooting.md) |
| Understand processes, files, forwarding, IMDS compatibility, and lifecycle | [Architecture](docs/architecture.md) |
| Evaluate credential exposure and privilege boundaries | [Security model](docs/security.md) |
| Upgrade, roll back, or uninstall | [Upgrades and rollback](docs/upgrades.md) |
| Develop or release the project | [Contributing](CONTRIBUTING.md) and [Release process](docs/releasing.md) |

## Architecture summary

```text
Application / AWS SDK / AWS CLI
              |
              v
      169.254.169.254:80
              |
              v
  root-owned forwarding layer
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

The service never executes `aws-runas` from a user-writable directory. Setup
copies the selected executable into a root-owned `libexec` directory, while
the broker executes with the developer's uid so browser and credential-cache
state remain user-owned. Privileged components know only the link-local and
loopback endpoints; they do not read AWS configuration or credentials.

The endpoint is a credential-focused subset of EC2 instance metadata supplied
by upstream `aws-runas`, not a complete emulation of every EC2 metadata path.
Upstream supports IMDSv1 and enough of IMDSv2 for credential consumers, but
does not implement all of IMDSv2's EC2 security properties. See
[Architecture](docs/architecture.md#protocol-compatibility) and the official
[Metadata Credential Service](https://mmmorris1975.github.io/aws-runas/metadata_credentials.html)
documentation before assuming compatibility with a specific application.

## Maintenance

Identify the installed release with:

```sh
aws-metadata version
```

For Homebrew, remove privileged service state before the formula:

```sh
aws-metadata uninstall
brew uninstall aws-metadata-agent
```

For a direct or source installation, use `./uninstall.sh` from the matching
release. Uninstall removes project-owned services, executables, networking,
and configuration but preserves user-owned AWS profiles, browser state, and
`aws-runas` caches. See [Upgrades and rollback](docs/upgrades.md) for complete
method-specific procedures.

Report suspected vulnerabilities privately as described in
[SECURITY.md](SECURITY.md).

## Development

Run the credential-free checks with:

```sh
make test
```

The CLI tests use a fake `curl` executable and do not contact AWS or the local
metadata address. Development, documentation, sanitization, and pull-request
guidance lives in [CONTRIBUTING.md](CONTRIBUTING.md); release automation lives
in [docs/releasing.md](docs/releasing.md).

## License

The original project code is available under the [MIT License](LICENSE).
Third-party attribution for the separately downloaded `aws-runas` dependency
is recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

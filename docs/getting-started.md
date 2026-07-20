# Getting started

This guide takes a supported-platform user from an uninstalled host to an AWS
identity obtained through the standard EC2 metadata credential provider.

## Before you begin

Confirm that the product model fits:

- one upstream `aws-runas` profile is exposed globally at a time;
- every reachable local consumer receives the currently active profile;
- profile selection is unauthenticated on the local metadata HTTP interface;
- the active selection does not survive a broker restart or reboot; and
- any process or container that can reach `169.254.169.254` may be able to
  obtain credentials for the active profile.

This is intended for a trusted developer workstation, not mutually untrusted
workloads or concurrent per-application identities. Read the
[security model](security.md) if either boundary is uncertain.

## Understand the three profiles

```text
upstream profile       example-nonprod in ~/.aws/config
                              |
active agent profile  selected globally by aws-metadata use
                              |
consumer profile       local-metadata, only when a tool requires a name
```

The upstream profile defines authentication and role assumption. The active
agent profile is transient broker state. The optional consumer profile does
not identify or lock a role; it tells a profile-oriented application to read
whichever credentials the agent currently exposes.

## 1. Install the supported host path

### Apple Silicon macOS 26

Review and trust the third-party tap, install its unprivileged payload, then
run the separate native-service setup:

```sh
brew trust --tap so1omon563/aws-metadata-agent
brew tap so1omon563/aws-metadata-agent
brew install aws-metadata-agent
aws-metadata setup
```

If no executable is found in `PATH` or `~/.local/bin`, setup downloads the
pinned upstream `aws-runas` release after verifying its published checksum.
Setup then requests administrator access for the service payload, link-local
address, and launchd services. See [Homebrew installation](homebrew.md) for
trust review, exact privilege boundaries, App Management, and recovery.

### Ubuntu 24.04 LTS ARM64

Use the pinned archive, checksum, bootstrap, and installer sequence in
[Direct release installation](direct-install.md). The essential dependency
ordering after extracting and inspecting the verified release is:

```bash
if ! command -v aws-runas >/dev/null 2>&1 && \
   [[ ! -x "$HOME/.local/bin/aws-runas" ]]; then
  ./bootstrap.sh
fi
./install.sh
```

The direct installer does not run the bootstrap automatically. It does search
`~/.local/bin`, so no shell restart is required between those two commands.

## 2. Confirm one upstream profile

If the AWS CLI is installed, list the names in the standard AWS configuration:

```sh
aws configure list-profiles
```

Choose a real `aws-runas` role profile, not a consumer compatibility profile.
If no suitable profile exists, follow [Configure aws-runas](aws-runas-configuration.md)
and the authoritative [upstream documentation](https://mmmorris1975.github.io/aws-runas/).

Find the upstream executable. A Homebrew setup that just bootstrapped it may
have placed it in `~/.local/bin` before that directory is in the current
shell's `PATH`:

```bash
if command -v aws-runas >/dev/null 2>&1; then
  aws_runas=$(command -v aws-runas)
else
  aws_runas="$HOME/.local/bin/aws-runas"
fi
test -x "$aws_runas"
```

Test and refresh the upstream profile without involving the metadata service:

```sh
"$aws_runas" -r example-nonprod /usr/bin/true
printf 'exit=%s\n' "$?"
```

Exit `0` means upstream obtained credentials. Browser-backed profiles may open
an authentication session. A nonzero exit belongs to the upstream profile,
identity-provider, or AWS STS boundary; fix it before diagnosing the agent.

The bootstrap destination is immediately usable by the installer. To make the
command available in later interactive shells, add `~/.local/bin` to the login
shell's `PATH` or use the reviewed `bootstrap.sh --configure-shell` flow from
the extracted release.

## 3. Verify native service state

Run:

```sh
aws-metadata status
aws-metadata diagnose
```

Before the first selection, expected status is:

```text
AWS metadata service is running at http://169.254.169.254.
No profile is selected.
```

No profile is a healthy startup state. `diagnose` separately checks the
configured endpoint, link-local address, and user broker service. It also
looks for `aws-runas` in the current `PATH`; if setup used
`~/.local/bin/aws-runas` and that directory is not yet in `PATH`, this one
diagnostic line can report `not found` even though the installed root-owned
broker copy is running. Use the path test above and configure the shell path.

Do not use a credential endpoint or `status --json` from a real active work
profile as shareable diagnostic output. Profile objects and names may expose
organization-specific identifiers.

## 4. Select the active agent profile

For a human-operated selection, use:

```sh
aws-metadata use example-nonprod
```

`use` opens the browser when needed and waits up to 300 seconds by default. A
successful result is:

```text
AWS metadata profile set to example-nonprod.
```

Then confirm only local state:

```sh
aws-metadata status
```

If an expired password, recovery step, or MFA interaction may take longer:

```sh
aws-metadata use example-nonprod --wait 600
```

For unattended automation, use `aws-metadata profile`; it does not open a
browser or wait unless explicitly requested. See the [CLI reference](cli-reference.md).

## 5. Prove an AWS client uses metadata

AWS tools stop at the first valid provider in their credential chain.
Environment credentials, an explicit profile, SSO, shared credentials,
`credential_process`, web identity, or container credentials can all mask a
working or broken metadata path.

The following command excludes the common competing providers, leaves IMDS
enabled, and makes one AWS STS identity request:

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

The response should identify the account and assumed role exposed by
`example-nonprod`. The command prints identity information rather than
credentials, but that identity can still be organization-sensitive. Verify it
locally and do not paste real output into a public issue.

The AWS CLI documents EC2 metadata after environment, shared-file, process,
SSO, web-identity, and container providers in its
[credential precedence](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html#configure-precedence).
Provider order varies among SDKs, so verify the specific application before
claiming support.

## 6. Connect applications

- Applications using the default AWS credential chain should need no profile
  name or custom endpoint.
- The AWS Toolkit for Visual Studio Code and other profile-oriented tools may
  use the optional `local-metadata` compatibility profile documented in
  [Consumer recipes](consumers.md#profile-oriented-consumers).
- Containers use the standard address but have runtime-specific routing; see
  [Container runtime validation](container-runtimes.md).
- GUI automation should call the package-managed CLI directly; see
  [Stream Deck integration](stream-deck.md).

## State lifecycle

| State | Survives service restart? | Survives reboot? | Removed by agent uninstall? |
| --- | --- | --- | --- |
| Installed services and executables | Yes | Yes | Yes |
| Link-local forwarding | Restored by native service | Restored by native service | Yes |
| User-owned AWS profile definitions | Yes | Yes | No |
| Upstream role credential cache | Usually, subject to expiration | Usually, subject to expiration | No |
| Upstream browser session state | Provider-controlled | Provider-controlled | No |
| Active agent profile | No | No | Not applicable |

Temporary AWS credentials are refreshed by the upstream broker when a consumer
requests them. A cached browser session may allow that refresh to complete
silently; an expired or invalid identity-provider session may require a new
browser login. The caller can block while interactive authentication completes.
The browser session and STS credential exchange are separate boundaries, so a
completed login does not by itself prove that AWS issued fresh credentials.

`aws-metadata open` and `aws-metadata refresh` both open the upstream browser
interface. They do not directly force a refresh from the CLI. Use the browser's
**Refresh Now** control or reselect the profile when interactive renewal is
needed.

## Next steps

- [CLI reference](cli-reference.md)
- [Consumer recipes](consumers.md)
- [Troubleshooting](troubleshooting.md)
- [Security model](security.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

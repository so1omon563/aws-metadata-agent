# Getting started

This guide takes a supported-platform user from an uninstalled host to one AWS
client using temporary credentials through the standard EC2 metadata provider.

The completed path is:

```text
install -> confirm upstream profile -> check service -> select profile -> verify
```

If the profile roles are unfamiliar, read [Concepts](concepts.md) first.

## Before you begin

You need:

- Apple Silicon macOS 26 or Ubuntu 24.04 LTS ARM64;
- a trusted, single-developer workstation;
- administrator access for native service setup; and
- an `aws-runas` profile, or enough information to configure one.

The endpoint exposes one globally active profile to every reachable consumer.
Read the [security model](security.md) before continuing if local applications
or containers should not share one AWS identity.

## 1. Install

### Apple Silicon macOS 26

Review and trust the third-party tap, install its unprivileged payload, then
run the separate native-service setup:

```sh
brew trust --tap so1omon563/aws-metadata-agent
brew tap so1omon563/aws-metadata-agent
brew install aws-metadata-agent
aws-metadata setup
```

If `aws-runas` is absent from `PATH` and `~/.local/bin`, setup downloads the
pinned upstream release and verifies its published checksum. It then requests
administrator access for the native service payload and networking. The
credential broker still runs as the installing user.

Use [Homebrew installation](homebrew.md) for tap inspection, exact setup
behavior, conditional App Management permission, recovery, and uninstall.

### Ubuntu 24.04 LTS ARM64

Follow [Direct release installation](direct-install.md) to choose an explicit
stable release, verify its checksum, inspect its scripts, and install it.

The direct installer does not bootstrap `aws-runas` automatically. After
extracting the verified release, run the dependency step only when needed:

```bash
if ! command -v aws-runas >/dev/null 2>&1 && \
   [[ ! -x "$HOME/.local/bin/aws-runas" ]]; then
  ./bootstrap.sh
fi
./install.sh
```

The installer searches `~/.local/bin`, so no shell restart is required between
those commands.

## 2. Confirm one upstream profile

If the AWS CLI is installed, list the names in the standard AWS configuration:

```sh
aws configure list-profiles
```

Choose a real `aws-runas` role profile, such as `example-nonprod`, rather than
a consumer compatibility profile. If no suitable profile exists, follow
[Configure aws-runas](aws-runas-configuration.md) and the authoritative
[upstream documentation](https://mmmorris1975.github.io/aws-runas/).

Find the executable and test that profile directly:

```bash
if command -v aws-runas >/dev/null 2>&1; then
  aws_runas=$(command -v aws-runas)
else
  aws_runas="$HOME/.local/bin/aws-runas"
fi
test -x "$aws_runas"
"$aws_runas" -r example-nonprod /usr/bin/true
printf 'exit=%s\n' "$?"
```

Exit `0` means upstream obtained credentials. Browser-backed profiles may open
an authentication session. Fix a nonzero upstream result before involving the
metadata service.

If setup placed the executable in `~/.local/bin`, use the reviewed
`bootstrap.sh --configure-shell` flow or add that directory to the login
shell's `PATH` for future terminals.

## 3. Check the service

Run:

```sh
aws-metadata version
aws-metadata status
aws-metadata diagnose
```

Before the first selection, expected status is:

```text
AWS metadata service is running at http://169.254.169.254.
No profile is selected.
```

No profile is a healthy startup state. If `diagnose` reports `aws-runas: not
found` after setup bootstrapped `~/.local/bin/aws-runas`, configure the shell
path as described above; the installed root-owned broker copy can still be
running correctly.

## 4. Select the profile

Use the human-oriented command:

```sh
aws-metadata use example-nonprod
```

It opens a browser when authentication is required and waits up to 300 seconds
by default. Success reports:

```text
AWS metadata profile set to example-nonprod.
```

Use `--wait 600` when password recovery or MFA may take longer. For unattended
automation, `aws-metadata profile` does not open a browser or wait unless the
caller opts in. See the [CLI reference](cli-reference.md).

## 5. Verify and finish

Complete the [verification checklist](verification.md). It proves, in order:

1. the package and native service;
2. the upstream profile;
3. agent profile selection;
4. provider-isolated AWS credentials through metadata; and
5. any optional application or container boundary you actually need.

When those checks pass, the happy path is complete. Applications using the
default AWS credential chain need no project-specific wrapper or endpoint.

When work with the active identity is complete, return the broker to healthy
no-profile state:

```sh
aws-metadata clear
```

This prevents new metadata requests from retrieving that active identity. It
does not revoke credentials an application already fetched; see the
[security model](security.md#profile-switching-is-global-and-unauthenticated).

## Connect another application

- Use [Consumer recipes](consumers.md) for AWS CLI, SDK, VS Code, coding-agent,
  container, and GUI patterns.
- Use [Container runtime validation](container-runtimes.md) before assuming a
  container can route to the host metadata address.
- Use [Stream Deck integration](stream-deck.md) for validated macOS automation.
- Start from the visible symptom in [Troubleshooting](troubleshooting.md) if a
  check fails.

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

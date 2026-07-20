# Direct release installation

Homebrew is the primary installation path on supported macOS. Direct release
installation is intended primarily for supported Ubuntu ARM64 and as a
secondary inspect-first macOS option. It does not configure AWS profiles or
credentials.

## Prerequisites

Supported Ubuntu installation requires ARM64 Ubuntu 24.04 LTS with a system
systemd manager, a working systemd user manager, and:

```sh
command -v bash curl unzip ip systemctl loginctl sudo
command -v systemd-socket-proxyd || \
  test -x /usr/lib/systemd/systemd-socket-proxyd || \
  test -x /lib/systemd/systemd-socket-proxyd
uname -m
```

The validated architecture reports `aarch64`. The installer searches systemd's
private executable directories, so `systemd-socket-proxyd` does not need to be
in `PATH`. Other Linux distributions and architectures may work but are not
part of the support claim.

Both supported hosts require administrator access during service installation.
`unzip` is needed only when bootstrapping the upstream dependency.

## Inspect, verify, bootstrap, and install

Pin the documented release instead of resolving a mutable `latest` reference:

```sh
version=0.2.2
archive="aws-metadata-agent-v${version}.tar.gz"
checksum="${archive}.sha256"
release_url="https://github.com/so1omon563/aws-metadata-agent/releases/download/v${version}"

curl --proto '=https' --tlsv1.2 --fail --location --show-error \
  --output "$archive" "$release_url/$archive"
curl --proto '=https' --tlsv1.2 --fail --location --show-error \
  --output "$checksum" "$release_url/$checksum"
```

Read the matching
[release notes](https://github.com/so1omon563/aws-metadata-agent/releases)
before installing. Verify the published SHA-256 before extracting anything:

```sh
# macOS
shasum -a 256 -c "$checksum"

# Linux
sha256sum -c "$checksum"
```

Extract the verified archive and inspect the dependency bootstrap, installer,
and uninstaller:

```sh
tar -xzf "$archive"
cd "aws-metadata-agent-${version}"
less bootstrap.sh install.sh uninstall.sh
```

The direct installer does not run `bootstrap.sh` automatically. Insert the
dependency step before installation only when neither supported location
contains an executable:

```bash
if ! command -v aws-runas >/dev/null 2>&1 && \
   [[ ! -x "$HOME/.local/bin/aws-runas" ]]; then
  ./bootstrap.sh
fi
./install.sh
```

`bootstrap.sh` downloads the pinned, unmodified dependency only from the
official `mmmorris1975/aws-runas` release and verifies its published checksum.
It installs to `~/.local/bin` by default. `install.sh` checks that location
directly, so no shell restart is required between bootstrap and installation.
To use a different existing executable:

```sh
./install.sh --aws-runas /absolute/path/to/aws-runas
```

The installer requests administrator access for the root-owned service
payload, link-local address, and native service definitions. The credential
broker still runs as the installing user; only networking runs with elevated
ownership. The installer never creates or selects an AWS profile.

## Verify installation state

Successful installation reports the installing user, version, privilege
boundary, status command, and browser URL. Verify:

```sh
aws-metadata version
aws-metadata status
aws-metadata diagnose
```

Expected first status is a running endpoint with no selected profile. That is
healthy. Continue with
[Getting started](getting-started.md#2-confirm-one-upstream-profile) to test an
upstream profile, select it, and prove an AWS client uses metadata.

## Auditable helper

`install-release.sh` automates the same pinned archive download, checksum
verification, archive validation, and installer handoff. It does not bootstrap
`aws-runas`, so use it when the dependency is already present or pass an
explicit installer path.

Download and inspect the helper before running it:

```sh
curl --proto '=https' --tlsv1.2 --fail --location --show-error \
  --output install-release.sh \
  https://raw.githubusercontent.com/so1omon563/aws-metadata-agent/main/install-release.sh
less install-release.sh
sh ./install-release.sh --version 0.2.2
```

Installer options follow a literal `--`:

```sh
sh ./install-release.sh --version 0.2.2 -- \
  --aws-runas "$HOME/.local/bin/aws-runas"
```

The helper refuses missing or nonsemantic versions, unsupported platforms,
failed downloads, malformed or mismatched checksums, unexpected archive paths,
and an embedded `VERSION` that differs from the requested tag. Temporary files
are removed on success and failure.

## Optional piped form

**YOU SHOULD NEVER BLINDLY RUN THIS. Inspect the script before executing it.**

After inspecting the current helper, the equivalent piped convenience command
is:

```sh
curl --proto '=https' --tlsv1.2 --fail --location --show-error --silent \
  https://raw.githubusercontent.com/so1omon563/aws-metadata-agent/main/install-release.sh \
  | sh -s -- --version 0.2.2
```

The helper URL on `main` is mutable. The versioned archive it downloads is a
project-uploaded release asset and must match that release's published
SHA-256. The helper does not use GitHub-generated source archives because their
bytes are not guaranteed stable over time.

## Recover from partial installation

Preserve the exact error and rerun the same reviewed release installer:

```sh
./install.sh
aws-metadata diagnose
```

Same-version reinstall is supported. If clean removal is necessary, run the
matching `./uninstall.sh` before trying another method. Do not manually remove
individual systemd/launchd definitions or link-local state first. See
[Troubleshooting](troubleshooting.md).

## Upgrade, rollback, and uninstall

Upgrade by rerunning the inspected helper with the desired newer version or by
extracting and installing that verified release. Roll back only after reviewing
the target release notes for schema or installed-layout compatibility. If they
are incompatible, run the current matching uninstaller first.

From an extracted release directory:

```sh
./uninstall.sh
```

Uninstall removes project-owned services, executables, networking, and
configuration. It preserves AWS profiles, browser-authentication state, and
other user-owned AWS state. See [Upgrades and rollback](upgrades.md) for the
complete method-specific policy.

## Related documentation

- [Getting started](getting-started.md)
- [Configure aws-runas](aws-runas-configuration.md)
- [Troubleshooting](troubleshooting.md)
- [Upgrades and rollback](upgrades.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

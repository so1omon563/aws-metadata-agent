# Direct release installation

Homebrew is the primary installation path on supported macOS hosts. The direct
release installer is intended primarily for supported Linux hosts and as a
secondary macOS option. It does not configure AWS profiles or credentials.

## Inspect, verify, and install

Pin the release instead of resolving a mutable `latest` reference:

```sh
version=0.2.0
archive="aws-metadata-agent-v${version}.tar.gz"
checksum="${archive}.sha256"

curl --proto '=https' --tlsv1.2 --fail --location --show-error \
  --output "$archive" \
  "https://github.com/so1omon563/aws-metadata-agent/archive/refs/tags/v${version}.tar.gz"
curl --proto '=https' --tlsv1.2 --fail --location --show-error \
  --output "$checksum" \
  "https://github.com/so1omon563/aws-metadata-agent/releases/download/v${version}/${checksum}"
```

Verify the published SHA-256 before extracting anything. Use the command for
your host:

```sh
# macOS
shasum -a 256 -c "$checksum"

# Linux
sha256sum -c "$checksum"
```

Extract the verified archive, inspect the installer, and only then execute it:

```sh
tar -xzf "$archive"
cd "aws-metadata-agent-${version}"
less install.sh
./install.sh
```

The installer may request administrator access for the link-local address and
native services. The credential broker still runs as the installing user; only
network forwarding runs as root. The installer never creates or selects an AWS
profile.

If `aws-runas` is not already installed, use the project's existing
checksum-verified `bootstrap.sh`. It downloads only from the official upstream
`mmmorris1975/aws-runas` release and does not bundle or mirror that dependency.

## Auditable helper

`install-release.sh` automates the same pinned archive download, checksum
verification, archive validation, and handoff. Download and inspect the helper
before running it:

```sh
curl --proto '=https' --tlsv1.2 --fail --location --show-error \
  --output install-release.sh \
  https://raw.githubusercontent.com/so1omon563/aws-metadata-agent/main/install-release.sh
less install-release.sh
sh ./install-release.sh --version 0.2.0
```

Installer options must follow a literal `--`, for example:

```sh
sh ./install-release.sh --version 0.2.0 -- \
  --aws-runas "$HOME/.local/bin/aws-runas"
```

The helper refuses missing or non-semantic versions, unsupported platforms,
failed downloads, malformed or mismatched checksums, unexpected archive paths,
and a `VERSION` that differs from the requested tag. Temporary files are
removed on success and failure.

**YOU SHOULD NEVER BLINDLY RUN THIS. Inspect the script before executing it.**

After inspecting the current helper, the equivalent piped convenience command
is:

```sh
curl --proto '=https' --tlsv1.2 --fail --location --show-error --silent \
  https://raw.githubusercontent.com/so1omon563/aws-metadata-agent/main/install-release.sh \
  | sh -s -- --version 0.2.0
```

The helper URL on `main` is mutable; the release archive it downloads is an
explicit immutable tag and must match that release's published SHA-256.

## Upgrade, rollback, and uninstall

Upgrade by rerunning the helper with the desired newer version. Roll back by
rerunning it with an earlier supported version whose configuration schema is
compatible. If release notes describe an incompatible schema or installed
layout, uninstall the current release first and then install the older one.

From an extracted release directory, uninstall with:

```sh
./uninstall.sh
```

The uninstall removes project-owned services, executables, and configuration.
It leaves AWS profiles, browser-authentication state, and other user-owned AWS
configuration untouched. See [upgrades.md](upgrades.md) for the full versioning
and rollback policy.

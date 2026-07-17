# Homebrew installation

Homebrew is the primary installation path for supported macOS hosts. The
formula installs a versioned, unprivileged project payload. Service setup is a
separate, explicit command because it needs administrator access to configure
the link-local address and launchd services.

## Install and set up

The tap is third-party executable code. Review it before trusting it, then
install the unprivileged package payload:

```sh
brew trust --tap so1omon563/aws-metadata-agent
brew tap so1omon563/aws-metadata-agent
brew install aws-metadata-agent
```

`brew install` places the versioned package payload under the Homebrew prefix.
The trust, tap, and install steps do not invoke `sudo`, change network state,
install `aws-runas`, or load services. Complete the separate service setup
explicitly:

```sh
aws-metadata setup
```

Before requesting administrator access, setup looks for `aws-runas` in `PATH`
and `~/.local/bin`. If it is absent and no `--aws-runas PATH` is supplied,
setup invokes the packaged checksum-verified bootstrap, which downloads the
pinned, unmodified binary directly from the official upstream release into
`~/.local/bin`. The formula does not bundle or mirror `aws-runas`. If an
executable is already available, setup skips the bootstrap.

Setup then runs the same reviewed installer used by source releases. The
installer requests `sudo` for the root-owned service payload, link-local
address, and launchd services; the credential broker continues to run as the
installing user. To use a specific existing binary, run:

```sh
aws-metadata setup --aws-runas /absolute/path/to/aws-runas
```

The supported Homebrew host boundary is Apple Silicon macOS 26. Other macOS
versions and architectures are not part of the current support claim.

## Upgrade

Upgrade the Homebrew payload, then explicitly refresh the root-owned service
copy and definitions:

```sh
brew update
brew upgrade aws-metadata-agent
aws-metadata setup
aws-metadata version
aws-metadata status
```

Homebrew owns the command in its prefix. Setup copies only the service payload
to root-owned absolute paths and records that command removal belongs to the
package manager.

## Uninstall

Remove the privileged service state before removing the Homebrew payload:

```sh
aws-metadata uninstall
brew uninstall aws-metadata-agent
```

If Homebrew was removed first, reinstall the formula and run
`aws-metadata uninstall`, or use `uninstall.sh` from the matching tagged source
release. User-owned AWS configuration, profiles, and `aws-runas` caches are
preserved.

## Rollback

The tap distributes the current supported release rather than retaining every
historical formula. To roll back, remove the service state and Homebrew payload
as above, check out the desired earlier project tag, and run that release's
source installer. Review the release notes first for configuration-schema or
path incompatibilities.

## Formula contract

The formula installs the release tree under its private `libexec`, verifies the
immutable tagged source archive checksum, and provides an `aws-metadata`
wrapper with these environment values:

- `AWS_METADATA_PACKAGE_ROOT` points to the packaged release tree.
- `AWS_METADATA_VERSION_FILE` points to that tree's `VERSION` file.
- `AWS_METADATA_PACKAGE_CLI` is the absolute path to the package-managed
  wrapper. Setup uses it to remove a distinct CLI left by an earlier source
  installation without deleting the package manager's command.

Formula tests must verify `aws-metadata version` and
`aws-metadata setup --help` without administrator access, service changes,
network downloads, or AWS configuration.

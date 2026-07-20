# Upgrades, rollback, and uninstall

This document covers end-user maintenance. Maintainer tagging, GitHub Release,
and Homebrew publication automation lives in [Release process](releasing.md).

## Version and compatibility policy

`VERSION` is the source of truth for the project version, and the matching Git
tag adds a `v` prefix. `aws-metadata version` reports the release copied into
the root-owned service directory.

Only tagged releases are supported installation inputs. The project follows
semantic versioning. While the project is on `0.x`, a minor release may contain
a breaking change, but its release notes must identify the change and provide
a migration path. After `1.0.0`, breaking changes require a major release.

Before upgrading or rolling back:

1. Record the installed method and version:

   ```sh
   command -v aws-metadata
   aws-metadata version
   ```

2. Read the target [release notes](https://github.com/so1omon563/aws-metadata-agent/releases)
   and [changelog](../CHANGELOG.md), especially configuration-schema, installed
   path, and migration notes.
3. Keep the current installer or package available until the target is
   verified.

The root-owned configuration records agent and schema versions. An installer
rejects a newer unsupported schema rather than silently rewriting it. A
release that removes, renames, or reinterprets installer state must increment
the schema and include a tested migration.

Upgrades preserve user-owned `~/.aws` configuration, upstream credential and
browser caches, and unrelated personal scripts. They do not create, select,
migrate, or delete an AWS profile.

## Homebrew upgrade

Homebrew owns the package command; native service setup owns the separate
root-owned copy and definitions. Upgrade both layers explicitly:

```sh
brew update
brew upgrade aws-metadata-agent
aws-metadata setup
aws-metadata version
aws-metadata status
aws-metadata diagnose
```

`aws-metadata setup` reruns the reviewed installer and refreshes the service
payload from the package. Reinstalling the same version is supported.

## Direct release upgrade

Download and inspect the current `install-release.sh`, then rerun it with an
explicit target version:

```sh
less install-release.sh
sh ./install-release.sh --version TARGET_VERSION
aws-metadata version
aws-metadata status
aws-metadata diagnose
```

The helper verifies the target release archive and checksum before invoking
its installer. It does not bootstrap `aws-runas`; retain the existing upstream
binary or pass an explicit installer path after a literal `--`.

See [Direct release installation](direct-install.md) for the full supply-chain
and argument contract.

## Source installation upgrade

Use an exact release tag and inspect the diff or release notes before rerunning
the installer:

```sh
git fetch --tags
git checkout vTARGET_VERSION
./install.sh
aws-metadata version
aws-metadata status
aws-metadata diagnose
```

The installer replaces the CLI when it owns it, service executables, copied
`aws-runas`, service definitions, and root-owned configuration in place, then
reloads or restarts the native services.

## Confirm the upgraded identity path

Healthy service state alone does not prove that a consumer is using metadata.
After reselecting an upstream profile, repeat the provider-isolated identity
verification from [Getting started](getting-started.md#5-prove-an-aws-client-uses-metadata).

The active profile is process state and is normally cleared when setup restarts
the broker. Reselect it after an upgrade:

```sh
aws-metadata use example-nonprod
```

## Recover from a failed upgrade

1. Preserve the exact error and run `aws-metadata diagnose`.
2. Rerun the same package setup or matching release installer. Same-version
   reinstall is supported and repairs service payloads and definitions.
3. If the endpoint answers but authentication fails, use
   `aws-metadata errors`; do not mistake a broker error for a failed install.
4. If clean removal is necessary, use the current method's uninstaller before
   attempting a different installation method.

Do not manually remove isolated root-owned files or service definitions unless
the matching uninstaller is unavailable and the complete layout has been
reviewed. Manual partial cleanup can leave networking, service-manager, or
package ownership inconsistent.

## Rollback

There is no automatic rollback. Confirm target compatibility in the release
notes before changing versions.

### Homebrew-managed installation

The tap publishes the current supported formula rather than a catalog of every
historical version. A rollback therefore changes ownership temporarily from
Homebrew to a tagged direct/source installation:

```sh
aws-metadata uninstall
brew uninstall aws-metadata-agent
```

Then install the reviewed older tag with its direct-release helper or source
installer. Keep the tap installed if you intend to return to Homebrew later.

To return to Homebrew, run the older release's `./uninstall.sh`, then:

```sh
brew install aws-metadata-agent
aws-metadata setup
```

Do not leave both source-owned `/usr/local/bin/aws-metadata` and a
package-managed command as competing installations. Setup contains migration
handling for the known legacy source path, but installation ownership should
remain explicit.

### Direct or source installation

If the earlier release uses a compatible schema and layout, install that exact
tag with its verified helper or rerun its source installer. If the release
notes describe incompatibility, run the current release's uninstaller first,
then install the older version from clean state.

## Uninstall

### Homebrew

Remove service state before the package payload:

```sh
aws-metadata uninstall
brew uninstall aws-metadata-agent
```

If Homebrew was removed first, reinstall the formula and run
`aws-metadata uninstall`, or obtain `uninstall.sh` from the matching tagged
release.

### Direct or source

From the matching release directory:

```sh
./uninstall.sh
```

Uninstall stops and removes the user broker and privileged forwarding,
project-owned executables, native definitions, link-local state, and root-owned
configuration. On Linux it restores the prior linger state when the project
originally enabled lingering.

User-owned AWS configuration, profile definitions, browser-authentication
state, upstream credential caches, and unrelated scripts are preserved.

## Related documentation

- [Homebrew installation](homebrew.md)
- [Direct release installation](direct-install.md)
- [Troubleshooting](troubleshooting.md)
- [Release process](releasing.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

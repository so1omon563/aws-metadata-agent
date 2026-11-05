# Upgrades, rollback, and uninstall

This document covers end-user maintenance. Maintainer tagging, GitHub Release,
and Homebrew publication automation lives in [Release process](releasing.md).

## Version and compatibility policy

`VERSION` is the source of truth for the project version, and the matching Git
tag adds a `v` prefix. Through Homebrew, `aws-metadata version` reports the
packaged release in either mode. Direct/source commands default to the release
copied into the root-owned service directory. This reads a file, not the
version of a running broker or auto-clear guard.

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

Installer configuration records agent and schema versions. It is user-owned
in user mode and root-owned in system mode. The system-mode installer
rejects a newer unsupported schema rather than silently rewriting it; user-mode
setup does not perform that schema-compatibility check. A
release that removes, renames, or reinterprets installer state must increment
the schema and include a tested migration.

Upgrades preserve user-owned `~/.aws` configuration, upstream credential and
browser caches, and unrelated personal scripts. User-mode setup owns only its
marked default process provider and refuses to replace another default
credential source; system mode does not edit AWS configuration.

## Homebrew upgrade

Homebrew owns the package command. User mode references Homebrew's stable
`opt` path, keeping its LaunchAgent and default `credential_process` paths
valid after a package upgrade:

```sh
brew update
brew upgrade aws-metadata-agent
aws-metadata version
```

### macOS user mode: running-process caveat

A stable path affects future process starts; it does not reload a guard that
is already running. `brew upgrade` can therefore install a new release while
the old auto-clear guard continues running. A new `aws-metadata version`, a
healthy endpoint, or successful `diagnose` output does not prove that the
guard uses the new code. Automatic guard reload remains an unresolved upgrade
issue; this documentation does not fix it.

The proposed maintenance workaround is to rerun explicit user-mode setup
after the package upgrade. The current installer unloads and bootstraps the
user LaunchAgent. It also migrates older versioned Cellar references to the
stable package path. This sequence has not yet been validated end-to-end for
an old-to-new Homebrew upgrade on native macOS, so it is not a verified fix
for the running-guard issue.

If using this workaround, plan for a broker interruption and loss of its
in-process active selection. Keep the Homebrew package installed, remain in
user mode, and reselect the intended upstream profile after setup:

```sh
aws-metadata setup --mode user
aws-metadata status
aws-metadata diagnose
aws-metadata use example-nonprod
```

Setup does not remove the saved auto-clear duration. Check it with
`aws-metadata auto-clear status`, then repeat
[provider-isolated verification](verification.md#4-metadata-credential-path).
Do not infer guard-version validation from these health checks alone.

### System mode

System mode copies a root-owned payload outside Homebrew, so refresh that layer
after every package upgrade:

```sh
aws-metadata setup --mode system
aws-metadata version
aws-metadata status
aws-metadata diagnose
```

Rerunning either explicit setup mode remains supported for repair or
reinstallation. For user mode, distinguish that installer behavior from the
native upgrade validation still needed above.

## Direct release upgrade

This is a system-mode path. It is not a replacement for user mode's stable
package-managed command. Download and inspect the current `install-release.sh`,
then rerun it with an explicit target version:

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

For a source-owned system-mode installation, use an exact release tag and
inspect the diff or release notes before rerunning
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
verification from [Verification](verification.md#4-metadata-credential-path).

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
4. Before clean removal, confirm that a compatible replacement is available
   for the same mode and that you can recover the current version. User-mode
   readers should keep the Homebrew package installed and review the
   [rollback limitation](#homebrew-managed-user-mode) before removing any
   working service or command.
5. If a supported ownership transition requires removal, use the current
   method's matching uninstaller before attempting the replacement method.

Do not manually remove isolated root-owned files or service definitions unless
the matching uninstaller is unavailable and the complete layout has been
reviewed. Manual partial cleanup can leave networking, service-manager, or
package ownership inconsistent.

## Rollback

There is no automatic rollback. Confirm target compatibility in the release
notes before changing versions.

### Homebrew-managed user mode

User mode requires a stable package-managed `aws-metadata` command. Removing
Homebrew's package and then using the direct/source system installer does not
provide an equivalent no-sudo rollback. Do not uninstall a working user-mode
service or package before confirming a compatible package-managed replacement
and a tested recovery path.

The tap publishes the current supported formula rather than a catalog of every
historical version. No package-preserving historical user-mode rollback
procedure has been validated and documented here. Until one has been tested on
macOS, keep the current package and its recovery information available; do not
substitute a source installation, elevate privileges, or silently switch to
system mode on a managed workstation.

A future rollback procedure must verify the historical package, stable command
and service paths, default process provider, restart behavior, version
reporting, and return to the current supported Homebrew package before it can
be recommended. For a broken setup on the current package, try the matching
`aws-metadata setup --mode user` repair described above instead of removing
the package first.

### Homebrew-managed system mode

The tap publishes the current supported formula rather than a catalog of every
historical version. If the reviewed older release supports your system-mode
host, schema, and layout, a rollback can temporarily change ownership from
Homebrew to that tagged direct/source installation. Have the verified target
installer and a recovery path available before removal:

```sh
aws-metadata uninstall --mode system
brew uninstall aws-metadata-agent
```

Then install the reviewed older tag with its direct-release helper or source
installer. Keep the tap installed if you intend to return to Homebrew later.

To return to Homebrew, run the older release's `./uninstall.sh`, then:

```sh
brew install aws-metadata-agent
aws-metadata setup --mode system
```

Do not leave both source-owned `/usr/local/bin/aws-metadata` and a
package-managed command as competing installations. Setup contains migration
handling for the known legacy source path, but installation ownership should
remain explicit.

### Direct or source system-mode installation

If the earlier release uses a compatible schema and layout, install that exact
tag with its verified helper or rerun its source installer. If the release
notes describe incompatibility, run the current release's uninstaller first,
then install the older version from clean state.

## Uninstall

### Homebrew

Remove the selected service state before the package payload:

```sh
aws-metadata uninstall --mode user
# or: aws-metadata uninstall --mode system
brew uninstall aws-metadata-agent
```

If Homebrew was removed first, reinstall the formula and run
the matching uninstall command, or obtain `uninstall.sh` from the matching
tagged release.

### Direct or source

From the matching release directory:

```sh
./uninstall.sh
```

Uninstall stops and removes the user broker and privileged forwarding,
project-owned executables, native definitions, link-local state, and root-owned
configuration. On Linux it restores the prior linger state when the project
originally enabled lingering.

User-mode removal stops its LaunchAgent and removes user-owned installer state
and only its marked default process provider. Unrelated AWS settings, profile
definitions, browser-authentication state, upstream credential caches, and
unrelated scripts are preserved in both modes.

## Related documentation

- [Homebrew installation](homebrew.md)
- [Direct release installation](direct-install.md)
- [Troubleshooting](troubleshooting.md)
- [Release process](releasing.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

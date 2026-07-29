# Homebrew installation

Homebrew is the primary installation path for supported macOS hosts. The
formula installs a versioned, unprivileged project payload. Service setup is a
separate explicit command. User mode remains unprivileged; system mode requests
administrator access to configure the link-local address and launchd services.

## Review and trust the tap

The tap is third-party executable code. Review the
[tap repository](https://github.com/so1omon563/homebrew-aws-metadata-agent)
before trusting it. At minimum, inspect:

- `Formula/aws-metadata-agent.rb` for the release URL, SHA-256, wrapper, and
  test contract;
- `README.md` for the package/setup boundary; and
- repository history and current protected pull requests for unexpected
  changes.

Record the explicit trust decision, tap the repository, and install:

```sh
brew trust --tap so1omon563/aws-metadata-agent
brew tap so1omon563/aws-metadata-agent
brew install aws-metadata-agent
```

`brew trust --tap` records the tap in Homebrew's user trust file. Homebrew uses
that allowlist when `HOMEBREW_REQUIRE_TAP_TRUST` is enabled; this project makes
the third-party trust decision explicit even when local policy does not
currently enforce it. The trust command does not clone the tap or execute its
formula.

If the installed Homebrew does not provide `brew trust`, update Homebrew and
confirm the command before following this supported path:

```sh
brew update
brew trust --help
```

Do not replace repository review with a blind tap/install command merely to
work around an older client.

## Choose and set up a service mode

`brew install` places the package under the Homebrew prefix. Trust, tap, and
install do not invoke `sudo`, change network state, install `aws-runas`, or
load services. Complete one explicit setup:

```sh
# Managed Mac, host consumers, or configured Docker Desktop images:
aws-metadata setup --mode user

# Transparent IMDS and validated container routing:
aws-metadata setup --mode system
```

Both modes look for `aws-runas` in `PATH` and `~/.local/bin`. If it is absent
and no `--aws-runas PATH` is supplied,
setup invokes the packaged checksum-verified bootstrap. The bootstrap downloads
the pinned, unmodified binary directly from the official upstream release into
`~/.local/bin`; the formula does not bundle or mirror it. If an executable is
already available, setup skips the download.

User mode installs a user LaunchAgent, listens on `127.0.0.1:18080`, and adds a
marked process provider to the default AWS profile without `sudo`. System mode
requests `sudo` for the root-owned service payload, link-local address, and
system launchd services; its credential broker still runs as the installing
user.
The modes refuse to coexist and setup never silently changes modes after a
blocked elevation attempt. See [macOS user mode](user-mode.md) for its
host and configured-image consumer boundary.

To use a specific existing binary and skip discovery:

```sh
aws-metadata setup --mode user --aws-runas /absolute/path/to/aws-runas
```

Setup should finish by reporting the installing user, agent version,
user-owned broker boundary, status command, and browser URL. Verify healthy
initial state:

```sh
aws-metadata version
aws-metadata status
```

Before first selection, `status` should say the service is running and no
profile is selected. Continue with
[Getting started](getting-started.md#2-confirm-one-upstream-profile) to test an
upstream profile, select it, and prove an AWS client uses metadata.

The supported Homebrew host boundary is Apple Silicon macOS 26. The exact
validated marketing `ProductVersion` is recorded in the
[project README](../README.md#supported-platforms). Other macOS versions and
architectures are not part of the current support claim.

## Switch service modes

Keep the Homebrew package installed and remove the current mode before setting
up the other one. To switch from user mode to system mode:

```sh
aws-metadata uninstall --mode user
aws-metadata setup --mode system
aws-metadata status
aws-metadata diagnose
```

System-mode setup requests administrator access. To switch from system mode to
user mode:

Before removing system mode, confirm that `[default]` contains no static
credentials, SSO or role settings, or another `credential_process`, and that
`[default]` in `~/.aws/credentials` is empty. User-mode setup refuses to replace
those credential sources. Move or rename them before starting the transition;
see [macOS user mode](user-mode.md#connect-applications) for the full
preflight contract.

```sh
aws-metadata uninstall --mode system
aws-metadata setup --mode user
aws-metadata status
aws-metadata diagnose
```

Removing system mode also requires administrator access because it must remove
root-owned launchd and link-local networking state. If device policy blocks
that command, do not remove files manually or try to bypass the policy; ask an
administrator to run the matching system-mode uninstaller. User-mode setup is
unprivileged after system mode has been removed.

Switching modes restarts the broker and clears its active profile. Reselect the
upstream profile after setup. Unrelated AWS configuration, named profiles, and
`aws-runas` caches are preserved. The endpoint and container boundary also
change, so review [Consumers](consumers.md) and
[Container runtimes](container-runtimes.md) before switching workflows that
depend on transparent `169.254.169.254` access.

## Browser-based authentication permission

The upstream `saml_provider = browser` flow starts and manages a dedicated
Chrome or Edge session through the Chrome DevTools Protocol. On macOS,
`aws-runas` may consequently appear under **System Settings -> Privacy &
Security -> App Management**.

If macOS prompts for access, or browser authentication cannot start or complete
while the entry is disabled:

1. Open **System Settings -> Privacy & Security -> App Management**.
2. Enable `aws-runas`.
3. Retry the profile selection or authentication command.

Apple describes App Management as permission for an application to update or
delete other applications. Grant it only after verifying the upstream
`aws-runas` binary installed or selected during setup. This permission is
separate from administrator access for networking and launchd services. It is
not required merely to trust the tap, install the formula, or use profiles that
do not invoke the browser provider.

See Apple's
[Privacy & Security settings reference](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac)
for the operating-system description of App Management.

## Recover from partial setup

If setup stopped, retain the exact error and rerun the same explicit mode:

```sh
aws-metadata setup --mode user
# or: aws-metadata setup --mode system
aws-metadata diagnose
```

Rerunning setup is supported. If clean removal is necessary, use the matching
`aws-metadata uninstall --mode user` or `--mode system` while the formula
remains installed, then rerun setup. Avoid manually deleting individual
launchd definitions or link-local state before the matching uninstaller can
restore known state.

See [Troubleshooting](troubleshooting.md) for endpoint, broker, browser, and
credential-provider boundaries.

## Upgrade

Upgrade the Homebrew payload, then explicitly refresh the selected mode:

```sh
brew update
brew upgrade aws-metadata-agent
aws-metadata setup --mode user
# or: aws-metadata setup --mode system
aws-metadata version
aws-metadata status
aws-metadata diagnose
```

Setup normally restarts the broker, so reselect the active profile. Homebrew
owns the command in its prefix; setup records that command removal belongs to
the package manager.

## Uninstall and revoke trust

Remove the selected service mode before the Homebrew payload:

```sh
aws-metadata uninstall --mode user
# or: aws-metadata uninstall --mode system
brew uninstall aws-metadata-agent
```

If Homebrew was removed first, reinstall the formula and run
the matching uninstall command, or use `uninstall.sh` from the matching tagged
source release. User mode removes only its marked default process provider.
Other AWS configuration, profiles, and `aws-runas` caches are preserved.

When the formula and tap are no longer needed, remove the tap and its trust
entry explicitly:

```sh
brew untrust --tap so1omon563/aws-metadata-agent
brew untap so1omon563/aws-metadata-agent
```

Untrusting does not uninstall a formula or remove a tap. Untapping does not
remove agent service state, which is why the matching explicit
`aws-metadata uninstall --mode ...` comes first.

## Rollback

The tap distributes the current supported release rather than retaining every
historical formula. Review the target release notes for schema or path
incompatibilities, remove service state and the Homebrew payload, then install
the exact earlier tag through its verified direct/source path. That temporarily
changes installation ownership away from Homebrew.

To return to the current formula, run the older release's `./uninstall.sh`,
then reinstall the formula and run `aws-metadata setup --mode user` or
`--mode system`. Do not keep source-owned and package-managed commands as
competing installations. See
[Upgrades and rollback](upgrades.md#rollback) for the full transition.

The maintainer-only formula wrapper, environment, and CI contract is in
[Release process](releasing.md#formula-contract).

## Related documentation

- [Getting started](getting-started.md)
- [Configure aws-runas](aws-runas-configuration.md)
- [Troubleshooting](troubleshooting.md)
- [Upgrades and rollback](upgrades.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

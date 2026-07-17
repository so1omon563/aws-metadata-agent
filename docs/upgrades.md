# Versioning, upgrades, and rollback

## Version source and release tags

`VERSION` is the source of truth for the project version. It contains a plain
semantic version such as `0.1.0`; the matching Git tag is prefixed with `v`,
for example `v0.1.0`. The `aws-metadata version` command reports the version
copied into the installed, root-owned service directory.

Only tagged releases are supported installation inputs. The initial `v0.1.0`
release predates the `VERSION` file; every later release must contain a
`VERSION` value that exactly matches its tag.

The project follows semantic versioning. While the project is on `0.x`, a
minor release may contain a breaking change, but the release notes must call it
out and provide an explicit migration path. After `1.0.0`, breaking changes
require a major release.

## In-place upgrades

Homebrew-managed upgrades use `brew upgrade` followed by an explicit
`aws-metadata setup` to refresh the root-owned service copy. See
[homebrew.md](homebrew.md) for the complete package-manager ordering.

To upgrade a source installation, check out the desired release tag and rerun
the installer:

```sh
git fetch --tags
git checkout v0.1.1
./install.sh
```

Replace `v0.1.1` with the release being installed. The installer replaces the
CLI, service executables, copied `aws-runas` binary, service definitions, and
root-owned configuration in place, then reloads or restarts the services.
Reinstalling the same version is supported.

An upgrade preserves user-owned AWS configuration and `aws-runas` cache files.
On Linux it also preserves the pre-install systemd linger state so uninstall
can restore it correctly. The installer never creates, selects, migrates, or
deletes an AWS profile.

The root-owned configuration records both `AWS_METADATA_AGENT_VERSION` and
`AWS_METADATA_CONFIG_VERSION`. Configuration schema 1 contains only installer
state: the target account and paths, local port, copied executable path, and
the original Linux linger state. It does not contain AWS credentials or
profiles.

Additive schema changes may use an existing schema version when older
executables safely ignore them. A change that removes, renames, or reinterprets
state must increment the schema version and include a tested installer
migration. An installer must reject an unsupported newer schema rather than
silently rewriting it. A destructive migration requires a breaking release as
defined above.

## Rollback and uninstall

There is no automatic rollback. If the prior release uses a compatible
configuration schema, check out its tag and rerun its installer. If schemas or
installed paths are incompatible, use the current release's `uninstall.sh`
first, then install the older release from a clean checkout.

Uninstall stops and removes the user broker and privileged forwarding
services, removes project-owned executables and configuration, and restores
the Linux linger state when the project originally enabled it. It leaves
user-owned AWS configuration, profiles, browser-authentication state, and
unrelated personal scripts untouched.

When moving between a package-manager installation and a source installation,
run the agent's privileged uninstall before removing the package payload. The
Homebrew-specific ordering is documented in [homebrew.md](homebrew.md).

## Release checklist

Each release must:

1. Update `VERSION` and verify that it exactly matches the proposed `v` tag.
2. Move relevant entries from `Unreleased` into a dated changelog section and
   describe breaking changes, migration requirements, and rollback limits.
3. Run the credential-free test suite and platform CI.
4. For installer-affecting changes, upgrade a supported host from the
   immediately previous release and verify version reporting, service health,
   metadata access, restart persistence, and uninstall. Skipped-version
   upgrades are best effort unless the release notes promise otherwise.
5. Verify that committed fixtures, logs, and documentation contain no AWS
   credentials, account IDs, profile names, identity output, or private
   infrastructure details.
6. Create the release tag only after the release commit is on the default
   branch.
7. Create and upload a versioned release archive named
   `aws-metadata-agent-vVERSION.tar.gz`, calculate its SHA-256, and upload the
   matching `aws-metadata-agent-vVERSION.tar.gz.sha256`. The checksum file must
   contain the hash and archive filename used by `install-release.sh`. Do not
   checksum GitHub's generated source archive as the installation artifact;
   GitHub does not guarantee stable bytes for those archives.
8. Download the two published release assets from their public URLs, verify the
   checksum, and exercise
   `install-release.sh --version VERSION -- --help` handoff without installing
   service state.

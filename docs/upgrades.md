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

Normal releases move through a dedicated pull request. Start from a clean
branch based on current `main`, confirm that `CHANGELOG.md` has complete
`Unreleased` entries, and stage the release metadata:

```sh
make stage-release BUMP=patch
make test
```

Use `minor` or `major` only when the release scope requires it. The staging
command fetches tags, derives the next version from the latest stable tag,
updates `VERSION`, moves the non-empty `Unreleased` entries into a dated
release section, and prints the required pull-request title. It refuses a dirty
working tree, an empty changelog, an existing tag, or a version inconsistent
with the requested bump.

The release PR title must contain exactly one of `#patch`, `#minor`, or
`#major`. Add `#release`, `#publish`, or `#ship` when merging the PR should also
publish the GitHub Release. For example:

```text
Prepare release 0.2.1 #patch #release
```

The squash or merge commit message must retain those markers. The pre-tag
validation and semantic-version action both read the checked-out merge commit,
so editing the final message to remove or change a marker fails before any tag
is created.

After the release PR merges, `.github/workflows/bump.yml`:

1. validates that the staged `VERSION` and changelog match the merge-commit
   marker;
2. uses `so1omon563/custom-semver-bumper@v1` to create the matching tag on the
   merged default-branch commit;
3. creates a deterministic `aws-metadata-agent-vVERSION.tar.gz` from that tag
   and its matching `.sha256` file;
4. uses `so1omon563/release-creator@v1` to publish grouped release notes and
   upload both verified assets when a release marker is present.

The downstream Homebrew workflow downloads and verifies those assets, updates
the separate tap formula to the release-asset URL and checksum, runs the
formula's strict audit, install, and tests, and opens a protected tap pull
request. It waits for the tap checks before squash-merging the update. The
parent repository must contain a `PACKAGING_PR_TOKEN` Actions secret backed by
a fine-grained token with access only to
`so1omon563/homebrew-aws-metadata-agent` and permission to write contents and
pull requests and read Actions and commit statuses.

The Homebrew workflow also supports manual dispatch with an existing release
tag. Use that fallback to retry tap publication without creating another tag
or GitHub Release.

Every release still requires the following evidence:

1. The credential-free suite and hosted platform CI pass.
2. For installer-affecting changes, upgrade a supported host from the
   immediately previous release and verify version reporting, service health,
   metadata access, restart persistence, and uninstall. Skipped-version
   upgrades are best effort unless the release notes promise otherwise.
3. Committed fixtures, logs, documentation, and release notes contain no AWS
   credentials, account IDs, profile names, identity output, or private
   infrastructure details.
4. The published tag, GitHub Release, archive, checksum, and Homebrew formula
   all report the same version.
5. Download the two public release assets, verify their checksum, and exercise
   `install-release.sh --version VERSION -- --help` without installing service
   state.

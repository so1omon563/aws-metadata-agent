# Release process

This is maintainer documentation. End users should follow
[Upgrades, rollback, and uninstall](upgrades.md).

## Release contract

- `VERSION` is the source of truth after the initial release.
- Release tags add `v` and must exactly match `VERSION`.
- Normal publication starts from a dedicated pull request based on current
  protected `main`.
- The merge commit must retain exactly one semantic marker: `#patch`, `#minor`,
  or `#major`.
- A GitHub Release is published only when the merge commit also contains
  `#release`, `#publish`, or `#ship`.
- Stable assets are deterministic project-built archives and checksums, not
  GitHub-generated source archives.
- Homebrew publication is downstream of a verified GitHub Release.

## Prepare release metadata

Start from a clean branch. Confirm that `CHANGELOG.md` has complete, sanitized
`Unreleased` entries, then stage the release:

```sh
make stage-release BUMP=patch
make check-release
make test
```

Use `minor` or `major` only when the release scope requires it. Staging:

1. fetches semantic tags;
2. derives the next version from the latest stable tag;
3. updates `VERSION`;
4. moves nonempty `Unreleased` entries into a dated release section;
5. advances pinned current-release examples in `README.md`,
   `docs/direct-install.md`, and `install-release.sh`; and
6. prints the required pull-request title.

`scripts/check_release.py` rejects those current-release examples when they do
not all match `VERSION`. Historical versions in the changelog and illustrative
release-process examples are intentionally excluded from that current-version
contract.

Example title:

```text
Prepare release 0.2.3 #patch #release
```

The checked-out merge commit is the authoritative marker source. Removing or
changing the marker from the final squash/merge message must fail before tag
creation.

## Required validation

Every release requires:

1. Credential-free local tests and protected macOS/Ubuntu CI.
2. A completed bounded code review with actionable conversations resolved.
3. No credentials, account IDs, real profile names, identities,
   identity-provider details, or private infrastructure in fixtures, logs,
   documentation, changelog, or release notes.
4. For installer-affecting changes, an upgrade from the immediately previous
   release on a supported host, including version, service health, metadata
   access, restart persistence, and uninstall.
5. Exact agreement among `VERSION`, tag, GitHub Release, archive, checksum, and
   Homebrew formula.

Hosted CI and containers do not replace a native service-manager/reboot test
when a change crosses launchd, systemd user lingering, root-owned networking,
or first-install boundaries.

## Tag and GitHub Release automation

After the release PR merges, `.github/workflows/bump.yml`:

1. validates staged version/changelog data against the merge-commit marker;
2. invokes `so1omon563/custom-semver-bumper@v1` to create the exact tag on the
   default-branch merge commit;
3. creates deterministic `aws-metadata-agent-vVERSION.tar.gz` and matching
   `.sha256` assets from that tag; and
4. invokes `so1omon563/release-creator@v1` to publish grouped notes and upload
   verified assets when a release marker is present.

After publication, verify the immutable public state rather than relying on a
green merge alone:

```sh
make release-assets
```

Download the public archive and checksum, verify the pair, inspect the archive
root and embedded `VERSION`, and exercise the safe installer-help handoff:

```sh
sh ./install-release.sh --version VERSION -- --help
```

That check must not install service state or touch AWS configuration.

## Homebrew publication

The post-release workflow downloads and verifies the project-uploaded assets,
updates the dedicated
[`homebrew-aws-metadata-agent`](https://github.com/so1omon563/homebrew-aws-metadata-agent)
formula, runs its strict audit/install/test contract, and opens a ready
protected tap pull request. It waits for the required tap check before
squash-merging.

The parent repository's `PACKAGING_PR_TOKEN` must be a fine-grained token with
access only to `so1omon563/homebrew-aws-metadata-agent`, contents and pull
request write permission, and Actions/commit-status read permission. Do not
reuse a broad personal token.

The workflow supports manual dispatch with an existing release tag to retry
tap publication without creating another tag or GitHub Release.

## Formula contract

The formula:

- installs the verified release tree under its private `libexec`;
- provides the stable package-managed `aws-metadata` wrapper;
- sets `AWS_METADATA_PACKAGE_ROOT` to the packaged release tree;
- sets `AWS_METADATA_VERSION_FILE` to the packaged `VERSION`;
- sets `AWS_METADATA_PACKAGE_CLI` to the package-managed wrapper so setup can
  remove only a distinct legacy source CLI; and
- never runs `sudo`, changes networking, installs `aws-runas`, or loads native
  services during formula installation.

Formula tests verify `aws-metadata version` and
`aws-metadata setup --help` without administrator access, network downloads,
service changes, or AWS configuration.

## Documentation and release notes

- Keep current pinned examples synchronized through release staging rather
  than editing one document manually.
- Keep support claims tied to recorded validation; patch releases do not imply
  new platform support.
- Link upstream `aws-runas` behavior to its official documentation rather than
  copying a complete upstream manual.
- Sanitize every public example according to [CONTRIBUTING.md](../CONTRIBUTING.md).

## Related documentation

- [Contributing](../CONTRIBUTING.md)
- [Upgrades and rollback](upgrades.md)
- [Direct release installation](direct-install.md)
- [Changelog](../CHANGELOG.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

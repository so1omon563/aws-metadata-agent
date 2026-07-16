## Summary

Describe what this change achieves and why it is needed.

## Related issues

List related issues, using `Closes #123` when appropriate.

## Changes

- _List the main changes._

## Validation

- [ ] `make test` passes locally
- [ ] Relevant macOS behavior was tested, or the change does not affect macOS
- [ ] Relevant Linux behavior was tested, or Linux remains explicitly unverified
- [ ] Installation, upgrade, reboot, and uninstall effects were considered where applicable

## Security and compatibility

- [ ] No credentials, account IDs, profile names, identities, or organization-specific data are included
- [ ] Privileged services still use root-owned executables and absolute paths
- [ ] Metadata requests still bypass HTTP proxies with `--noproxy '*'`
- [ ] Executable bits are preserved for shell entry points and tests
- [ ] Documentation reflects any change to platform support, credential exposure, or the global-profile limitation

## Additional context

Add logs, screenshots, migration notes, or follow-up work. Sanitize all output.

# Contributing

Contributions should preserve the project's narrow support claims, privilege
separation, supply-chain checks, and explicit credential trust model.

## Development checks

Run the credential-free suite before opening a pull request:

```sh
make test
```

When available, validate GitHub Actions syntax as well:

```sh
actionlint
```

Finish with:

```sh
git diff --check
git status --short --branch
```

CLI tests use fixtures and do not contact AWS or the host metadata address.
The Linux container-runtime test is a separate host-network check and requires
the explicit prerequisites documented in
[docs/container-runtimes.md](docs/container-runtimes.md).

## Pull requests

- Use a focused branch and keep unrelated local changes out of the commit.
- Explain the user or operator impact, security boundary, and support claim
  affected by the change.
- Keep credential-free local and hosted macOS/Ubuntu checks green.
- Resolve actionable review conversations before merge.
- Do not add a release marker unless the pull request intentionally stages and
  publishes a release through [docs/releasing.md](docs/releasing.md).

## Documentation examples

Project-specific examples belong in public documentation only when they add an
integration pattern not already clear in the authoritative upstream material.

Before committing an example:

- replace real profile names with fictional names such as
  `example-nonprod`;
- replace account IDs, identities, tenant or client IDs, application IDs,
  private endpoints, role and MFA ARNs, and user names with unmistakable
  placeholders;
- never include credentials, tokens, passwords, browser cookies, real
  `status --json` profile objects, or raw authentication logs;
- link to the official upstream or AWS document that defines the underlying
  behavior; and
- state the evidence boundary when an application, SDK, runtime, host, or
  identity-provider flow has not been validated.

The official [aws-runas documentation](https://mmmorris1975.github.io/aws-runas/)
is authoritative for upstream configuration and behavior. Project docs should
explain this agent's integration boundary rather than reproduce a complete
upstream manual.

## Release work

Normal feature and documentation pull requests remain marker-free. Release
metadata, tags, assets, and Homebrew publication follow the dedicated
[release process](docs/releasing.md).

## Security reports

Do not open a public issue for a suspected vulnerability. Follow
[SECURITY.md](SECURITY.md).

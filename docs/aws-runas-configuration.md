# Configure aws-runas

`aws-metadata-agent` exposes profiles that are configured and authenticated by
`aws-runas`. It does not create profiles or replace the upstream configuration
model.

The official [aws-runas documentation](https://mmmorris1975.github.io/aws-runas/)
is authoritative. When this guide is incomplete, ambiguous, or differs from
upstream, follow the upstream documentation. This guide covers only the
configuration boundary needed to use an upstream profile through
`aws-metadata-agent`.

The examples below use the attributes documented for the project's supported
`aws-runas` 3.9.0 dependency. They are deliberately sanitized and incomplete:
replace angle-bracketed values with configuration supplied by the people who
manage your AWS accounts and identity provider. Never commit credentials or
real identity-provider details to this repository.

## Ownership boundary

`aws-runas` owns the user-specific AWS state:

- profiles in `~/.aws/config`;
- credentials or upstream-managed password entries in `~/.aws/credentials`;
- authentication and credential caches stored by `aws-runas` under `~/.aws`;
- SAML, OIDC, MFA, and role-assumption behavior.

`aws-metadata-agent` owns the service integration:

- the root-owned installed copy of the `aws-runas` executable;
- the developer-owned broker process;
- forwarding from `169.254.169.254:80` to that broker;
- selection of one configured profile through `aws-metadata use`.

Installation does not read, create, copy, or modify `~/.aws/config`,
`~/.aws/credentials`, or upstream cache files. The broker runs as the installing
developer, so it reads the same user-owned configuration as an interactive
`aws-runas` command.

## Configuration files

On macOS and Linux, upstream uses the standard AWS files in `~/.aws`:

- `~/.aws/config` contains default settings and named profiles;
- `~/.aws/credentials` may contain sensitive source credentials or
  upstream-managed password entries.

Protect the credentials file as sensitive data. The upstream
[Quick Start Guide](https://mmmorris1975.github.io/aws-runas/quickstart.html)
and [IAM Configuration Guide](https://mmmorris1975.github.io/aws-runas/iam_config.html)
describe its format, permissions, alternate file locations, and the complete
set of supported IAM attributes.

Named profiles in `~/.aws/config` use the standard `[profile NAME]` section
form. The name after `profile` is the value passed to `aws-metadata use`.

## IAM role profile

A minimal role profile uses a source profile and role ARN:

```ini
[default]
region = us-west-2

[profile example-iam]
source_profile = default
role_arn = <role-arn>
```

When the role requires MFA, add the MFA device ARN to that profile:

```ini
[profile example-iam-mfa]
source_profile = default
role_arn = <role-arn>
mfa_serial = <mfa-device-arn>
```

The referenced source profile must have a valid upstream-supported credential
source. Do not put access keys in `~/.aws/config`. Follow the official
[IAM Configuration Guide](https://mmmorris1975.github.io/aws-runas/iam_config.html)
for source credentials, shared MFA settings, session duration attributes, and
environment-variable behavior.

## SAML profile

A minimal SAML profile identifies the authentication endpoint and AWS role:

```ini
[profile example-saml]
region = us-west-2
saml_auth_url = https://idp.example.invalid/saml/auth
saml_username = user@example.invalid
role_arn = <role-arn>
```

`saml_username` is optional. Authentication and MFA behavior depend on the
identity provider. Use the official
[SAML Configuration Guide](https://mmmorris1975.github.io/aws-runas/saml_config.html)
for supported providers, provider-specific attributes, password handling, and
advanced options.

## OIDC profile

A minimal Web Identity/OIDC profile identifies the provider, client, redirect
URI, and AWS role:

```ini
[profile example-oidc]
region = us-west-2
web_identity_auth_url = https://idp.example.invalid/oauth2
web_identity_username = user@example.invalid
web_identity_client_id = <client-id>
web_identity_redirect_uri = app:/callback
role_arn = <role-arn>
```

`web_identity_username` is optional. Obtain the client ID, redirect URI,
authentication endpoint, and role ARN from the administrators responsible for
your identity provider and AWS accounts. Follow the official
[OIDC Configuration Guide](https://mmmorris1975.github.io/aws-runas/oidc_config.html)
for provider-specific behavior and the complete attribute reference.

## Select and use a profile

After the service is installed, select a configured profile by name:

```sh
aws-metadata use example-iam
aws-metadata status
```

The first command opens the browser when the selected profile requires SAML,
OIDC, or MFA interaction. Applications then use the normal EC2 metadata
provider at `169.254.169.254`; they do not need the profile name or access to
the user's AWS files.

The active profile is process state, not persistent configuration. Select it
again after the broker restarts or the host reboots. The metadata service has
one globally active profile, so the most recent selection wins for every local
consumer that can reach the endpoint.

For upstream details about the EC2-compatible service itself, see the official
[Metadata Credential Service](https://mmmorris1975.github.io/aws-runas/metadata_credentials.html)
documentation.

## Custom setups

Custom configurations should preserve the same ownership boundary: define and
authenticate the profile using supported `aws-runas` configuration, then pass
only its profile name to `aws-metadata use`.

Project-specific examples belong here only when they add an integration pattern
that is not already clear in the upstream documentation. Sanitize profile
names, account and identity details, role and MFA ARNs, client IDs, endpoints,
and all credentials before publishing an example. Link each example to the
upstream guide that defines the underlying attributes.

## Official references

- [aws-runas documentation](https://mmmorris1975.github.io/aws-runas/)
- [Quick Start Guide](https://mmmorris1975.github.io/aws-runas/quickstart.html)
- [IAM Configuration Guide](https://mmmorris1975.github.io/aws-runas/iam_config.html)
- [SAML Configuration Guide](https://mmmorris1975.github.io/aws-runas/saml_config.html)
- [OIDC Configuration Guide](https://mmmorris1975.github.io/aws-runas/oidc_config.html)
- [Metadata Credential Service](https://mmmorris1975.github.io/aws-runas/metadata_credentials.html)
- [Upstream repository](https://github.com/mmmorris1975/aws-runas)

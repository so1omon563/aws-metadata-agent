# Configure aws-runas

`aws-metadata-agent` exposes profiles that are configured and authenticated by
`aws-runas`. It does not create profiles or replace the upstream configuration
model. Start with one upstream profile that works directly; add the metadata
service only after that boundary succeeds.

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

## Start here

If an upstream profile already works, list the standard AWS profile names and
test the intended role directly:

```sh
aws configure list-profiles
aws-runas -r example-nonprod /usr/bin/true
printf 'exit=%s\n' "$?"
```

Exit `0` confirms that upstream can obtain credentials. Skip to
[Select and use a profile](#select-and-use-a-profile).

If no upstream profile works yet, choose the relevant IAM, SAML, or OIDC
pattern below, then follow the linked official guide for the complete
configuration. The snippets are illustrative shapes, not copy-paste account
configuration.

Keep the three profile concepts distinct:

- an **upstream profile** in `~/.aws/config` defines authentication and role
  assumption;
- the **active agent profile** is the one upstream profile selected globally
  by `aws-metadata use`; and
- an optional **consumer compatibility profile** such as `local-metadata`
  tells a profile-oriented application to read the current metadata identity.

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

## Named metadata profile for profile-oriented tools

Some integrations require the user to select a named AWS profile instead of
using the default credential provider chain directly. The AWS Toolkit for
Visual Studio Code is one example. A dedicated consumer compatibility profile
can point those tools at the standard EC2 metadata provider:

```ini
[profile local-metadata]
region = us-west-2
credential_source = Ec2InstanceMetadata
```

This profile and an upstream `aws-runas` profile serve different purposes:

- `aws-metadata use example-iam` selects the real upstream profile whose
  credentials the broker exposes;
- `--profile local-metadata` tells a profile-oriented consumer to retrieve the
  currently exposed credentials from EC2 metadata.

For example, after selecting the upstream profile:

```sh
aws-metadata use example-iam
aws --profile local-metadata sts get-caller-identity
```

Select `local-metadata` in the AWS Toolkit for Visual Studio Code for the same
reason. The consumer profile does not select or lock an upstream profile, and
it does not correspond one-to-one with an AWS role. If another caller changes
the active agent profile, the consumer receives credentials for the new active
profile.

No custom endpoint is required because `aws-metadata-agent` exposes the
standard `169.254.169.254` address. Applications that already use the default
credential provider chain do not need this named profile. Standalone
`credential_source` is intentionally used here as a consumer compatibility
profile, not as an assume-role profile. AWS primarily documents the setting as
an [assume-role credential source], but the [Toolkit credential provider]
explicitly maps the standalone `Ec2InstanceMetadata` value to its instance
metadata provider, and AWS CLI v2 continues through its credential chain to
IMDS. Do not add a `role_arn` merely to complete this consumer profile: that
would ask the consumer to assume another role after retrieving the credentials
already selected through `aws-metadata-agent`. Behavior may vary among other
SDKs and tools; test the specific integration.

See [Consumer recipes](consumers.md#profile-oriented-consumers), the AWS
documentation for
[Toolkit credential profiles](https://docs.aws.amazon.com/toolkit-for-vscode/latest/userguide/setup-credentials.html),
and the
[EC2 instance metadata credential source](https://docs.aws.amazon.com/sdkref/latest/guide/feature-assume-role-credentials.html).

## Custom setups

Custom configurations should preserve the same ownership boundary: define and
authenticate the profile using supported `aws-runas` configuration, then pass
only its profile name to `aws-metadata use`.

### Browser-based Azure AD SAML with derived roles

A browser-backed SAML profile can hold common authentication settings while
several derived profiles identify the IAM roles to assume:

```ini
[profile example-saml-source]
region = us-west-2
saml_auth_url = https://myapps.microsoft.com/signin/<application-name>/<application-id>?tenantId=<tenant-id>
saml_provider = browser
credentials_duration = <duration>

[profile example-role-one]
role_arn = <role-arn>
source_profile = example-saml-source

[profile example-role-two]
role_arn = <role-arn>
source_profile = example-saml-source
```

Copy the Azure Enterprise Application user-access URL supplied by the identity
administrators. The application and tenant placeholders above must not be
committed with real values.

The derived profiles inherit the SAML configuration through `source_profile`.
Pass a derived profile such as `example-role-one` to `aws-metadata use`; the
SAML source profile centralizes authentication but does not identify the final
role. `credentials_duration` uses a Go duration such as `1h`, must be between
15 minutes and 12 hours, and cannot exceed the target role's configured maximum
session duration.

The `browser` provider uses a browser session that `aws-runas` can observe for
the SAML response. Upstream also documents a distinct `browserne` provider;
do not substitute it without reviewing its additional identity-provider and
role trust-policy requirements. On macOS, the `browser` provider may also need
the `aws-runas` entry enabled under **System Settings → Privacy & Security → App
Management**; see the
[Homebrew browser-permission guidance](homebrew.md#browser-based-authentication-permission).

See the official upstream
[SAML Configuration Guide](https://mmmorris1975.github.io/aws-runas/saml_config.html)
for shared source-profile behavior and the
[SAML Client Configuration Guide](https://mmmorris1975.github.io/aws-runas/saml_client_config.html)
for Azure AD and browser-provider configuration.

## Official references

- [aws-runas documentation](https://mmmorris1975.github.io/aws-runas/)
- [Quick Start Guide](https://mmmorris1975.github.io/aws-runas/quickstart.html)
- [IAM Configuration Guide](https://mmmorris1975.github.io/aws-runas/iam_config.html)
- [SAML Configuration Guide](https://mmmorris1975.github.io/aws-runas/saml_config.html)
- [SAML Client Configuration Guide](https://mmmorris1975.github.io/aws-runas/saml_client_config.html)
- [OIDC Configuration Guide](https://mmmorris1975.github.io/aws-runas/oidc_config.html)
- [Metadata Credential Service](https://mmmorris1975.github.io/aws-runas/metadata_credentials.html)
- [Upstream repository](https://github.com/mmmorris1975/aws-runas)
- [AWS Toolkit for Visual Studio Code credential profiles](https://docs.aws.amazon.com/toolkit-for-vscode/latest/userguide/setup-credentials.html)
- [AWS EC2 instance metadata credential source](https://docs.aws.amazon.com/sdkref/latest/guide/feature-assume-role-credentials.html)

[assume-role credential source]: https://docs.aws.amazon.com/sdkref/latest/guide/feature-assume-role-credentials.html
[Toolkit credential provider]: https://github.com/aws/aws-toolkit-vscode/blob/master/packages/core/src/auth/providers/sharedCredentialsProvider.ts

## Related documentation

- [Getting started](getting-started.md)
- [Consumer recipes](consumers.md)
- [Troubleshooting](troubleshooting.md)
- [Documentation contribution policy](../CONTRIBUTING.md#documentation-examples)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

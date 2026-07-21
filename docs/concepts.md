# Concepts

This page explains the credential and profile model behind
`aws-metadata-agent`. Use it when you want to understand what applications see;
use [Architecture](architecture.md) for processes, files, and privilege
boundaries.

## The mental model

`aws-metadata-agent` makes EC2 instance metadata the canonical credential
interface on a developer workstation.

```text
Developer
    |
    | selects an upstream aws-runas profile
    v
aws-metadata-agent
    |
    | exposes temporary credentials through IMDS
    v
169.254.169.254
    |
    +--> AWS CLI and SDKs
    +--> VS Code and coding agents
    +--> trusted containers and GUI automation
```

The application does not need to understand `aws-runas`. It follows its normal
AWS credential provider chain and reaches the same metadata address it would
use on EC2.

## The three profile roles

```text
upstream aws-runas profile       example-nonprod in ~/.aws/config
                                       |
                                       | aws-metadata use example-nonprod
                                       v
active agent profile             one globally exposed identity
                                       |
                                       | EC2 metadata credential provider
                                       v
consumer compatibility profile  local-metadata (optional)
```

The **upstream profile** defines how `aws-runas` authenticates and assumes a
role. The **active agent profile** is the one upstream profile currently
exposed at the metadata endpoint. Applications consume that active identity;
they do not independently select the upstream profile.

Most AWS SDKs and tools using the default credential provider chain need no
extra profile. A **consumer compatibility profile**, such as
`local-metadata`, is only for profile-oriented software that requires a named
choice while still obtaining credentials from EC2 metadata. It does not bind
the consumer to one upstream role.

See [Configure aws-runas](aws-runas-configuration.md) for upstream examples and
[Consumer recipes](consumers.md) for application-specific setup.

## One endpoint, one active identity

EC2 metadata exposes one instance role, and this service similarly exposes one
active upstream profile. The most recent successful selection wins for every
consumer that reaches the endpoint.

For example, if VS Code observes profile A and a Stream Deck action later
selects profile B, VS Code can receive profile B credentials on its next
refresh. Use a different credential approach when concurrent consumers require
independent identities.

## Credential discovery

AWS tools use ordered provider chains. Explicit environment credentials,
named profiles, SSO, shared files, `credential_process`, web identity, or
container credentials may take precedence over EC2 metadata. A successful AWS
command therefore does not by itself prove that this service supplied the
credentials.

Use the provider-isolated procedure in [Verification](verification.md) to
prove the metadata path. Provider order can vary by SDK, so verify the exact
consumer before claiming compatibility.

## State lifetime

| State | Service restart | Reboot | Agent uninstall |
| --- | --- | --- | --- |
| Installed services and executables | Retained | Retained | Removed |
| Link-local forwarding | Recreated | Recreated | Removed |
| User-owned AWS profile definitions | Retained | Retained | Preserved |
| Upstream role credential cache | Subject to expiration | Subject to expiration | Preserved |
| Upstream browser session state | Provider-controlled | Provider-controlled | Preserved |
| Active agent profile | Cleared | Cleared | Not applicable |

Native services return after logout or reboot, but the developer must select a
profile again after the broker restarts. Upstream `aws-runas` owns temporary
credential refresh and browser-session behavior.

`aws-metadata clear` deliberately restarts only the user broker and verifies
that it returns to healthy no-profile state. This prevents later metadata
requests from receiving the previously active identity, but it cannot revoke
temporary credentials that a consumer already fetched. Upstream credential
and browser caches remain available for a later explicit selection.

## Next steps

- [Getting started](getting-started.md)
- [Verification](verification.md)
- [Consumer recipes](consumers.md)
- [Architecture](architecture.md)
- [Security model](security.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

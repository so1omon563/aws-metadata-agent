# Security model

This page helps you decide whether the service's credential exposure and trust
boundaries are appropriate for a workstation and its local workloads.

For supported security-fix versions and private vulnerability reporting, see
the repository [security policy](../SECURITY.md).

## Intended trust boundary

`aws-metadata-agent` is designed for a trusted developer account on a trusted
workstation. It intentionally makes temporary AWS credentials available to
software that can reach a standard metadata address.

| Actor or boundary | Security expectation |
| --- | --- |
| Installing developer | Trusted to configure upstream profiles and select the active identity. |
| Root-owned installer and native service definitions | Trusted to establish the address and forwarding path; do not own AWS authentication. |
| Trusted host application | May obtain credentials for the globally active profile. |
| Other local user or process | If it can route to the endpoint, it may obtain credentials or request a profile change; the endpoint is not an authorization boundary. |
| Container | Same risk as a host process when its runtime routes the metadata address. |
| Local service with SSRF | May be abused to fetch metadata credentials if it can reach the address and accepts attacker-controlled URLs. |
| Remote network peer | The project binds the metadata address to loopback rather than an external interface, but routing or firewall policy must not be treated as profile authorization. |

Do not install the project when untrusted local workloads must be isolated from
the active AWS identity or when organizational policy prohibits a workstation
metadata service.

## Credentials are intentionally reachable

The purpose of the service is to let local applications and containers obtain
temporary AWS credentials without explicit environment injection or AWS file
mounts. Any process that can reach `169.254.169.254` may be able to obtain the
active profile's credentials.

Concrete examples include:

- another process in the same developer account;
- another local account with a route to the host-local address;
- a Docker container whose network reaches the host endpoint;
- a development web service vulnerable to server-side request forgery; and
- a coding agent or IDE extension using the default AWS credential chain.

IMDSv2 compatibility does not change this local trust model. Upstream
`aws-runas` explicitly implements enough of IMDSv2 for credential requests,
not the complete EC2 security model.

## Profile switching is global and unauthenticated

The browser and HTTP API can change the one globally active upstream profile.
Local `POST /profile` access does not require an authentication token. This is
intentional convenience for a single trusted developer workstation.

A caller must not assume that its selected profile remains active. Stream Deck
keys, IDEs, scripts, containers, and coding agents all share the same broker.
The most recent successful selection wins, and the project has no current lease
or per-consumer enforcement layer.

Profile names are not credentials, but they can reveal environments, account
roles, or organization structure. Treat them as potentially sensitive in logs
and automation output.

Use `aws-metadata clear` when work with the active identity is complete. It
returns the broker to no-profile state and does not print the previous profile
name. This reduces accidental future credential retrieval, but it is not a
revocation boundary: applications may retain already-issued STS credentials
until expiration, and any local caller with endpoint access can select a
profile again.

## Privilege boundary

`aws-runas` does not run as root. A root-owned wrapper rejects startup unless
its effective uid matches the configured developer uid. The broker therefore
reads that user's `~/.aws` configuration and creates refreshed cache files with
upstream's user ownership and modes.

Root is limited to:

- installing executable copies and service definitions in root-owned paths;
- assigning `169.254.169.254/32` to loopback; and
- arranging TCP forwarding to `127.0.0.1:18080`.

On macOS, launchd owns the privileged socket and runs the system `nc` command
as `nobody` for each accepted connection; the root setup process exits. On
Linux, systemd owns the socket and launches its native proxy with a dynamic
user, strict filesystem protection, no new privileges, and an empty capability
bounding set.

Installed service executables are root-owned and referenced by absolute path.
A user-writable `~/bin`, `~/.local/bin`, Homebrew prefix, or other `PATH` entry
is not executed by a privileged process. The copied upstream binary is
root-owned but executes as the configured developer.

The root-owned configuration file contains installer state only: user name,
uid, home path, binary path, local port, version/schema, CLI ownership, and
prior Linux linger state. It contains no AWS profile definitions, credentials,
passwords, tokens, or browser cookies.

## Browser authentication

The macOS broker runs in the developer's GUI launchd domain. Linux browser
opening is performed by the calling user command through `xdg-open` or `gio`.
The privileged forwarding service never opens a browser or receives an
identity-provider password or MFA code.

Upstream browser state and role credential caches remain under `~/.aws` and
survive agent uninstall. Provider sessions can expire independently of AWS STS
credentials. A browser login can succeed while a later AWS credential exchange
fails, so do not equate a closed browser window with a ready AWS identity.

On macOS, an upstream `saml_provider = browser` session may require the verified
`aws-runas` entry under **System Settings -> Privacy & Security -> App
Management**. Grant that permission only when the browser provider needs it;
it is not required for formula installation or native service setup.

## Logs and diagnostics

`aws-metadata errors` examines a bounded recent log window and prints fixed
redacted classifications. Full broker logs and upstream verbose diagnostics can
contain profile data, identity-provider URLs, account or role identifiers, and
possibly credentials.

- Inspect full logs locally before sharing any excerpt.
- Never publish real `status --json` profile objects.
- Never publish `aws-runas -v` or `-vv` output without complete review and
  redaction.
- Keep temporary automation logs in the user's private `TMPDIR` and remove them
  after the investigation.

## Pre-install security checklist

- [ ] The workstation and installing developer account are trusted.
- [ ] Local applications or containers that can reach metadata are trusted with
      the active role.
- [ ] Concurrent consumers do not require independent identities.
- [ ] Local policy permits a workstation-hosted link-local metadata service.
- [ ] The host is within the documented support boundary or unvalidated use is
      explicitly accepted.
- [ ] The Homebrew tap or direct-release scripts and checksums were reviewed.
- [ ] Upstream profiles use the least privilege and session duration appropriate
      for their work.
- [ ] Local SSRF-prone development services cannot be used by untrusted callers
      to reach metadata.

## Related documentation

- [Architecture](architecture.md)
- [Getting started](getting-started.md)
- [Container runtime validation](container-runtimes.md)
- [Troubleshooting](troubleshooting.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

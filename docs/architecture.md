# Architecture

This document describes how `aws-metadata-agent` exposes the credential subset
of EC2 instance metadata while keeping AWS authentication and user-owned state
in the developer account.

## Goals

- Preserve the standard `169.254.169.254:80` EC2 metadata address.
- Keep `aws-runas`, browser authentication, and AWS caches unprivileged.
- Restrict root to installed code, a link-local address, and TCP forwarding.
- Keep AWS profile definitions and credentials outside project-owned state.
- Survive terminal exit, logout, and reboot through native service managers.
- Expose one active profile honestly rather than claim per-consumer isolation.

## Process topology and ownership

```text
trusted local consumer
  AWS CLI / SDK / IDE / container
                |
                | HTTP, IMDS credential subset
                v
        169.254.169.254:80
                |
                | root-owned address and socket
                v
 privileged forwarding layer
  macOS: launchd + nc as nobody
  Linux: systemd socket + DynamicUser proxy
                |
                | TCP
                v
        127.0.0.1:18080
                |
                | developer uid
                v
 aws-runas EC2 metadata broker
  ~/.aws config, browser, caches
                |
                v
 identity provider and AWS STS
```

The privileged layer knows only the external link-local address and internal
loopback port. It does not receive an AWS profile, read a home directory, open
a browser, or parse credentials.

## Installed layout

Common root-owned state:

| Path | Purpose |
| --- | --- |
| `/usr/local/libexec/aws-metadata-agent/aws-metadata-server` | Validates the developer uid and starts the upstream broker. |
| `/usr/local/libexec/aws-metadata-agent/aws-runas` | Protected copy of the selected upstream executable; executes as the developer. |
| `/usr/local/libexec/aws-metadata-agent/aws-metadata-forwarder` | macOS link-local and socket setup. |
| `/usr/local/libexec/aws-metadata-agent/aws-metadata-network` | Linux link-local address setup and cleanup. |
| `/usr/local/libexec/aws-metadata-agent/VERSION` | Installed release version. |
| `/etc/aws-metadata-agent/config` | Installer state: account, uid, paths, port, schema, CLI ownership, and prior Linux linger state. |

The configuration file is root-owned mode `0644` because the user broker must
read it. It contains no AWS profiles, credentials, passwords, tokens, or
browser state.

A source/direct installation owns `/usr/local/bin/aws-metadata`. A Homebrew
installation keeps the command under the Homebrew prefix and uses the same
root-owned service layout without transferring package-command ownership to
the installer.

### macOS services

| Domain | Definition | Role |
| --- | --- | --- |
| Developer GUI | `~/Library/LaunchAgents/com.github.so1omon563.aws-metadata-agent.broker.plist` | Keeps the broker running as the installing user. |
| System | `/Library/LaunchDaemons/com.github.so1omon563.aws-metadata-agent.forwarder.plist` | Creates the loopback alias and loads the socket proxy. |
| System | `/Library/Application Support/aws-metadata-agent/com.github.so1omon563.aws-metadata-agent.proxy.plist` | Lets launchd own port 80 and runs `/usr/bin/nc` as `nobody` per accepted connection. |

### Linux services

| Manager | Definition | Role |
| --- | --- | --- |
| Developer user manager | `~/.config/systemd/user/aws-metadata-agent.service` | Keeps the broker running as the installing user. |
| System manager | `/etc/systemd/system/aws-metadata-agent-address.service` | Maintains `169.254.169.254/32` on loopback. |
| System manager | `/etc/systemd/system/aws-metadata-agent.socket` | Owns `169.254.169.254:80`. |
| System manager | `/etc/systemd/system/aws-metadata-agent.service` | Runs `systemd-socket-proxyd` to `127.0.0.1:18080` with a dynamic user and filesystem hardening. |

The system and user services intentionally share the descriptive base name in
different systemd manager namespaces. The installer records whether lingering
was already enabled, enables it for the developer user, and restores the prior
state during uninstall when the project originally changed it.

## Startup order

### macOS

1. The developer LaunchAgent starts the root-owned server wrapper in the GUI
   domain.
2. The wrapper rejects an unexpected effective uid, then executes the protected
   `aws-runas` copy as an unprivileged EC2 broker on `127.0.0.1:18080`.
3. The root LaunchDaemon creates the `/32` loopback alias when absent.
4. The forwarder loads the launchd socket definition for
   `169.254.169.254:80`.
5. For each accepted connection, launchd invokes the system `nc` executable as
   `nobody` to connect to the broker.

### Linux

1. systemd user lingering allows the developer user manager to start
   independently of a terminal or active login.
2. The user service starts the protected broker on `127.0.0.1:18080`.
3. The system address service assigns `169.254.169.254/32` to `lo`.
4. The system socket starts after the address service and owns port 80.
5. Socket activation launches the hardened `systemd-socket-proxyd` service for
   accepted traffic.

The installer waits for the metadata endpoint before reporting success. A
running endpoint with no selected profile is the expected initial state.

## Request and authentication flow

1. `aws-metadata use PROFILE` posts the upstream profile name to `/profile`.
2. HTTP 200 or 204 means upstream credentials are ready.
3. HTTP 401 means SAML/OIDC, password, or MFA interaction is required.
4. Human-oriented selection opens the metadata browser interface and polls the
   same profile request for a bounded period.
5. Automation-oriented selection returns a stable nonzero exit unless the
   caller explicitly opts into browser interaction and waiting.
6. Once ready, an AWS consumer requests the active role name and temporary
   credentials through the normal IMDS credential paths.

`aws-metadata status` reads that same live role-name path for the user's exact
configuration name and reads `/profile` for the existing detail object. It does
not persist either response. Because selection is global and unauthenticated,
concurrent requests can still observe the latest selection between reads; a
later status call always returns fresh broker state rather than a cached label.

Credential expiration and refresh belong to upstream `aws-runas`. A valid
browser session can allow silent renewal; an expired provider session can
require new interaction. Browser authentication and the later AWS STS exchange
are separate boundaries.

## Protocol compatibility

`aws-metadata-agent` forwards the upstream `aws-runas` EC2 metadata service; it
does not implement a second metadata protocol. Upstream describes that service
as a stripped-down EC2 instance metadata implementation that exposes credential
interfaces but not other EC2 instance information.

The upstream contract includes:

- IMDSv1 and IMDSv2 request compatibility for credential consumers;
- the active role name at
  `/latest/meta-data/iam/security-credentials/`;
- temporary credentials at
  `/latest/meta-data/iam/security-credentials/PROFILE`;
- the browser interface and profile-selection HTTP API; and
- no promise of region, instance identity, networking, user data, or the full
  EC2 metadata tree.

Upstream explicitly states that its IMDSv2 implementation provides enough
behavior to satisfy credential requests but does not implement all security
measures of the actual EC2 interface. This local service must therefore not be
treated as gaining EC2's workload-isolation properties merely because a
consumer uses IMDSv2.

Unsupported metadata paths and application-specific assumptions are not a
project compatibility promise. Validate any application that requires more
than the credential paths. The official
[Metadata Credential Service](https://mmmorris1975.github.io/aws-runas/metadata_credentials.html)
documentation is authoritative for upstream protocol behavior.

## Failure behavior

- If the user broker is unavailable, the privileged socket can still accept or
  attempt a connection, but forwarding to `127.0.0.1:18080` fails and the CLI
  reports the metadata service unavailable or unhealthy.
- If the endpoint answers but upstream authentication or STS fails, profile
  selection returns an unexpected broker response. This is not an endpoint
  routing failure.
- If no profile is selected, `/profile` reports the upstream no-profile state;
  `aws-metadata status` translates it to a healthy running service with
  `profile: null`.
- Native managers restart failed broker processes, but active profile selection
  is in-process state and returns to empty after broker restart.
- `aws-metadata clear` uses that state boundary intentionally: it restarts only
  the developer's broker, waits through the transient forwarding failure, and
  verifies `/profile` reports no selection. The privileged address, socket, and
  proxy remain running.
- The CLI keeps routine error output redacted. Full broker logs remain local
  and potentially sensitive.

See [Troubleshooting](troubleshooting.md) for the diagnostic sequence.

## Global profile and concurrency

The EC2 metadata model exposes one active instance profile. This broker also
has one active upstream profile. Concurrent consumers can race:

1. VS Code observes profile A.
2. A coding agent selects profile B.
3. A later credential refresh by VS Code receives profile B credentials.

The project does not currently implement acquire/release, ownership, TTL,
advisory locking, or enforced isolation. A future cooperative lease design is
tracked separately; it cannot prevent direct HTTP clients from changing the
profile unless all selection is mediated by an enforcing controller.

## State lifecycle

| State | Restart | Reboot | Uninstall |
| --- | --- | --- | --- |
| Native service definitions and installed payload | Retained | Retained | Removed |
| Link-local address and forwarding | Recreated | Recreated | Removed |
| User AWS configuration | Retained | Retained | Preserved |
| Upstream credential and browser caches | Retained, subject to expiration | Retained, subject to provider policy | Preserved |
| Active profile | Cleared | Cleared | Not applicable |

An explicit `aws-metadata clear` has the same effect on active-profile process
state as a broker restart. It does not delete upstream caches or invalidate
credentials already copied into a consumer process.

## Related documentation

- [Security model](security.md)
- [Getting started](getting-started.md)
- [Troubleshooting](troubleshooting.md)
- [Container runtime validation](container-runtimes.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

# Architecture

## Goals

- Preserve the standard EC2 metadata endpoint at `169.254.169.254`.
- Work with applications that do not inherit custom AWS environment variables.
- Keep the server alive independently of terminals.
- Support browser-based SSO and MFA renewal.
- Allow existing personal `runas.sh PROFILE` clients to keep working while the
  team-facing interface uses `aws-metadata use PROFILE`.
- Depend only on `aws-runas`, Bash, curl, and the native service manager.

## Privilege-separated services

The installer copies `aws-runas` into the root-owned
`/usr/local/libexec/aws-metadata-agent` directory, then executes that immutable
copy in a per-user service. The broker is required to have the developer's uid
and listens on `127.0.0.1:18080`. It therefore reads and writes AWS state with
the same identity as an interactive `aws-runas` command.

The public metadata address is a separate network layer:

- macOS: a root LaunchDaemon establishes a `lo0` alias, then launchd owns port
  80 and hands accepted sockets to `/usr/bin/nc` running as `nobody`;
- Linux: a root oneshot service maintains a `/32` address on `lo`, and a
  socket-activated `systemd-socket-proxyd` forwards TCP connections.

The privileged layer knows only two endpoints. It has no AWS environment,
profile, home-directory access, browser logic, or credential parsing.

The unprivileged `aws-metadata` CLI controls the service through the HTTP API
that `aws-runas` already exposes. It never needs to invoke `sudo` during normal
profile changes.

## Authentication flow

1. A caller posts a profile name to `/profile`.
2. A successful response means credentials are ready.
3. HTTP 401 means SAML/OIDC or MFA interaction is required.
4. Human-oriented callers open the metadata browser interface.
5. Automation-oriented callers receive a stable exit code and optional JSON.

## Global profile and concurrency

The EC2 metadata protocol exposes one active instance profile. Therefore, this
service also has one active `aws-runas` profile at a time. Concurrent consumers
can race:

1. VS Code selects profile A.
2. A coding agent selects profile B.
3. A later credential refresh by VS Code receives profile B credentials.

An optional future lease layer could add:

```text
aws-metadata acquire PROFILE --owner ID --ttl SECONDS
aws-metadata release --owner ID
aws-metadata status --json
```

The first version can implement advisory locking in a root-owned runtime file.
Enforcement would require placing a small controller in front of direct
`POST /profile` access or accepting that the lock is cooperative.

## Service lifetime

The macOS broker is a LaunchAgent in the installing user's GUI domain, which
keeps browser authentication in that login session. The Linux broker is a
systemd user service. The installer enables user lingering so it remains
available independently of terminals and records whether lingering was already
enabled so uninstall can restore the prior state.

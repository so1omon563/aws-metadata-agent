# Security notes

For private vulnerability reporting and supported security-fix versions, see
the repository [security policy](../SECURITY.md).

## Metadata credentials are intentionally reachable

The purpose of this service is to let local applications and containers obtain
AWS credentials without explicit environment injection. Any process that can
reach `169.254.169.254` may be able to obtain credentials for the active
profile. Treat untrusted local processes and containers accordingly.

## Privilege boundary

`aws-runas` does not run as root. A wrapper rejects startup unless its effective
uid matches the configured developer uid. This ensures refreshed cache files
remain user-owned and mode `0600` as upstream creates them.

Root is limited to assigning `169.254.169.254` locally and arranging forwarding
of TCP port 80 to `127.0.0.1:18080`. On macOS, launchd owns the privileged
socket and passes accepted connections to the system `nc` command running as
`nobody`; the root address-setup process exits. On Linux, systemd owns the
privileged socket and launches its native socket proxy with filesystem
hardening.

All installed executables used by services are root-owned and referenced by
absolute path. A user-writable `~/bin`, `~/.local/bin`, Homebrew, or other PATH
entry is not executed by a privileged process.

The root-owned configuration file is mode `0644` because the user broker must
read it. It contains the account name, uid, home path, binary path, and local
port—not profiles, credentials, or passwords. Only root can modify it.

## Browser authentication

The macOS broker runs inside the user's GUI launchd domain. Profile selection
through `aws-metadata use` explicitly opens the browser in that user session.
Linux desktop opening uses `xdg-open` or `gio` from the calling command, not the
privileged forwarding service.

## Profile switching

Profile changes are global and unauthenticated on the local metadata HTTP
interface. The convenience is intentional, but callers must not assume their
selected profile remains active indefinitely.

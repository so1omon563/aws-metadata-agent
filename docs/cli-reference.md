# CLI reference

`aws-metadata` controls the installed service and the HTTP API exposed by the
upstream `aws-runas` broker. Normal profile changes do not require `sudo`.

## Commands

| Command | Use it when | Important behavior |
| --- | --- | --- |
| `use PROFILE` | A human is selecting an upstream profile. | Opens the browser when required and waits 300 seconds by default. |
| `profile PROFILE` | Automation is selecting a profile. | Does not open a browser or wait by default; use explicit flags. |
| `clear` | Stop the broker from vending the selected profile to new metadata requests. | Restarts only the user broker when needed and verifies healthy no-profile state. |
| `active-profile` | Show the selected profile in a shell prompt or status bar. | Prints only the exact live profile name; stays silent when there is nothing to display. |
| `status` | Check endpoint and active-profile state. | `profile: null` or “No profile is selected” is healthy after startup. |
| `open` | Open the upstream browser interface. | Opens `http://169.254.169.254`; it does not select a profile. |
| `refresh` | Open the browser interface for its **Refresh Now** control. | Currently the same operation as `open`; the CLI itself does not force refresh. |
| `errors` | Classify recent authentication failures safely. | Reads at most 200 broker log lines and prints redacted summaries for the last 10 matches. |
| `logs` | Deliberately inspect the full live broker log. | Full logs may contain sensitive profile, identity, or credential data. |
| `diagnose` | Check installation and service boundaries. | Tests endpoint, link-local address, broker service, log location, and `aws-runas` in the current `PATH`. |
| `version` | Identify the installed agent release. | Reads the root-owned installed `VERSION`. |
| `setup` | Complete or refresh a Homebrew installation. | Package-only command; conditionally bootstraps `aws-runas`, then runs the privileged installer. |
| `uninstall` | Remove service state for a Homebrew installation. | Package-only command; preserves user-owned AWS configuration and upstream caches. |

Source and direct-release users run `./install.sh` and `./uninstall.sh` from the
reviewed matching release instead of the package-only commands.

## Interactive profile selection

```sh
aws-metadata use example-nonprod
aws-metadata use example-nonprod --wait 600
aws-metadata use example-nonprod --no-open
aws-metadata use example-nonprod --json
```

`use` initially posts the upstream profile name to `/profile`. If upstream
returns an authentication requirement, the command opens the browser and polls
until credentials are ready or the wait expires. When browser interaction is
enabled and the wait is positive, the HTTP request deadline is extended to the
same wait plus a small transport grace period so the caller does not cancel
upstream authentication prematurely.

One narrowly matched upstream SAML transition is retried once: a browser login
can complete and persist its session while the first STS
`AssumeRoleWithSAML` exchange returns HTTP 408. Other broker errors are not
retried broadly.

## Automation profile selection

```sh
aws-metadata profile example-nonprod --no-open --json
aws-metadata profile example-nonprod --open --wait 300 --json
```

`profile` defaults to `--no-open` and a zero-second wait. This makes an
authentication requirement a prompt nonzero result instead of silently
opening a GUI or holding an unattended process. Automation that can involve a
human must opt into both `--open` and a bounded `--wait`.

## Profile exit codes

| Code | State | Meaning |
| ---: | --- | --- |
| 0 | `ready` | Profile selected and credentials are ready. |
| 2 | usage error | Missing profile or invalid option. |
| 3 | `unavailable` | Metadata endpoint could not be reached. |
| 4 | `authentication_required` | Authentication is required and the command is not waiting for it. |
| 5 | `timeout` | The configured interactive authentication wait expired. |
| 6 | `error` | The endpoint answered, but the broker returned an unexpected response. |

JSON output contains stable state, message, and profile fields. Unexpected
broker responses also include a redacted broker classification, the
`aws-metadata errors` command, and the platform log location. Profile names can
still be sensitive even when credential values are absent.

## Active profile for shell prompts

```sh
aws-metadata active-profile
```

When a profile is selected, `active-profile` performs one live request to the
standard IMDS role-name path and prints only its exact user-defined name. It
does not read or print the profile detail object. When no profile is selected,
the endpoint is unavailable, or the 200 ms request ceiling expires, it prints
nothing and exits successfully so a prompt does not become noisy or report a
false command failure. Use `status` when those states must be distinguished.

The lookup is never cached, so a later prompt reflects the broker's current
process state. Set `AWS_METADATA_ACTIVE_PROFILE_TIMEOUT_SECONDS` only when a
different bounded deadline is needed. See
[Shell prompt integration](shell-prompts.md) for Starship, zsh, Bash, and fish
examples.

## Status

```sh
aws-metadata status
aws-metadata status --json
```

Expected healthy no-profile JSON is:

```json
{"state":"running","endpoint":"http://169.254.169.254","profile_name":null,"profile":null}
```

When a profile is active, status reads the user-defined upstream profile name
from the standard IMDS role-name path and preserves the live details returned
by the upstream `/profile` endpoint:

```json
{"state":"running","endpoint":"http://169.254.169.254","profile_name":"example-nonprod","profile":{"auth_url":"","client_id":"","external_id":"","jump_role":"","redirect_uri":"","role_arn":"","username":""}}
```

No profile name or detail object is persisted by the agent. If the live
role-name request is unavailable, `profile_name` is `null` while the available
profile details remain visible. The `profile` object can include role or
authentication URLs. Do not treat status output as safe to paste into a public
issue.

## Clear the active profile

```sh
aws-metadata clear
aws-metadata clear --wait 30 --json
```

`clear` is idempotent. If no profile is selected, it exits successfully
without restarting anything. Otherwise it restarts only the unprivileged
broker through the user's launchd or systemd manager, tolerates the expected
brief endpoint outage, and succeeds only after `/profile` reports healthy
no-profile state. It does not require `sudo` and leaves privileged address and
forwarding services running.

The command never prints the previous profile name. A successful JSON response
is:

```json
{"state":"clear","message":"AWS metadata profile cleared."}
```

Clearing is not credential revocation. Applications can continue using
credentials they already fetched until those credentials expire. Upstream role
credential caches and browser sessions remain under the user's ownership, and
another local caller can select a profile again immediately.

| Code | Meaning |
| ---: | --- |
| 0 | No profile is selected, either already or after the broker restart. |
| 2 | Invalid arguments or an unsupported operating system. |
| 3 | The metadata endpoint was unavailable before any restart was attempted. |
| 5 | The broker did not return in the configured wait period. |
| 6 | The restart failed, the endpoint returned an unexpected state, or another caller selected a profile during clearing. |

## Diagnostics and logs

```sh
aws-metadata diagnose
aws-metadata errors
aws-metadata logs
```

Use `diagnose` for service boundaries and `errors` for a bounded redacted view
of authentication failures. Use `logs` only when full local inspection is
necessary:

- macOS: `~/Library/Logs/aws-metadata-agent.log`;
- Linux: systemd user journal for `aws-metadata-agent.service`.

On macOS, a Homebrew setup may bootstrap `aws-runas` to `~/.local/bin` before
that directory is in the current shell's `PATH`. In that case `diagnose` can
flag only the interactive path lookup while the root-owned installed copy and
service remain healthy. Confirm `~/.local/bin/aws-runas` and configure the
shell path.

## Environment overrides

The CLI supports bounded diagnostic and test overrides:

| Variable | Purpose | Default |
| --- | --- | --- |
| `AWS_METADATA_URL` | Metadata base URL, primarily for an unprivileged test broker. | `http://169.254.169.254` |
| `AWS_METADATA_WAIT_SECONDS` | Default selection wait. | `300` for `use`, `0` for `profile` |
| `AWS_METADATA_CLEAR_WAIT_SECONDS` | Default wait for the broker to return after `clear`. | `15` |
| `AWS_METADATA_REQUEST_TIMEOUT` | Explicit HTTP request deadline. | `15`, extended for interactive waits |
| `AWS_METADATA_CONNECT_TIMEOUT` | Endpoint connection timeout. | `2` |

After a full supported install, applications and routine CLI use should not
need a custom metadata endpoint.

## Related documentation

- [Getting started](getting-started.md)
- [Troubleshooting](troubleshooting.md)
- [Architecture](architecture.md)
- [Stream Deck integration](stream-deck.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

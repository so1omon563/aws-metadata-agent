# CLI reference

`aws-metadata` controls the installed service and the HTTP API exposed by the
upstream `aws-runas` broker. Normal profile changes do not require `sudo`.

## Commands

| Command | Use it when | Important behavior |
| --- | --- | --- |
| `use PROFILE` | A human is selecting an upstream profile. | Opens the browser when required and waits 300 seconds by default. |
| `profile PROFILE` | Automation is selecting a profile. | Does not open a browser or wait by default; use explicit flags. |
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

## Status

```sh
aws-metadata status
aws-metadata status --json
```

Expected healthy no-profile JSON is:

```json
{"state":"running","endpoint":"http://169.254.169.254","profile":null}
```

When a real profile is active, `status --json` can include upstream profile
fields such as role or authentication URLs. Do not treat that output as safe
to paste into a public issue.

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

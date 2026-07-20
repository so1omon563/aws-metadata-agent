# Troubleshooting

Troubleshoot one boundary at a time: package command, native services,
metadata endpoint, upstream profile, browser authentication, credential
provider chain, and finally the consuming application.

## Command not found

Check the package-managed agent command and upstream dependency separately:

```sh
command -v aws-metadata
command -v aws-runas
test -x "$HOME/.local/bin/aws-runas" && printf '%s\n' "$HOME/.local/bin/aws-runas"
```

Homebrew commonly provides `/opt/homebrew/bin/aws-metadata` on Apple Silicon.
Setup may bootstrap upstream to `~/.local/bin/aws-runas`; that path is
immediately discoverable by the installer even if the current shell does not
yet include it. Add `~/.local/bin` to the login shell's `PATH` or use the
reviewed release bootstrap's `--configure-shell` option.

## Service installed but endpoint unavailable

Run:

```sh
aws-metadata diagnose
aws-metadata status
```

`diagnose` checks the link-local address and user broker independently. On
macOS, complete forwarder errors are in
`/var/log/aws-metadata-agent-forwarder.log`; broker errors are in
`~/Library/Logs/aws-metadata-agent.log`. On Linux, inspect the system units and
user broker separately:

```sh
systemctl status aws-metadata-agent-address.service aws-metadata-agent.socket
systemctl --user status aws-metadata-agent.service
```

If setup or install stopped partway through, rerun the same matching operation
first:

```sh
# Homebrew package
aws-metadata setup

# Extracted direct/source release
./install.sh
```

Reinstalling the same release is supported and replaces service payloads and
definitions before reloading them. If rerunning fails and clean removal is
required, use `aws-metadata uninstall` for Homebrew or `./uninstall.sh` from
the matching release, then confirm with `aws-metadata diagnose` or host service
tools. Do not start by manually deleting individual units or root-owned files;
that can hide the original boundary and leave partial state.

## Running with no active profile

Immediately after first setup, broker restart, or reboot:

```text
AWS metadata service is running at http://169.254.169.254.
No profile is selected.
```

That state is expected. Select an upstream profile again:

```sh
aws-metadata use example-nonprod
```

## Profile not found or upstream profile fails

List standard AWS configuration names and test upstream directly:

```sh
aws configure list-profiles
/usr/local/libexec/aws-metadata-agent/aws-runas -r example-nonprod /usr/bin/true
printf 'exit=%s\n' "$?"
```

The installed root-owned copy still executes as the developer. If this direct
command fails similarly, investigate the upstream profile, identity provider,
or AWS STS exchange using the authoritative
[aws-runas documentation](https://mmmorris1975.github.io/aws-runas/). Do not
share `-v` or `-vv` output without reviewing and redacting it; upstream warns
that verbose diagnostics may contain AWS credentials.

## Endpoint responds but profile selection fails

An HTTP 500 or another unexpected response from `aws-metadata use` means the
metadata endpoint answered, but the broker could not complete the request. It
is not evidence that the link-local endpoint is unavailable.

```sh
aws-metadata diagnose
aws-metadata errors
```

`errors` reads a bounded recent window and emits fixed redacted classifications.
If the installed direct upstream command succeeds while the agent path fails,
retain browser and role-cache state and report the comparison as an agent-path
problem. Do not delete caches before collecting that bounded evidence.

## Browser does not open or authentication times out

Use the human-oriented command and an explicit wait:

```sh
aws-metadata use example-nonprod --wait 600
```

Check these boundaries:

1. Confirm the direct installed `aws-runas` command can authenticate.
2. On macOS, if the `saml_provider = browser` session cannot start or complete,
   check **System Settings -> Privacy & Security -> App Management** for the
   verified `aws-runas` entry. This permission is conditional browser-provider
   troubleshooting, not an installation prerequisite.
3. Confirm the browser was not closed before authentication completed.
4. Allow enough time for password expiry, account recovery, or MFA.
5. Inspect only `aws-metadata errors` before opening the complete sensitive log.

A successful browser login and the AWS STS credential exchange are separate
steps. The browser can persist its session even if the first STS request fails.
The agent retries one confirmed SAML STS 408 transition once; unrelated errors
are not retried.

## Credentials are for the wrong role

Check both global selection and the consumer's provider precedence:

```sh
aws-metadata status
env | grep '^AWS_'
```

Do not paste the output of a real `status --json` object or real environment
credentials into an issue. Another local caller may have changed the one
globally active profile. Alternatively, the consumer may be using explicit
environment credentials, a named profile, SSO, shared credentials,
`credential_process`, web identity, or container credentials before IMDS.

Use the isolated identity test in
[Getting started](getting-started.md#5-prove-an-aws-client-uses-metadata).

## CLI works but a GUI application fails

- Configure the GUI with the optional `local-metadata` consumer profile if it
  requires a selectable name.
- Confirm the application has not disabled IMDS.
- Restart the GUI after changing AWS configuration if it caches profiles.
- For automation, use the absolute package-managed `aws-metadata` path rather
  than relying on a GUI process's `PATH`.
- Verify the exact SDK or application provider chain; support varies.

See [Consumer recipes](consumers.md).

## Host works but a container fails

Run a credential-free reachability check from the exact runtime and network
mode. Link-local routing may be forwarded to the host, intercepted by a cloud
metadata proxy, or dropped. The installer does not modify Docker, Podman,
Kubernetes, CNI, or VM networking.

See [Container runtime validation](container-runtimes.md) before adding a
custom route or endpoint override; those workarounds can diagnose a problem but
do not prove transparent EC2 metadata compatibility.

## Profile changes unexpectedly

This is the documented global-profile model, not isolation failure. Stream
Deck actions, VS Code, scripts, containers, and coding agents all change the
same active broker profile. The most recent successful selection wins. The
project does not currently implement leases or per-consumer locks.

## Sensitive diagnostic material

- `aws-metadata errors` is bounded and redacted.
- `aws-metadata logs` is complete and potentially sensitive.
- Profile names, role ARNs, authentication URLs, account IDs, and identity
  output can all be organization-specific.
- Upstream verbose output may contain credentials.
- Keep temporary GUI-automation logs in the user's private `TMPDIR` and remove
  them after use.

## Related documentation

- [CLI reference](cli-reference.md)
- [Architecture](architecture.md)
- [Security model](security.md)
- [Upgrades and rollback](upgrades.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

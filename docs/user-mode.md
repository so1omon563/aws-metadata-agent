# macOS user mode

User mode runs the credential broker entirely in the signed-in macOS account.
It is intended for managed Macs where organizational policy blocks the
administrator step required by the transparent system endpoint.

| Mode | Endpoint | Administrator access | Consumer setup | Containers |
| --- | --- | --- | --- | --- |
| User | `127.0.0.1:18080` | None | Select `local-metadata` or explicitly configure a loopback endpoint | Not supported |
| System | `169.254.169.254:80` | Required during setup | Transparent to the default IMDS chain | Runtime-specific validated paths |

The modes are explicit and mutually exclusive. Setup never treats blocked
elevation as permission to install a different mode.

## Set up user mode

Install the Homebrew package, then request user mode:

```sh
brew trust --tap so1omon563/aws-metadata-agent
brew tap so1omon563/aws-metadata-agent
brew install aws-metadata-agent
aws-metadata setup --mode user
```

Setup conditionally bootstraps the pinned `aws-runas` release, writes a user
LaunchAgent, and starts one `aws-runas serve ecs` listener on
`127.0.0.1:18080`. Upstream ECS mode also registers its IMDS credential
routes, so user mode does not run a second broker.

No `sudo`, root-owned path, system LaunchDaemon, link-local alias, privileged
port, or global launch environment is used. If system mode is already present,
setup stops and asks you to remove it explicitly.

Confirm the empty startup state:

```sh
aws-metadata status
aws-metadata diagnose
```

## Connect applications

Setup appends one marked, project-owned profile to `~/.aws/config`:

```ini
[profile local-metadata]
credential_process = "/absolute/package/path/aws-metadata" _credential-process
```

The internal command asks the local broker for the active profile name, then
uses the pinned upstream `aws-runas` process-credential output for that
profile. It does not write temporary credentials to the AWS files. Existing
config content, file permissions, and a config symlink are preserved.

Select an upstream role globally, then use the compatibility profile:

```sh
aws-metadata use example-nonprod
aws --profile local-metadata sts get-caller-identity
```

Select `local-metadata` in the AWS Toolkit for Visual Studio Code. For the
Terraform AWS provider, set `profile = "local-metadata"` or use the equivalent
profile selection already present in the project.

Applications that support explicit endpoint environment settings may instead
use either protocol exposed by the same listener:

```sh
AWS_CONTAINER_CREDENTIALS_FULL_URI=http://127.0.0.1:18080/credentials command
AWS_EC2_METADATA_SERVICE_ENDPOINT=http://127.0.0.1:18080 command
```

Those variables must reach the application process. GUI applications commonly
do not inherit an interactive shell environment, which is why the named
process profile is the supported default for user mode. Explicit credentials,
SSO, web identity, shared credential entries, and other earlier providers can
still take precedence.

Loopback is host-local. A container's `127.0.0.1` is the container itself, not
the macOS host, so user mode makes no container-routing claim. Use system mode
when a validated transparent container path is required.

## Lifecycle and ownership

Profile selection, status, browser access, refresh, clear, logs, and errors use
the loopback endpoint automatically while the user-mode marker exists:

```sh
aws-metadata use example-nonprod
aws-metadata active-profile
aws-metadata clear
```

After a Homebrew upgrade, refresh the versioned LaunchAgent target explicitly:

```sh
brew upgrade aws-metadata-agent
aws-metadata setup --mode user
```

Repeated setup is supported. To remove only user mode:

```sh
aws-metadata uninstall --mode user
```

Uninstall stops the user LaunchAgent, removes user-mode installer state, and
removes only the marked `local-metadata` block. It preserves unrelated AWS
configuration, upstream caches, broker logs, the Homebrew package, and all
system-mode paths.

## Security boundary

The loopback listener is not an authorization boundary. Processes in the
developer account can request the active credentials or change the global
profile through the local HTTP API. A successful profile change affects every
consumer, and credentials already fetched remain usable until they expire.

Use `aws-metadata clear` after finishing sensitive work, and do not enable user
mode when untrusted local workloads share the account.

## Related documentation

- [Getting started](getting-started.md)
- [Consumer recipes](consumers.md)
- [Security model](security.md)
- [Upgrades and uninstall](upgrades.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

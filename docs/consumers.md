# Consumer recipes

This page shows how to connect AWS CLI, SDKs, profile-oriented applications,
containers, coding agents, and GUI automation to the metadata endpoint.

Every consumer sees the one globally active agent profile. A consumer does not
reserve the profile it first observed, and an optional consumer compatibility
profile does not provide locking. If another process selects a different
upstream profile, later credential refreshes receive the new identity.

## AWS CLI through the default chain

After selecting an upstream profile:

```sh
aws-metadata use example-nonprod
aws sts get-caller-identity --region us-east-1
```

That ordinary command is representative, but success alone does not prove the
CLI used metadata. AWS CLI command options, environment variables, role and
web-identity settings, IAM Identity Center, shared credentials,
`credential_process`, and container credentials all precede IMDS.

In macOS user mode, setup owns the default `credential_process`; in system
mode, the chain continues to standard IMDS. Neither mode requires a synthetic
profile for ordinary default-chain commands.

Use the provider-isolated verification in
[Verification](verification.md#4-metadata-credential-path) when
proving the integration. It makes an AWS STS request and prints identity
information; verify the expected role locally and do not publish real output.

## Profile-oriented consumers

Some integrations require a named AWS profile. The AWS Toolkit for Visual
Studio Code is one example. Select the consumer profile for the installed mode:

| Agent mode | Select in the AWS Toolkit | Credential provider |
| --- | --- | --- |
| macOS user mode | `default` | Project-owned `credential_process` |
| System mode | `local-metadata` | EC2 instance metadata |

User-mode setup creates the marked provider in `[default]`; do not add another
profile for the Toolkit:

```ini
[default]
credential_process = "/absolute/package/path/aws-metadata" _credential-process
```

System mode instead uses this optional compatibility profile:

```ini
[profile local-metadata]
region = us-west-2
credential_source = Ec2InstanceMetadata
```

In both modes, select the real upstream role through the agent first:

```sh
aws-metadata use example-nonprod
```

Then choose `default` or `local-metadata` from the AWS Toolkit connection
picker according to the table. Do not select `example-nonprod` in the Toolkit
merely because it is active; that is the upstream profile passed to the agent,
not the consumer connection.

The names have different jobs:

- `example-nonprod` is an upstream `aws-runas` profile and the value passed to
  `aws-metadata use`;
- `default` asks the user-mode process provider for whichever profile is active;
- `local-metadata` asks the consumer to retrieve whichever credentials are
  currently exposed by system-mode EC2 metadata.

`local-metadata` is not one-to-one with a role and must not add a `role_arn`
merely to appear complete. Adding one would ask the consumer to assume another
role after retrieving the already selected credentials. Standalone
`credential_source` behavior varies among SDKs and tools; use this pattern only
for an integration known to support it.

See [Configure aws-runas](aws-runas-configuration.md#named-metadata-profile-for-profile-oriented-tools)
for the full portability boundary and official AWS references.

### Validate an AWS Toolkit connection

1. Record the installed VS Code and AWS Toolkit versions.
2. Run `aws-metadata use example-nonprod`.
3. Choose `default` in user mode or `local-metadata` in system mode.
4. Open an AWS Toolkit view that makes a permitted AWS request and confirm the
   expected account and role locally.
5. Select a different non-production upstream profile, then refresh or
   reconnect the Toolkit connection so it requests credentials again.
6. Confirm the Toolkit now uses the second identity while its selected
   consumer profile remains `default` or `local-metadata`.

The Toolkit and its AWS SDK can retain credentials until they expire. A stale
identity immediately after `aws-metadata use` is not proof that selection
failed; refresh or reconnect the Toolkit before comparing the provider paths.
Do not publish account IDs, role names, real profile names, Toolkit logs, or
authentication output from this check.

## Generic SDKs and tools

In system mode, applications that use an AWS SDK's default credential provider
chain should use the standard endpoint with no project-specific configuration:

```text
http://169.254.169.254
```

Check the specific SDK's provider chain and settings:

- `AWS_EC2_METADATA_DISABLED` must not disable IMDS;
- explicit credentials, profiles, web identity, container credentials, and
  in-code providers may take precedence;
- a custom `AWS_EC2_METADATA_SERVICE_ENDPOINT` is unnecessary after a full
  install and can hide routing problems; and
- SDK support for IMDS providers and standalone `credential_source` varies.

In macOS user mode, applications use the default profile. Advanced host
applications may explicitly inherit
`AWS_CONTAINER_CREDENTIALS_FULL_URI=http://127.0.0.1:18080/credentials` or
`AWS_EC2_METADATA_SERVICE_ENDPOINT=http://127.0.0.1:18080`, but shared endpoint
support and GUI environment inheritance vary. See
[macOS user mode](user-mode.md).

AWS documents the shared model in
[standardized credential providers](https://docs.aws.amazon.com/sdkref/latest/guide/standardized-credentials.html),
but the SDK- or tool-specific guide remains authoritative.

Terraform's AWS provider, coding agents, and similar tools may use an AWS SDK
credential chain, but this project does not claim that every version or custom
provider configuration is independently validated. Prove the exact consumer
and watch for global-profile changes during long-running operations.

## Containers

System mode provides the transparent container path at `169.254.169.254`.
Starting with
[`so1omon/tf_image:v1.0.2`](https://github.com/so1omon563/tf-image-build/releases/tag/v1.0.2),
the maintained Terraform image detects a healthy macOS user-mode broker and
configures:

```text
AWS_EC2_METADATA_SERVICE_ENDPOINT=http://host.docker.internal:18080
```

No copied `tf_image` or `tg_ci.sh` launcher change is required. An explicitly
supplied endpoint remains authoritative, and the image retains standard IMDS
behavior when user mode is unavailable. A container cannot reach the host
service through its own `127.0.0.1`, and arbitrary unmodified images do not
discover user mode. Do not inject AWS credential values or mount AWS
configuration for either path.

Docker Desktop on the supported Apple Silicon macOS host and default-bridge
Docker Engine routing on a GitHub-hosted Ubuntu runner have distinct evidence.
Podman, Kubernetes, rootless networking, CNIs, and cloud metadata interception
remain runtime-specific and unverified. Follow
[Container runtime validation](container-runtimes.md) for reproducible
connectivity checks and the exact claim boundary.

Any container that can reach the address may obtain the active credentials.
Do not expose it to untrusted images or workloads without accepting that risk.

## GUI and command automation

Call the stable package-managed CLI with an absolute path. GUI applications
may not inherit an interactive shell's `PATH`, and Homebrew Cellar paths change
across upgrades:

```sh
command -v aws-metadata
/opt/homebrew/bin/aws-metadata profile example-nonprod --open --wait 300 --json
```

The [Stream Deck guide](stream-deck.md) documents one validated automation
path, including output capture, browser behavior, and security considerations.
Avoid rapid or conflicting profile actions: there is no per-consumer lock, and
the most recent successful selection wins.

## Related documentation

- [Getting started](getting-started.md)
- [Configure aws-runas](aws-runas-configuration.md)
- [CLI reference](cli-reference.md)
- [Security model](security.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

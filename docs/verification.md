# Verification

Use this checklist after installation or upgrade to prove each boundary in
order. Stop at the first failure and follow the linked troubleshooting path;
later checks depend on earlier ones.

## 1. Package and service

Confirm the installed version and native service state:

```sh
aws-metadata version
aws-metadata status
aws-metadata diagnose
```

The service should be running at `http://169.254.169.254`. A new or restarted
broker may report no selected profile; that is healthy. If the command is
missing or the endpoint is unavailable, start with
[Troubleshooting](troubleshooting.md#choose-the-failing-symptom).

## 2. Upstream profile

Test the real `aws-runas` profile without involving the metadata service:

```bash
if command -v aws-runas >/dev/null 2>&1; then
  aws_runas=$(command -v aws-runas)
else
  aws_runas="$HOME/.local/bin/aws-runas"
fi
test -x "$aws_runas"
"$aws_runas" -r example-nonprod /usr/bin/true
printf 'exit=%s\n' "$?"
```

Exit `0` means upstream obtained credentials. A nonzero result belongs to the
upstream profile, identity provider, or AWS STS boundary; fix that before
diagnosing the agent. Browser-backed profiles may open an authentication
session.

## 3. Profile selection

Select the same upstream profile through the agent:

```sh
aws-metadata use example-nonprod
aws-metadata status
```

Expected selection output is:

```text
AWS metadata profile set to example-nonprod.
```

If authentication can take longer because of password recovery or MFA, use:

```sh
aws-metadata use example-nonprod --wait 600
```

## 4. Metadata credential path

AWS tools stop at the first valid provider. This command removes the common
competing providers, leaves IMDS enabled, and makes one AWS STS identity
request:

```sh
env \
  -u AWS_PROFILE \
  -u AWS_DEFAULT_PROFILE \
  -u AWS_ACCESS_KEY_ID \
  -u AWS_SECRET_ACCESS_KEY \
  -u AWS_SESSION_TOKEN \
  -u AWS_SECURITY_TOKEN \
  -u AWS_ROLE_ARN \
  -u AWS_WEB_IDENTITY_TOKEN_FILE \
  -u AWS_CONTAINER_CREDENTIALS_FULL_URI \
  -u AWS_CONTAINER_CREDENTIALS_RELATIVE_URI \
  -u AWS_EC2_METADATA_SERVICE_ENDPOINT \
  AWS_CONFIG_FILE=/dev/null \
  AWS_SHARED_CREDENTIALS_FILE=/dev/null \
  AWS_EC2_METADATA_DISABLED=false \
  aws sts get-caller-identity --region us-east-1
```

Confirm locally that the response identifies the expected account and assumed
role. It contains identity information rather than credentials, but that
identity may still be organization-sensitive. Do not paste real output into a
public issue or log.

## 5. Application boundary

The core service is verified when steps 1 through 4 pass. Then test only the
consumer you intend to use:

- Default-chain AWS CLI and SDK users need no additional profile.
- Profile-oriented tools such as the AWS Toolkit for Visual Studio Code may
  need the `local-metadata` compatibility profile in
  [Consumer recipes](consumers.md#profile-oriented-consumers).
- Containers require a runtime-specific reachability check from
  [Container runtime validation](container-runtimes.md).
- Stream Deck automation has a separate
  [verification procedure](stream-deck.md#verify-the-action).

Do not treat an optional consumer failure as evidence that the already-proven
host metadata path is broken. Isolate the consumer's routing and credential
provider chain.

## Done criteria

- [ ] The package reports the intended installed version.
- [ ] Native service diagnostics pass and the endpoint is reachable.
- [ ] The upstream profile succeeds directly.
- [ ] The agent selects that profile.
- [ ] The isolated AWS identity request returns the expected role.
- [ ] Each required optional consumer passes its own check.

[Troubleshoot a failed check](troubleshooting.md) | [Back to the documentation index](README.md) | [Back to the project README](../README.md)

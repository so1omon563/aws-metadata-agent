# Security policy

## Supported versions

Security fixes are made against the latest release line.

| Version | Supported |
| --- | --- |
| Latest tagged release | Yes |
| Older releases or unreleased builds | No |

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use
[GitHub private vulnerability reporting](https://github.com/so1omon563/aws-metadata-agent/security/advisories/new)
instead.

Include the affected version and platform, the expected impact, reproduction
steps, and any known mitigation. Do not include AWS credentials, account IDs,
profile names, identity output, browser-authentication material, or other
sensitive data. Redacted diagnostics are preferred.

Reports will be reviewed as soon as practical. Please allow time to validate
and address the issue before public disclosure, and coordinate disclosure
through the private advisory.

This repository covers vulnerabilities in `aws-metadata-agent` and in the way
it integrates with `aws-runas`. Vulnerabilities that affect `aws-runas`
independently should be reported to the
[upstream project](https://github.com/mmmorris1975/aws-runas). If the agent's
installation or forwarding design makes an upstream behavior exploitable,
report it here as well.

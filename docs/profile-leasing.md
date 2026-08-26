# Cooperative profile leasing design

Status: proposed design for an optional advisory layer; no lease commands or
enforcing controller are implemented.

This document defines how cooperating local tools could coordinate use of the
one globally active `aws-runas` profile. It does not turn the metadata endpoint
into an authorization boundary, isolate consumers, or revoke credentials that
have already been issued.

## Decision

The first lease layer, if implemented, must be **advisory and opt-in**.

- A live lease blocks conflicting profile-changing commands made through
  `aws-metadata` unless the caller proves lease ownership or explicitly forces
  an override.
- Existing `use`, `profile`, `clear`, `refresh`, status, and credential-provider
  workflows remain unchanged when no live lease exists.
- The browser interface, direct `POST /profile`, direct `aws-runas` use, and
  other upstream HTTP routes do not participate. They can bypass or invalidate
  the holder's expectation without changing the lease record.
- A lease is coordination metadata, not proof that a profile stayed selected
  and not permission to retrieve credentials.

Enforcement is deferred. Honest enforcement would require a controller to own
the exposed port, move `aws-runas` behind a private second endpoint, proxy the
complete browser, authentication, EC2, ECS, and IMDSv2 surface, and authenticate
every profile-changing route. That would replace today's transparent protocol
forwarding with a new security-critical HTTP component and would require an
upstream-compatible way for the browser interface to carry lease authority.

## Current constraints

| Constraint | Consequence for leasing | Source |
| --- | --- | --- |
| `aws-metadata` sends a plain profile name directly to upstream `POST /profile`. | The current CLI has no ownership or compare-and-set operation. | `bin/aws-metadata:488-528`, `bin/aws-metadata:560-688` |
| The supervisor ultimately replaces itself with `aws-runas`, which owns `127.0.0.1:18080`. | There is no agent-controlled request path on which to enforce a lease. | `libexec/aws-metadata-server:177-189` |
| System-mode forwarding sends accepted connections to that same loopback port. | A host process or reachable container can bypass the CLI. | `docs/architecture.md:145-157` |
| The browser and common HTTP API can select the global profile without authentication. | An advisory lease cannot prevent an upstream browser or API override. | `docs/security.md:50-59` |
| Broker restart clears active-profile process state. | A lease must also become invalid when the broker generation changes. | `docs/architecture.md:215-235` |
| Upstream ECS mode supports a profile-specific credential route. | A lease cannot be described as credential authorization, even when active selection is unchanged. | [Upstream metadata service](https://mmmorris1975.github.io/aws-runas/metadata_credentials.html#ecs-metadata-service) |

## Proposed advisory contract

### Commands

An implementation should add one command group and one option shared by
profile-changing commands:

```text
aws-metadata lease acquire --owner OWNER --ttl DURATION
aws-metadata lease status [--json]
aws-metadata lease renew --token-file PATH --ttl DURATION
aws-metadata lease release --token-file PATH

aws-metadata use PROFILE --lease-token-file PATH
aws-metadata profile PROFILE --lease-token-file PATH
aws-metadata clear --lease-token-file PATH
aws-metadata use PROFILE --force
```

`acquire` creates a token file inside the agent's private runtime directory and
returns its path. The token itself must never be accepted on the command line,
printed, logged, or included in JSON. The caller can pass the file path to a
child process or remove the file after release.

Acquiring a lease does not select, clear, or verify a profile. It reserves only
the cooperative right to make the next profile-changing CLI operation. This
keeps acquisition atomic and separate from authentication, which may require a
browser and a long bounded wait.

`refresh` does not require lease ownership because it reselects the already
active profile as part of credential renewal. It must not change the lease
owner, duration, or expiry. Read-only commands and credential requests also do
not require lease ownership.

### Acquire

1. Validate the owner label and TTL before touching state.
2. Take the lease-state lock with an atomic filesystem operation.
3. Reject an existing unexpired lease.
4. Remove malformed, expired, or prior-broker-generation state.
5. Generate at least 128 bits of random token material.
6. Write the token to a new mode `0600` file and store only its SHA-256 digest
   in the lease record.
7. Atomically publish the lease record, then release the state lock.

The owner is a diagnostic label, not an authenticated OS or process identity.
It must be valid UTF-8, one line, and at most 64 bytes. Process IDs are not
owners because a lease commonly outlives the command that acquired it and PIDs
can be reused.

### Release and renew

- `release` succeeds only when the supplied token digest matches the live
  lease. Releasing an already absent or expired lease is idempotent success.
- `release` removes coordination state only. It does not clear the active
  profile or revoke credentials.
- `renew` requires the matching token before expiry and sets a new expiry from
  the current time. There is no post-expiry grace period.
- A failed or interrupted state update leaves either the complete old record or
  the complete new record, never a partial record.
- A holder should still release in its normal cleanup path. TTL is the recovery
  mechanism for crashes and abandoned automation.

### TTL

- Default: 15 minutes.
- Minimum: 1 second.
- Maximum: 24 hours.
- Stored form: decimal acquisition and expiry Unix timestamps plus the broker
  generation identifier.
- Every lease-aware operation lazily removes expired or impossible state. An
  expiry beyond the maximum allowed interval is malformed and is removed.

Wall-clock changes can shorten or extend an advisory lease. The strict maximum,
validation on every operation, broker-generation reset, and explicit force
path bound the resulting local availability impact. A future implementation
may use a portable boot-relative clock only if both supported platforms can
expose it without adding a privileged or persistent service.

Expiry removes coordination state only. It does not clear the active profile.
A successful `clear`, auto-clear expiry, broker crash, or service restart starts
a new broker generation and invalidates the lease and its token file.

### Force override

`--force` is an explicit cooperative escape hatch. It removes the current
lease under the state lock, reports the displaced owner and expiry without
printing a profile name or token, and then performs the requested profile
change. Automation must opt in on every forced operation; no environment
variable or persistent setting may make force implicit.

A direct HTTP or browser selection is already an out-of-band override. Because
the advisory layer cannot identify that caller, it neither labels the action as
forced nor claims to detect it.

## State and ownership

The installing developer UID owns the lease state. The root forwarding layer
must never read, write, or enforce it.

| Platform | Private runtime directory |
| --- | --- |
| macOS | `~/Library/Application Support/aws-metadata-agent/runtime` |
| Linux | `${XDG_RUNTIME_DIR}/aws-metadata-agent`, with `~/.local/state/aws-metadata-agent/runtime` as the documented fallback |

The directory is mode `0700`. The lease record, lock metadata, broker
generation, and generated token files are mode `0600`. Implementations must
reject symlinks, non-regular files, unexpected owners, group/world access, and
records above a small fixed size before parsing.

The record contains only:

- schema version;
- opaque lease ID;
- diagnostic owner label;
- SHA-256 token digest;
- acquisition and expiry timestamps; and
- broker generation identifier.

It must not contain a profile name, profile details, AWS identity, credential,
authentication URL, account identifier, process environment, or raw token.

At every broker start the unprivileged supervisor creates a new random
generation identifier and removes any prior lease record and token file. This
matches the existing rule that restart clears the active profile. The holder's
next operation then sees no lease and must acquire again.

## Threat model

### Protected assets and objectives

- Reduce accidental profile changes among cooperating tools.
- Keep lease tokens and owner metadata private from other local UIDs.
- Bound stale coordination state after holder failure.
- Preserve the integrity of user-owned state without adding root access.
- Keep the existing credential-exposure and one-global-profile model explicit.

The lease does **not** protect credentials from a process that can reach the
metadata service. It also does not isolate two processes running as the same
developer UID, authenticate direct HTTP callers, or revoke cached STS
credentials.

### Actors and trust boundaries

| Actor | Starting capability | Lease boundary |
| --- | --- | --- |
| Cooperative holder | Can run the CLI and read its private token file. | May renew, release, or change the profile while its lease is live. |
| Cooperative non-holder | Can run the CLI but lacks the token. | Profile-changing CLI commands fail unless `--force` is explicit. |
| Other local UID, routed container, or SSRF-capable service | May reach the metadata endpoint but cannot normally read mode `0600` lease state. | Can bypass an advisory lease through upstream HTTP and may retrieve credentials allowed by that endpoint. |
| Untrusted code under the developer UID | Can read or alter the developer's files and call the endpoint. | Already has enough authority to steal a token, alter state, or bypass the CLI; the lease adds no same-UID security boundary. |
| Installing developer | Owns configuration, profiles, and lease state. | May use explicit force and is responsible for choosing a non-sensitive owner label. |
| Root forwarding layer | Can expose or forward the system-mode socket. | Must remain unaware of lease state and AWS identity. |

### Prioritized attacker stories

These are design hypotheses, not confirmed vulnerabilities.

| Priority | Scenario and capability gain | Existing control and mitigation |
| --- | --- | --- |
| High | A reachable local process ignores the lease and posts another profile. A trusted consumer may later act with the wrong active identity. | This is an existing accepted endpoint capability. Label leasing advisory, keep direct-access warnings prominent, and require a controller before making an enforcement claim. |
| High | A caller treats a lease as credential authorization even though metadata and ECS profile-specific routes remain reachable. | State explicitly that leases coordinate selection only and do not restrict credential retrieval, cached credentials, or alternate upstream routes. |
| Medium | A crashed holder leaves cooperating tools blocked. | Use bounded TTL, lazy expiry, broker-generation invalidation, idempotent release, and explicit force. |
| Medium | A clock rollback or malformed future expiry extends a stale lease. | Cap TTL at 24 hours, validate timestamps on every operation, and remove impossible records. |
| Medium | A filesystem race replaces lease state or redirects a token write. | Use a private directory, atomic creation and replacement, strict ownership/mode checks, regular-file checks, bounded parsing, and no root consumer. |
| Low | A token leaks through command history, logs, JSON, or process listings. | Pass only a mode `0600` token-file path; never accept or print raw token material. |
| Low | Same-UID malicious code forges ownership or denies service to cooperative tools. | Do not claim same-UID isolation. That code can already call the endpoint and access the developer's files; the lease grants no meaningful new authority. |

## Direct selection and enforcement threshold

The advisory design deliberately preserves the upstream service and existing
simple workflow. Its tradeoff is that it cannot make a selected profile stable
against non-cooperating callers.

An enforcing design is a separate product change and must meet all of these
gates before implementation:

1. The agent controller, not `aws-runas`, owns every exposed TCP listener.
2. Upstream listens only on a private second endpoint that untrusted callers
   cannot reach directly.
3. The controller proxies and regression-tests every supported browser,
   authentication, refresh, EC2, ECS, and IMDSv2 route without logging secrets.
4. Every profile-changing route, including the browser interface, carries
   authenticated lease authority or an explicit audited override.
5. Legacy clients without lease support retain credential retrieval but cannot
   silently change selection while enforcement is enabled.
6. The controller is threat-modeled and reviewed as a new credential-bearing
   network boundary on both supported platforms.

Even that controller would protect only selection integrity. It would not
create per-consumer AWS identity isolation while every consumer shares one
metadata credential surface.

## Implementation gate

Before adding lease commands, require evidence of at least one real concurrent
workflow that benefits from cooperative blocking and can carry a token-file
path. Implementation must include:

- credential-free tests for atomic acquire, conflict, renew, release, expiry,
  crash recovery, broker restart, malformed state, filesystem races, and force;
- user/system-mode tests proving the same advisory behavior;
- direct `POST /profile` and browser-bypass tests proving the documentation is
  honest rather than implying enforcement;
- stable human and JSON output that never contains raw token or profile detail;
- documentation updates across CLI reference, concepts, troubleshooting,
  architecture, and security; and
- a supported-host validation before release.

Until that evidence exists, the current global latest-selection-wins workflow
remains the supported behavior.

## Related documentation

- [Concepts](concepts.md)
- [Architecture](architecture.md)
- [Security model](security.md)
- [CLI reference](cli-reference.md)
- [Troubleshooting](troubleshooting.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

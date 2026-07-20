# Container runtime validation

Containers consume `aws-metadata-agent` through the same
`http://169.254.169.254` endpoint as host applications. The project does not
inject credentials, mount AWS configuration, or configure a custom AWS SDK
endpoint inside the container.

Every reachable container shares the one globally active agent profile. Treat
endpoint reachability as credential access, not merely network connectivity.

## Evidence boundary

| Runtime and host | Network path | Evidence |
| --- | --- | --- |
| Docker Desktop on Apple Silicon macOS 26 | Default container networking to the installed host endpoint | Validated with the installed agent and no AWS credential environment variables or mounted AWS files |
| Docker Engine on GitHub-hosted Ubuntu 24.04 x86_64 | Default Docker bridge to a host-owned `169.254.169.254/32` listener | Validated on every Linux CI run by `tests/container-runtime-linux.sh` |
| Podman | Varies by rootful or rootless network backend | Not yet validated |
| Kubernetes | Varies by cluster, CNI, and cloud metadata interception | Not tested and not part of the support claim |

The Docker Engine check isolates the container-routing boundary from AWS
authentication. It temporarily installs the same `/32` link-local address used
by the Linux service, binds an inert HTTP fixture to port 80, and starts an
unprivileged Alpine container on Docker's default bridge. The container must
reach the standard metadata URL without:

- an `AWS_*` environment variable;
- `~/.aws/config` or `~/.aws/credentials`;
- a bind mount or volume;
- a custom container route or host mapping; or
- an SDK endpoint override.

The fixture image is pinned to the multi-architecture digest for the official
Alpine 3.22.5 image. The test refuses to run if the metadata address already
exists, removes the temporary listener and address on exit, and never reads AWS
configuration or credentials.

This check proves Docker Engine bridge routing on the current GitHub-hosted
Ubuntu runner. It does not replace the separate Ubuntu systemd installation,
logout, reboot, or uninstall evidence, and it does not expand the supported
Linux installation boundary to x86_64.

## Docker Desktop reachability on supported macOS

The supported Apple Silicon macOS validation used ordinary Docker Desktop
container networking to reach the installed host endpoint without host
networking, AWS credential environment variables, AWS file mounts, a custom
route, or a metadata endpoint override.

After `aws-metadata status` confirms the host endpoint is running, reproduce
the credential-free routing boundary with the same digest-pinned Alpine image
used by Linux CI:

```sh
docker run --rm --network bridge \
  alpine:3.22.5@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce \
  /bin/sh -eu -c \
  'wget -qO- -T 10 http://169.254.169.254/ >/dev/null'
```

Exit `0` proves that an ordinary Docker Desktop bridge container reached the
agent's HTTP interface. It discards the page and does not request or print
credentials, profile names, or identity data. It does not prove that a
particular containerized SDK used IMDS; validate that consumer separately
without competing providers.

No Docker Desktop setting change is part of the validated path. If this command
fails while the host endpoint is healthy, inspect the runtime's link-local
routing before changing the agent or adding a custom SDK endpoint.

## Running the Docker Engine check

Run the credential-free check on a clean Linux Docker host:

```sh
./tests/container-runtime-linux.sh
```

The script requires `curl`, Docker Engine, `ip`, Python 3, passwordless `sudo`,
and permission to pull its pinned Alpine fixture. It makes temporary host
network changes, so do not run it on a machine where an EC2 metadata service or
`aws-metadata-agent` is already active.

## Runtime-specific routing

The metadata address is link-local and commonly reserved by cloud platforms.
A runtime may route it to the host, intercept it for its own metadata proxy, or
drop it. Rootless networking implementations may also treat link-local routes
differently from a rootful Linux bridge. The installer deliberately does not
rewrite Docker, Podman, Kubernetes, CNI, or VM networking.

Before claiming support for another runtime, repeat the same invariants: use
the standard address, exclude credential environment variables and AWS file
mounts, document any required route, and verify that the runtime does not
reserve the destination for another metadata service. A custom
`AWS_EC2_METADATA_SERVICE_ENDPOINT` can help diagnose connectivity but does not
validate transparent EC2 metadata compatibility.

Upstream `aws-runas` supports credential requests through IMDSv1 and IMDSv2,
but its EC2 service is a credential-focused subset rather than the complete
metadata tree. The routing checks above do not independently validate every
SDK's IMDSv2 token behavior. See
[Protocol compatibility](architecture.md#protocol-compatibility).

Any container that can reach the endpoint may retrieve credentials for the
globally active profile. See the [Security model](security.md) before exposing
the address to untrusted workloads.

## Related documentation

- [Consumer recipes](consumers.md#containers)
- [Troubleshooting](troubleshooting.md#host-works-but-a-container-fails)
- [Architecture](architecture.md)
- [Security model](security.md)

[Back to the documentation index](README.md) | [Back to the project README](../README.md)

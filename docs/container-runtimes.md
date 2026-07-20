# Container runtime validation

Containers consume `aws-metadata-agent` through the same
`http://169.254.169.254` endpoint as host applications. The project does not
inject credentials, mount AWS configuration, or configure a custom AWS SDK
endpoint inside the container.

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

Any container that can reach the endpoint may retrieve credentials for the
globally active profile. See [Security notes](security.md) before exposing the
address to untrusted workloads.

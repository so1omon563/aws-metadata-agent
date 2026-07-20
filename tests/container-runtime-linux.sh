#!/usr/bin/env bash

set -euo pipefail

readonly METADATA_ADDRESS=169.254.169.254
readonly METADATA_PORT=80
readonly TEST_PATH=/aws-metadata-agent-runtime-check
readonly EXPECTED_BODY=aws-metadata-agent-container-runtime-ok
readonly CONTAINER_IMAGE='alpine:3.22.5@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce'

container_name="aws-metadata-agent-runtime-${RANDOM}-$$"
server_log=$(mktemp "${TMPDIR:-/tmp}/aws-metadata-agent-runtime.XXXXXX")
server_pid=
address_added=no

cleanup() {
  local status=$?

  docker rm --force "$container_name" >/dev/null 2>&1 || true

  if [[ -n $server_pid ]]; then
    sudo kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" 2>/dev/null || true
  fi

  if [[ $address_added == yes ]]; then
    sudo ip address delete "$METADATA_ADDRESS/32" dev lo >/dev/null 2>&1 || true
  fi

  rm -f "$server_log"
  exit "$status"
}
trap cleanup EXIT

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ $(uname -s) == Linux ]] || fail 'This test requires a Linux host.'

for command in curl docker ip python3 sudo; do
  command -v "$command" >/dev/null 2>&1 || fail "Required command not found: $command"
done

if ip address show dev lo | grep -Fq "$METADATA_ADDRESS/32"; then
  fail "$METADATA_ADDRESS is already configured on lo; refusing to disturb an existing metadata service."
fi

sudo -n true || fail 'Passwordless sudo is required for the isolated CI routing fixture.'
sudo ip address add "$METADATA_ADDRESS/32" dev lo
address_added=yes

# The unprivileged shell intentionally owns this temporary log redirection.
# shellcheck disable=SC2024
sudo python3 - "$METADATA_ADDRESS" "$METADATA_PORT" "$TEST_PATH" "$EXPECTED_BODY" \
  >"$server_log" 2>&1 <<'PY' &
import http.server
import sys

address = sys.argv[1]
port = int(sys.argv[2])
test_path = sys.argv[3]
expected_body = sys.argv[4].encode("ascii")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != test_path:
            self.send_error(404)
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(expected_body)))
        self.end_headers()
        self.wfile.write(expected_body)

    def log_message(self, _format, *_args):
        return


http.server.ThreadingHTTPServer((address, port), Handler).serve_forever()
PY
server_pid=$!

host_ready=no
for _ in {1..50}; do
  if response=$(curl --noproxy '*' --fail --silent --show-error \
    --max-time 1 "http://$METADATA_ADDRESS$TEST_PATH") &&
    [[ $response == "$EXPECTED_BODY" ]]; then
    host_ready=yes
    break
  fi
  sleep 0.1
done

if [[ $host_ready != yes ]]; then
  sed -n '1,20p' "$server_log" >&2
  fail 'The isolated host metadata fixture did not become ready.'
fi

docker pull "$CONTAINER_IMAGE"
docker create \
  --name "$container_name" \
  --network bridge \
  "$CONTAINER_IMAGE" \
  /bin/sh -eu -c '
    if env | grep -q "^AWS_"; then
      printf "%s\n" "Unexpected AWS environment variable in container." >&2
      exit 1
    fi

    for file in /root/.aws/config /root/.aws/credentials; do
      if [ -e "$file" ]; then
        printf "Unexpected AWS file in container: %s\n" "$file" >&2
        exit 1
      fi
    done

    response=$(wget -qO- -T 10 http://169.254.169.254/aws-metadata-agent-runtime-check)
    [ "$response" = aws-metadata-agent-container-runtime-ok ]
  ' >/dev/null

mounts=$(docker inspect --format '{{range .Mounts}}{{println .Source " -> " .Destination}}{{end}}' \
  "$container_name")
[[ -z $mounts ]] || fail "The validation container unexpectedly has mounted content: $mounts"

docker start --attach "$container_name"

printf 'Docker Engine default-bridge routing to http://%s:%s passed.\n' \
  "$METADATA_ADDRESS" "$METADATA_PORT"
printf '%s\n' 'No AWS environment variables, AWS files, mounts, custom routes, or endpoint overrides were used.'

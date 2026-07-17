#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_DIR

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/aws-metadata-pr-check.XXXXXX")
readonly TEMP_ROOT
trap 'rm -rf "$TEMP_ROOT"' EXIT

readonly WAIT_SCRIPT="$PROJECT_DIR/scripts/wait_for_pr_check.sh"
readonly GH_FIXTURE="$PROJECT_DIR/tests/fixtures/gh-pr-check"

queue="$TEMP_ROOT/queue"
calls="$TEMP_ROOT/calls"
stdout="$TEMP_ROOT/stdout"
stderr="$TEMP_ROOT/stderr"

run_wait() {
  GH_BIN=$GH_FIXTURE \
    MOCK_GH_CHECK_QUEUE=$queue \
    MOCK_GH_CALL_COUNT=$calls \
    PR_CHECK_DISCOVERY_TIMEOUT_SECONDS=${PR_CHECK_DISCOVERY_TIMEOUT_SECONDS:-3} \
    PR_CHECK_DISCOVERY_INTERVAL_SECONDS=1 \
    "$WAIT_SCRIPT" owner/tap https://example.invalid/pull/1 test
}

printf '%s\n' 'test' >"$queue"
: >"$calls"
run_wait >"$stdout" 2>"$stderr"
[[ $(<"$calls") == 1 ]]
grep -Fq 'Required check test is registered' "$stdout"

printf '%s\n' '<none>' 'lint,test' >"$queue"
: >"$calls"
run_wait >"$stdout" 2>"$stderr"
[[ $(<"$calls") == 2 ]]
grep -Fq 'Required check test is registered' "$stdout"

printf '%s\n' '<none>' '<none>' >"$queue"
: >"$calls"
if PR_CHECK_DISCOVERY_TIMEOUT_SECONDS=1 run_wait >"$stdout" 2>"$stderr"; then
  printf '%s\n' 'Check discovery unexpectedly succeeded without the required check.' >&2
  exit 1
fi
grep -Fq 'Timed out after 1 seconds waiting for check test' "$stderr"
grep -Fq 'gh pr checks https://example.invalid/pull/1 --repo owner/tap' "$stderr"

printf '%s\n' '<error>' >"$queue"
: >"$calls"
if run_wait >"$stdout" 2>"$stderr"; then
  printf '%s\n' 'Check discovery ignored a GitHub API failure.' >&2
  exit 1
fi
[[ $(<"$calls") == 1 ]]
grep -Fq 'Failed to query checks' "$stderr"

workflow="$PROJECT_DIR/.github/workflows/post-release-homebrew.yml"
wait_line=$(grep -n 'wait_for_pr_check.sh' "$workflow" | cut -d: -f1)
watch_line=$(grep -n 'gh pr checks.*--watch --fail-fast' "$workflow" | cut -d: -f1)
[[ -n $wait_line && -n $watch_line && $wait_line -lt $watch_line ]]
grep -Fq "so1omon563/homebrew-aws-metadata-agent \"\$pr_url\" test" "$workflow"

printf '%s\n' 'Pull-request check discovery tests passed.'

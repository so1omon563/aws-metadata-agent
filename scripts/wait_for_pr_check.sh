#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  printf 'Usage: %s REPOSITORY PULL_REQUEST CHECK_NAME\n' "$0" >&2
  exit 2
fi

readonly REPOSITORY=$1
readonly PULL_REQUEST=$2
readonly CHECK_NAME=$3
readonly GH_BIN=${GH_BIN:-gh}
readonly DISCOVERY_TIMEOUT_SECONDS=${PR_CHECK_DISCOVERY_TIMEOUT_SECONDS:-120}
readonly DISCOVERY_INTERVAL_SECONDS=${PR_CHECK_DISCOVERY_INTERVAL_SECONDS:-2}

if ! [[ $DISCOVERY_TIMEOUT_SECONDS =~ ^[1-9][0-9]*$ ]]; then
  printf '%s\n' 'PR_CHECK_DISCOVERY_TIMEOUT_SECONDS must be a positive integer.' >&2
  exit 2
fi
if ! [[ $DISCOVERY_INTERVAL_SECONDS =~ ^[1-9][0-9]*$ ]]; then
  printf '%s\n' 'PR_CHECK_DISCOVERY_INTERVAL_SECONDS must be a positive integer.' >&2
  exit 2
fi

readonly DEADLINE=$((SECONDS + DISCOVERY_TIMEOUT_SECONDS))

while true; do
  if ! check_names=$("$GH_BIN" pr view "$PULL_REQUEST" \
    --repo "$REPOSITORY" \
    --json statusCheckRollup \
    --jq '.statusCheckRollup[].name'); then
    printf 'Failed to query checks for %s in %s.\n' \
      "$PULL_REQUEST" "$REPOSITORY" >&2
    exit 1
  fi

  while IFS= read -r registered_name; do
    if [[ $registered_name == "$CHECK_NAME" ]]; then
      printf 'Required check %s is registered for %s.\n' \
        "$CHECK_NAME" "$PULL_REQUEST"
      exit 0
    fi
  done <<<"$check_names"

  if ((SECONDS >= DEADLINE)); then
    break
  fi

  remaining=$((DEADLINE - SECONDS))
  sleep_seconds=$DISCOVERY_INTERVAL_SECONDS
  if ((sleep_seconds > remaining)); then
    sleep_seconds=$remaining
  fi
  sleep "$sleep_seconds"
done

printf 'Timed out after %s seconds waiting for check %s to register on %s.\n' \
  "$DISCOVERY_TIMEOUT_SECONDS" "$CHECK_NAME" "$PULL_REQUEST" >&2
printf 'Inspect it with: gh pr checks %s --repo %s\n' \
  "$PULL_REQUEST" "$REPOSITORY" >&2
exit 1

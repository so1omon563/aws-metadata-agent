#!/usr/bin/env bash

set -euo pipefail

text=${1-}

printf '%s\n' "$text" | tr '[:upper:]' '[:lower:]' | awk '
{
  for (i = 1; i <= NF; i++) {
    token = $i
    if (token == "#patch" || token == "#minor" || token == "#major") {
      bump = substr(token, 2)
      bump_count++
    } else if (token == "#release" || token == "#publish" || token == "#ship") {
      continue
    } else if (token ~ /#(patch|minor|major|release|publish|ship)/) {
      printf "Release marker must be a standalone token: %s\n", token > "/dev/stderr"
      invalid = 1
    }
  }
}
END {
  if (invalid)
    exit 1
  if (bump_count != 1) {
    print "Release PR title must contain exactly one semver marker." > "/dev/stderr"
    exit 1
  }
  print bump
}'

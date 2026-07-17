#!/usr/bin/env python3
"""Update the Homebrew formula for a published aws-metadata-agent release."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def update_formula(
    path: Path, version: str, archive_url: str, checksum_path: Path
) -> None:
    checksum_fields = checksum_path.read_text(encoding="utf-8").split()
    if not checksum_fields or not SHA256_RE.fullmatch(checksum_fields[0]):
        raise ValueError("checksum file does not start with a SHA-256 digest")
    checksum = checksum_fields[0]

    text = path.read_text(encoding="utf-8")
    text, url_count = re.subn(
        r'(?m)^  url "[^"]+"$', f'  url "{archive_url}"', text, count=1
    )
    text, sha_count = re.subn(
        r'(?m)^  sha256 "[0-9a-f]{64}"$', f'  sha256 "{checksum}"', text, count=1
    )
    text, test_count = re.subn(
        r'assert_equal "\d+\.\d+\.\d+\\n", shell_output',
        lambda _match: f'assert_equal "{version}\\n", shell_output',
        text,
        count=1,
    )
    if (url_count, sha_count, test_count) != (1, 1, 1):
        raise ValueError("formula is missing its expected url, sha256, or version test")
    path.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("formula", type=Path)
    parser.add_argument("version")
    parser.add_argument("archive_url")
    parser.add_argument("checksum", type=Path)
    args = parser.parse_args()

    if not VERSION_RE.fullmatch(args.version):
        print(f"error: invalid version {args.version!r}", file=sys.stderr)
        return 2
    try:
        update_formula(args.formula, args.version, args.archive_url, args.checksum)
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Validate VERSION, tags, and staged changelog release metadata."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from stage_release import (
    CURRENT_RELEASE_REFERENCE_FILES,
    CURRENT_RELEASE_REFERENCE_RE,
    RELEASE_HEADER_RE,
    ReleaseStageError,
    Version,
    latest_tag_version,
    read_text,
    read_version,
)


def validate_current_release_references(root: Path, version: Version) -> None:
    for relative_path in CURRENT_RELEASE_REFERENCE_FILES:
        references = {
            match.group("version")
            for match in CURRENT_RELEASE_REFERENCE_RE.finditer(
                read_text(root / relative_path)
            )
        }
        if references != {str(version)}:
            found = ", ".join(sorted(references)) or "none"
            raise ReleaseStageError(
                f"{relative_path} release examples must all reference "
                f"VERSION {version}; found {found}"
            )


def validate_links(text: str, version: Version, latest: Version) -> None:
    unreleased = (
        "[Unreleased]: "
        "https://github.com/so1omon563/aws-metadata-agent/compare/"
        f"v{version}...HEAD"
    )
    if unreleased not in text:
        raise ReleaseStageError(f"Unreleased comparison must start at v{version}")

    if version != latest:
        release_link = (
            f"[{version}]: "
            "https://github.com/so1omon563/aws-metadata-agent/compare/"
            f"v{latest}...v{version}"
        )
        if release_link not in text:
            raise ReleaseStageError(f"missing comparison link for {version}")


def check_release(root: Path, bump: str | None) -> None:
    version = read_version(root / "VERSION")
    latest = latest_tag_version(root)
    changelog = read_text(root / "CHANGELOG.md")

    if version < latest:
        raise ReleaseStageError(f"VERSION {version} is older than latest tag v{latest}")
    if version > latest:
        matches = [match.group(1) for match in RELEASE_HEADER_RE.finditer(changelog)]
        if str(version) not in matches:
            raise ReleaseStageError(f"CHANGELOG.md has no dated section for {version}")

    if bump is not None:
        expected = latest.bump(bump)
        if version != expected:
            raise ReleaseStageError(
                f"#{bump} from v{latest} requires VERSION {expected}, found {version}"
            )
        release_header = (
            rf"(?m)^## \[{re.escape(str(version))}\] - "
            r"\d{4}-\d{2}-\d{2}$"
        )
        tag = re.search(release_header, changelog)
        if tag is None:
            raise ReleaseStageError(f"CHANGELOG.md has no dated section for {version}")
    elif version > latest:
        valid_next = {latest.bump(kind) for kind in ("patch", "minor", "major")}
        if version not in valid_next:
            raise ReleaseStageError(
                f"staged VERSION {version} is not one semantic bump after v{latest}"
            )

    validate_links(changelog, version, latest)
    validate_current_release_references(root, version)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--bump", choices=["patch", "minor", "major"])
    args = parser.parse_args(argv)
    try:
        check_release(args.root.resolve(), args.bump)
    except ReleaseStageError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print("Release metadata checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

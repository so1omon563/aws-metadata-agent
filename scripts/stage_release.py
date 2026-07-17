#!/usr/bin/env python3
"""Stage deterministic VERSION and CHANGELOG updates for a release PR."""

from __future__ import annotations

import argparse
import datetime as dt
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")
TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
RELEASE_HEADER_RE = re.compile(
    r"(?m)^## \[(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2})$"
)
CURRENT_RELEASE_REFERENCE_RE = re.compile(
    r"(?P<prefix>(?:^version=|--version ))"
    r"(?P<version>\d+\.\d+\.\d+)\b",
    re.MULTILINE,
)
CURRENT_RELEASE_REFERENCE_FILES = (
    Path("docs/direct-install.md"),
    Path("install-release.sh"),
)


class ReleaseStageError(RuntimeError):
    pass


@dataclass(frozen=True, order=True)
class Version:
    major: int
    minor: int
    patch: int

    @classmethod
    def parse(cls, value: str) -> Version:
        if not VERSION_RE.fullmatch(value):
            raise ReleaseStageError(f"invalid version {value!r}; expected X.Y.Z")
        return cls(*(int(part) for part in value.split(".")))

    @classmethod
    def parse_tag(cls, value: str) -> Version | None:
        match = TAG_RE.fullmatch(value)
        if match is None:
            return None
        return cls(*(int(part) for part in match.groups()))

    def bump(self, kind: str) -> Version:
        if kind == "major":
            return Version(self.major + 1, 0, 0)
        if kind == "minor":
            return Version(self.major, self.minor + 1, 0)
        if kind == "patch":
            return Version(self.major, self.minor, self.patch + 1)
        raise ReleaseStageError(f"unsupported bump kind {kind!r}")

    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"


def run_git(
    root: Path, args: list[str], *, capture: bool = False
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            ["git", *args],
            cwd=root,
            check=True,
            capture_output=capture,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        output = ((exc.stdout or "") + (exc.stderr or "")).strip()
        message = f"git {' '.join(args)} failed"
        if output:
            message = f"{message}: {output}"
        raise ReleaseStageError(message) from exc


def latest_tag_version(root: Path) -> Version:
    completed = run_git(root, ["tag", "--list", "v[0-9]*"], capture=True)
    versions = [
        version
        for tag in completed.stdout.splitlines()
        if (version := Version.parse_tag(tag.strip())) is not None
    ]
    if not versions:
        raise ReleaseStageError("no semantic-version tags found")
    return max(versions)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ReleaseStageError(f"read {path}: {exc}") from exc


def read_version(path: Path) -> Version:
    return Version.parse(read_text(path).strip())


def read_unreleased_entries(path: Path) -> tuple[str, int, str]:
    text = read_text(path)
    header = "## [Unreleased]"
    start = text.find(header)
    if start == -1:
        raise ReleaseStageError("CHANGELOG.md must contain an Unreleased section")
    content_start = start + len(header)
    next_match = RELEASE_HEADER_RE.search(text, content_start)
    if next_match is None:
        raise ReleaseStageError("CHANGELOG.md must contain a dated release section")
    entries = text[content_start : next_match.start()].strip()
    if not entries:
        raise ReleaseStageError(
            "CHANGELOG.md Unreleased section is empty; add release notes before staging"
        )
    return text, next_match.start(), entries


def update_changelog(
    path: Path, previous: Version, version: Version, release_date: str
) -> None:
    text, next_release_start, entries = read_unreleased_entries(path)
    unreleased_start = text.index("## [Unreleased]")
    updated = (
        text[:unreleased_start]
        + "## [Unreleased]\n\n"
        + f"## [{version}] - {release_date}\n\n{entries}\n\n"
        + text[next_release_start:]
    )

    unreleased_pattern = re.compile(r"(?m)^\[Unreleased\]: .+$")
    replacement = (
        "[Unreleased]: "
        f"https://github.com/so1omon563/aws-metadata-agent/compare/v{version}...HEAD"
    )
    updated, count = unreleased_pattern.subn(replacement, updated, count=1)
    if count != 1:
        raise ReleaseStageError("CHANGELOG.md must contain one Unreleased comparison link")

    previous_link = f"[{previous}]:"
    previous_link_start = updated.find(previous_link)
    if previous_link_start == -1:
        raise ReleaseStageError(
            f"CHANGELOG.md must contain the previous release link {previous_link}"
        )
    new_link = (
        f"[{version}]: "
        "https://github.com/so1omon563/aws-metadata-agent/compare/"
        f"v{previous}...v{version}\n"
    )
    updated = updated[:previous_link_start] + new_link + updated[previous_link_start:]
    path.write_text(updated, encoding="utf-8")


def prepare_current_release_reference_updates(
    root: Path, previous: Version, version: Version
) -> list[tuple[Path, str]]:
    updates = []
    for relative_path in CURRENT_RELEASE_REFERENCE_FILES:
        path = root / relative_path
        text = read_text(path)
        references = {
            match.group("version")
            for match in CURRENT_RELEASE_REFERENCE_RE.finditer(text)
        }
        if references != {str(previous)}:
            found = ", ".join(sorted(references)) or "none"
            raise ReleaseStageError(
                f"{relative_path} release examples must all reference "
                f"{previous}; found {found}"
            )
        updated = CURRENT_RELEASE_REFERENCE_RE.sub(
            lambda match: f'{match.group("prefix")}{version}', text
        )
        updates.append((path, updated))
    return updates


def stage_release(
    root: Path, bump: str, explicit_version: str | None, release_date: str, fetch: bool
) -> Version:
    try:
        dt.date.fromisoformat(release_date)
    except ValueError as exc:
        raise ReleaseStageError(
            f"invalid release date {release_date!r}; expected YYYY-MM-DD"
        ) from exc

    status = run_git(root, ["status", "--porcelain"], capture=True)
    if status.stdout.strip():
        raise ReleaseStageError("working tree must be clean before staging a release")
    if fetch:
        run_git(root, ["fetch", "--tags", "origin"])

    latest = latest_tag_version(root)
    current = read_version(root / "VERSION")
    if current != latest:
        raise ReleaseStageError(
            f"VERSION is {current}, but latest release tag is v{latest}"
        )

    version = Version.parse(explicit_version) if explicit_version else latest.bump(bump)
    if version != latest.bump(bump):
        raise ReleaseStageError(
            f"target {version} does not match the requested {bump} bump from v{latest}"
        )
    tag = run_git(root, ["tag", "--list", f"v{version}"], capture=True)
    if tag.stdout.strip():
        raise ReleaseStageError(f"tag v{version} already exists")

    reference_updates = prepare_current_release_reference_updates(
        root, latest, version
    )
    update_changelog(root / "CHANGELOG.md", latest, version, release_date)
    (root / "VERSION").write_text(f"{version}\n", encoding="utf-8")
    for path, text in reference_updates:
        path.write_text(text, encoding="utf-8")
    return version


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--bump", choices=["patch", "minor", "major"], default="patch")
    parser.add_argument("--version")
    parser.add_argument("--date", default=dt.date.today().isoformat())
    parser.add_argument("--no-fetch", action="store_true")
    args = parser.parse_args(argv)

    try:
        version = stage_release(
            args.root.resolve(), args.bump, args.version, args.date, not args.no_fetch
        )
    except ReleaseStageError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(f"staged release {version}")
    print(f"PR title: Prepare release {version} #{args.bump} #release")
    return 0


if __name__ == "__main__":
    sys.exit(main())

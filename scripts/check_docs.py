#!/usr/bin/env python3
"""Validate local documentation navigation and audience boundaries."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


INLINE_LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
HEADING_RE = re.compile(r"^#{1,6}\s+(.+?)\s*#*\s*$", re.MULTILINE)
EXTERNAL_SCHEMES = ("http://", "https://", "mailto:")


class DocsError(RuntimeError):
    pass


def documentation_files(root: Path) -> list[Path]:
    top_level = (
        root / "README.md",
        root / "CONTRIBUTING.md",
        root / "SECURITY.md",
        root / "THIRD_PARTY_NOTICES.md",
    )
    return [*top_level, *sorted((root / "docs").rglob("*.md"))]


def link_path(target: str) -> str:
    target = target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    return unquote(target.split("#", 1)[0])


def github_anchors(path: Path) -> set[str]:
    anchors: set[str] = set()
    duplicates: dict[str, int] = {}
    text = path.read_text(encoding="utf-8")
    for match in HEADING_RE.finditer(text):
        heading = match.group(1)
        heading = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", heading)
        heading = heading.replace("`", "").replace("*", "").replace("_", "")
        slug = re.sub(r"[^\w\- ]", "", heading.lower())
        slug = re.sub(r"\s+", "-", slug.strip())
        duplicate = duplicates.get(slug, 0)
        duplicates[slug] = duplicate + 1
        anchors.add(slug if duplicate == 0 else f"{slug}-{duplicate}")
    return anchors


def validate_local_links(root: Path, files: list[Path]) -> None:
    errors: list[str] = []
    anchor_cache: dict[Path, set[str]] = {}
    for source in files:
        if not source.is_file():
            errors.append(f"missing documentation file: {source.relative_to(root)}")
            continue
        text = source.read_text(encoding="utf-8")
        for match in INLINE_LINK_RE.finditer(text):
            target = match.group(1).strip()
            if not target or target.startswith(EXTERNAL_SCHEMES):
                continue
            relative = link_path(target)
            resolved = source if not relative else (source.parent / relative).resolve()
            try:
                resolved.relative_to(root)
            except ValueError:
                errors.append(
                    f"{source.relative_to(root)} links outside the repository: {target}"
                )
                continue
            if not resolved.exists():
                errors.append(
                    f"{source.relative_to(root)} has missing local link: {target}"
                )
                continue
            if "#" in target and resolved.is_file():
                fragment = unquote(target.split("#", 1)[1]).lower()
                anchors = anchor_cache.setdefault(resolved, github_anchors(resolved))
                if fragment and fragment not in anchors:
                    errors.append(
                        f"{source.relative_to(root)} has missing anchor: {target}"
                    )
    if errors:
        raise DocsError("\n".join(errors))


def validate_index(root: Path) -> None:
    index = (root / "docs" / "README.md").read_text(encoding="utf-8")
    missing = [
        path.name
        for path in sorted((root / "docs").glob("*.md"))
        if path.name != "README.md" and f"({path.name})" not in index
    ]
    if missing:
        raise DocsError(
            "docs/README.md does not link every documentation page: "
            + ", ".join(missing)
        )


def validate_reader_contract(root: Path) -> None:
    readme = (root / "README.md").read_text(encoding="utf-8")
    for required in (
        "makes a developer workstation behave like an EC2 instance",
        "## Is this for me?",
        "## Know before installing",
        "## Supported platforms",
        "## Quick start",
        "docs/getting-started.md",
        "docs/concepts.md",
        "docs/verification.md",
        "docs/cli-reference.md",
        "docs/troubleshooting.md",
    ):
        if required not in readme:
            raise DocsError(f"README.md is missing reader-journey contract: {required}")

    index = (root / "docs/README.md").read_text(encoding="utf-8")
    for required in (
        "## Start here",
        "## Guides",
        "## Concepts",
        "## Reference",
        "## Architecture and security",
        "## Maintenance",
    ):
        if required not in index:
            raise DocsError(f"docs/README.md is missing navigation group: {required}")

    getting_started = (root / "docs/getting-started.md").read_text(encoding="utf-8")
    for required in (
        "install -> confirm upstream profile -> check service -> select profile -> verify",
        "[verification checklist](verification.md)",
    ):
        if required not in getting_started:
            raise DocsError(
                f"docs/getting-started.md is missing happy-path contract: {required}"
            )

    user_files = (
        "README.md",
        "docs/getting-started.md",
        "docs/concepts.md",
        "docs/verification.md",
        "docs/homebrew.md",
        "docs/direct-install.md",
        "docs/aws-runas-configuration.md",
        "docs/upgrades.md",
    )
    for relative in user_files:
        text = (root / relative).read_text(encoding="utf-8")
        if "PACKAGING_PR_TOKEN" in text:
            raise DocsError(f"{relative} contains maintainer-only release secret guidance")

    configuration = (root / "docs/aws-runas-configuration.md").read_text(
        encoding="utf-8"
    )
    if "Project-specific examples belong here only" in configuration:
        raise DocsError(
            "aws-runas configuration still contains contributor example policy"
        )

    troubleshooting = (root / "docs/troubleshooting.md").read_text(encoding="utf-8")
    if "## Choose the failing symptom" not in troubleshooting:
        raise DocsError("docs/troubleshooting.md omits the symptom router")
    linux_service_status = (
        "systemctl status aws-metadata-agent-address.service aws-metadata-agent.socket \\\n"
        "  aws-metadata-agent.service"
    )
    if linux_service_status not in troubleshooting:
        raise DocsError(
            "docs/troubleshooting.md omits the Linux system proxy service status"
        )


def main() -> int:
    root = Path.cwd().resolve()
    try:
        files = documentation_files(root)
        validate_local_links(root, files)
        validate_index(root)
        validate_reader_contract(root)
    except (DocsError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print("Documentation checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Credential-safe scanner for tracked sources and built app artifacts.

Findings intentionally contain only a path and line/key location.
"""

from __future__ import annotations

import argparse
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit


TEXT_SUFFIXES = {
    ".entitlements",
    ".js",
    ".json",
    ".md",
    ".pbxproj",
    ".plist",
    ".scpt",
    ".sh",
    ".storyboard",
    ".strings",
    ".swift",
    ".tsv",
    ".xcconfig",
    ".xib",
    ".xml",
    ".yaml",
    ".yml",
}

REUSABLE_SECRET = re.compile(
    r"""(?ix)
    (?<![a-z0-9_])
    (?:api[_-]?(?:key|secret)|access[_-]?token|authorization|bearer|
       client[_-]?secret|credential|password|private[_-]?key|token)
    \s*(?:=|:)\s*
    (?:["']\s*)?
    [a-z0-9_./+=:-]{8,}
    """
)
URL = re.compile(r"https?://[^\s\"'<>]+", re.IGNORECASE)
CREDENTIAL_QUERY = re.compile(
    r"(?i)(?:^|[?&#])(?:api[_-]?(?:key|secret)|access[_-]?token|client[_-]?secret|credential|password|token|secret)="
)


def report(findings: list[tuple[str, str]], location: str) -> None:
    findings.append((location, ""))


def scan_text(path: Path, display: str, findings: list[tuple[str, str]], excluded: set[Path]) -> None:
    resolved = path.resolve()
    if resolved in excluded or not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
        return
    try:
        raw = path.read_bytes()
    except OSError:
        report(findings, f"{display}:unreadable")
        return
    if b"\x00" in raw:
        return
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return

    for line_number, line in enumerate(text.splitlines(), start=1):
        if REUSABLE_SECRET.search(line):
            report(findings, f"{display}:{line_number}")
            continue
        for match in URL.finditer(line):
            candidate = match.group(0).rstrip(".,;)]}")
            try:
                parsed = urlsplit(candidate)
            except ValueError:
                report(findings, f"{display}:{line_number}")
                break
            if parsed.username is not None or parsed.password is not None:
                report(findings, f"{display}:{line_number}")
                break
            if CREDENTIAL_QUERY.search(parsed.query) or CREDENTIAL_QUERY.search(parsed.fragment):
                report(findings, f"{display}:{line_number}")
                break


def tracked_files(root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    paths = [Path(item) for item in result.stdout.decode("utf-8").split("\x00") if item]
    # Test fixtures intentionally exercise rejected URL shapes; production/config/build
    # scanning remains strict, while the synthetic-file test covers scanner failure.
    return [root / item for item in paths if not any(part.endswith("Tests") for part in item.parts)]


def safe_endpoint(value: object) -> bool:
    if not isinstance(value, str) or not value or value != value.strip():
        return False
    try:
        parsed = urlsplit(value)
    except ValueError:
        return False
    return (
        parsed.scheme.lower() == "https"
        and bool(parsed.hostname)
        and parsed.username is None
        and parsed.password is None
        and parsed.query == ""
        and parsed.fragment == ""
    )


def scan_artifact(path: Path, findings: list[tuple[str, str]], excluded: set[Path]) -> None:
    if not path.exists():
        report(findings, f"{path}:missing")
        return
    candidates = [path] if path.is_file() else [item for item in path.rglob("*") if item.is_file()]
    for item in candidates:
        display = str(item)
        if item.name == "Info.plist":
            try:
                with item.open("rb") as handle:
                    plist = plistlib.load(handle)
            except (OSError, plistlib.InvalidFileException, ValueError, TypeError):
                report(findings, f"{display}:invalid-plist")
                continue
            value = plist.get("CurrencyInfoFeed") if isinstance(plist, dict) else None
            if value not in (None, "") and not safe_endpoint(value):
                report(findings, f"{display}:CurrencyInfoFeed")
        scan_text(item, display, findings, excluded)


def main() -> int:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--artifact", action="append", default=[], type=Path)
    parser.add_argument("--extra-file", action="append", default=[], type=Path)
    args = parser.parse_args()

    root = args.root.resolve()
    findings: list[tuple[str, str]] = []
    excluded = {Path(__file__).resolve()}
    try:
        files = tracked_files(root)
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError):
        report(findings, f"{root}:git-files")
        files = []

    for path in files:
        scan_text(path, str(path.relative_to(root)), findings, excluded)
    for path in args.extra_file:
        scan_text(path, str(path), findings, excluded)
    for path in args.artifact:
        scan_artifact(path, findings, excluded)

    for location, _ in sorted(set(findings)):
        print(location)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())

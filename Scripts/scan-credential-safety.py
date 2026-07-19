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
PLIST_SUFFIXES = {".entitlements", ".plist"}

REUSABLE_SECRET = re.compile(
    r"""(?ix)
    (?<![a-z0-9_])
    (?:api[_-]?(?:key|secret)|access(?:[_-]?(?:token|key|secret))|authorization|bearer|
       client[_-]?secret|credential|password|private[_-]?key|token)
    \s*(?:=|:)\s*
    (?:["']\s*)?
    [a-z0-9_./+=:-]{8,}
    """
)
URL = re.compile(r"https?://[^\s\"'<>]+", re.IGNORECASE)
SENSITIVE_CREDENTIAL_KEY = re.compile(
    r"""(?ix)
    ^(?:api[_-]?(?:key|secret)
      |access(?:[_-]?(?:token|key|secret))
      |authorization|bearer|client[_-]?secret|credential|password|private[_-]?key|token|secret)$
    """
)
SUSPICIOUS_PLIST_KEY = re.compile(
    r"^(?:accesskey|accesssecret|accesstoken|apikey|apisecret|authorization|bearer|clientsecret|credentials?|passwords?|privatekey|tokens?|secrets?)$"
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
            if _has_credential_param(parsed.query) or _has_credential_param(parsed.fragment):
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
    return [root / item for item in paths]


def safe_endpoint(value: object) -> bool:
    if not isinstance(value, str) or not value or value != value.strip():
        return False
    if any(character.isspace() for character in value) or "$(" in value:
        return False
    try:
        parsed = urlsplit(value)
        parsed.port
    except ValueError:
        return False
    try:
        if parsed.port is not None and not (0 < parsed.port <= 65535):
            return False
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


def _has_credential_param(raw: str) -> bool:
    for name, value in re.findall(r"([^&#=]+)=([^&#]*)", raw):
        if SENSITIVE_CREDENTIAL_KEY.fullmatch(name) and value.strip():
            return True
    return False


def is_nonempty_scalar(value: object) -> bool:
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, (bytes, bytearray)):
        return bool(value)
    return not isinstance(value, (dict, list, tuple)) and value is not None


def plist_key_name(key: object) -> str:
    return re.sub(r"[^a-z0-9]", "", str(key).lower())


def scan_plist(path: Path, display: str, findings: list[tuple[str, str]], artifact: bool) -> None:
    try:
        with path.open("rb") as handle:
            plist = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException, ValueError, TypeError):
        report(findings, f"{display}:invalid-plist")
        return

    def visit(value: object, key_path: str) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                child_path = f"{key_path}.{key}" if key_path else str(key)
                normalized_key = plist_key_name(key)
                if SUSPICIOUS_PLIST_KEY.fullmatch(normalized_key) and is_nonempty_scalar(child):
                    report(findings, f"{display}:{child_path}")
                if str(key) == "CurrencyInfoFeed" and child not in (None, ""):
                    source_placeholder = not artifact and child == "$(CURRENCY_INFO_FEED)"
                    if not source_placeholder and not safe_endpoint(child):
                        report(findings, f"{display}:{child_path}")
                visit(child, child_path)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                visit(child, f"{key_path}[{index}]")

    visit(plist, "")


def scan_artifact(path: Path, findings: list[tuple[str, str]], excluded: set[Path]) -> None:
    if not path.exists():
        report(findings, f"{path}:missing")
        return
    candidates = [path] if path.is_file() else [item for item in path.rglob("*") if item.is_file()]
    for item in candidates:
        display = str(item)
        if item.suffix.lower() in PLIST_SUFFIXES:
            scan_plist(item, display, findings, artifact=True)
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
        display = str(path.relative_to(root))
        if path.suffix.lower() in PLIST_SUFFIXES:
            scan_plist(path, display, findings, artifact=False)
        scan_text(path, display, findings, excluded)
    for path in args.extra_file:
        display = str(path)
        if path.suffix.lower() in PLIST_SUFFIXES:
            scan_plist(path, display, findings, artifact=False)
        scan_text(path, display, findings, excluded)
    for path in args.artifact:
        scan_artifact(path, findings, excluded)

    for location, _ in sorted(set(findings)):
        print(location)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())

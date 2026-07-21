#!/usr/bin/env python3
"""Credential-safe scanner for tracked sources and built app artifacts.

Findings intentionally contain only an opaque label and a line/byte location.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import re
import stat
import subprocess
import sys
from pathlib import Path
from urllib.parse import parse_qsl, unquote, unquote_plus, urlsplit


PLIST_SUFFIXES = {".plist"}
PLIST_BINARY_HEADER = b"bplist" + b"00"
PLIST_XML_PATTERN = re.compile(
    b"<" + rb"\s*" + b"plist" + rb"(?:\s|>)", re.IGNORECASE
)
PLIST_DOCTYPE_PATTERN = re.compile(
    b"<" + rb"!\s*" + b"doctype" + rb"\s+" + b"plist" + rb"\b",
    re.IGNORECASE,
)
PLIST_PROPERTY_DTD_PATTERN = re.compile(
    b"property" + rb"\s*list" + rb"\s*-\s*1\.0" + rb"\s*\.dtd",
    re.IGNORECASE,
)
SENSITIVE_NAMES = frozenset(
    {
        "apikey",
        "apisecret",
        "apitoken",
        "accesskey",
        "accesssecret",
        "accesstoken",
        "authkey",
        "authsecret",
        "authtoken",
        "authorization",
        "bearer",
        "clientkey",
        "clientsecret",
        "clienttoken",
        "clientcredential",
        "clientcredentials",
        "credential",
        "credentials",
        "password",
        "passwords",
        "privatekey",
        "secretkey",
        "token",
        "tokens",
        "secret",
        "secrets",
    }
)

URL_PATTERN = re.compile(r"https?://[^\s\"'<>]+", re.IGNORECASE)
ASSIGNMENT_PATTERN = re.compile(
    r"""
    (?<![A-Za-z0-9_])
    (?P<name>
        \"(?:[^\"\\]|\\.)*\"
        |'(?:[^'\\]|\\.)*'
        |[A-Za-z%][A-Za-z0-9_.%\-]{0,80}
    )
    [ \t]*(?:=(?!=)|:(?!=))[ \t]*(?P<value>[^\r\n]*)
    """,
    re.VERBOSE,
)


def report(findings: list[tuple[str, str]], location: str) -> None:
    findings.append((location, "credential-like material"))


def decode_name(value: object) -> str:
    decoded = str(value)
    for _ in range(3):
        next_value = unquote_plus(decoded)
        if next_value == decoded:
            break
        decoded = next_value
    return decoded


def normalized_name(value: object) -> str:
    return re.sub(r"[^a-z0-9]", "", decode_name(value).lower())


def is_sensitive_name(value: object) -> bool:
    return normalized_name(value) in SENSITIVE_NAMES


def printable_value(value: str) -> bool:
    value = value.strip()
    return (
        bool(value)
        and any(not character.isspace() for character in value)
        and all(character.isprintable() for character in value)
    )


def assignment_value(raw: str) -> str:
    candidate = raw.strip().rstrip(",;")
    if len(candidate) >= 2 and candidate[0] in {"\"", "'"}:
        quote = candidate[0]
        escaped = False
        for index in range(1, len(candidate)):
            character = candidate[index]
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                return candidate[1:index]
    return candidate


def has_sensitive_assignment(line: str) -> bool:
    for match in ASSIGNMENT_PATTERN.finditer(line):
        if is_sensitive_name(match.group("name")) and printable_value(
            assignment_value(match.group("value"))
        ):
            return True
    return False


def has_credential_param(raw: str) -> bool:
    try:
        pairs = parse_qsl(raw, keep_blank_values=True, strict_parsing=False)
    except ValueError:
        return False
    return any(is_sensitive_name(name) and bool(value.strip()) for name, value in pairs)


def scan_line(line: str) -> bool:
    if has_sensitive_assignment(line):
        return True
    for match in URL_PATTERN.finditer(line):
        candidate = match.group(0).rstrip(".,;!?)]}")
        try:
            parsed = urlsplit(candidate)
        except ValueError:
            return True
        if (
            parsed.username is not None
            or parsed.password is not None
            or has_credential_param(parsed.query)
            or has_credential_param(parsed.fragment)
        ):
            return True
    return False


def scan_content(content: str) -> bool:
    return any(scan_line(line) for line in content.splitlines())


def printable_segments(raw: bytes) -> list[tuple[int, str]]:
    segments: list[tuple[int, str]] = []
    start: int | None = None
    buffer: list[str] = []

    def finish() -> None:
        nonlocal start, buffer
        if start is not None and buffer:
            segments.append((start, "".join(buffer)))
        start = None
        buffer = []

    for offset, byte in enumerate(raw):
        character = chr(byte)
        is_printable = byte in {9, 10, 13} or character.isprintable()
        if is_printable:
            if start is None:
                start = offset
            buffer.append(character)
        else:
            finish()
    finish()
    return segments


def scan_bytes(path: Path, display: str, raw: bytes, findings: list[tuple[str, str]]) -> None:
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = None

    if text is not None and b"\x00" not in raw:
        for line_number, line in enumerate(text.splitlines(), start=1):
            if scan_line(line):
                report(findings, f"{display}:{line_number}")
        return

    for offset, segment in printable_segments(raw):
        if scan_content(segment):
            report(findings, f"{display}:byte-{offset}")


def tracked_files(root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    paths = [Path(os.fsdecode(item)) for item in result.stdout.split(b"\0") if item]
    return [root / item for item in paths]


def safe_endpoint(value: object) -> bool:
    if not isinstance(value, str) or not value or value != value.strip():
        return False
    if any(character.isspace() for character in value) or "$(" in value:
        return False
    if re.search(r"%(?![0-9A-Fa-f]{2})", value):
        return False
    if any(character.isspace() for character in unquote(value)):
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
        and "?" not in value
        and "#" not in value
        and parsed.query == ""
        and parsed.fragment == ""
    )


def is_credential_material(value: object) -> bool:
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, (bytes, bytearray)):
        return bool(value)
    return False


def plist_key_name(key: object) -> str:
    return normalized_name(key)


def scan_plist(raw: bytes, display: str, findings: list[tuple[str, str]], artifact: bool) -> None:
    try:
        plist = plistlib.loads(raw)
    except Exception:
        report(findings, f"{display}:invalid-plist")
        return

    def visit(value: object, key_path: str) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                child_path = f"{key_path}.{key}" if key_path else str(key)
                if is_sensitive_name(key) and is_credential_material(child):
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


def looks_like_plist(raw: bytes) -> bool:
    prefix = raw.lstrip()
    if prefix.startswith(PLIST_BINARY_HEADER):
        return True
    prefix_window = prefix[:1024]
    if PLIST_XML_PATTERN.match(prefix_window) or PLIST_DOCTYPE_PATTERN.match(
        prefix_window
    ):
        return True
    if prefix_window.lower().startswith(b"<?xml") and (
        PLIST_XML_PATTERN.search(prefix_window)
        or PLIST_DOCTYPE_PATTERN.search(prefix_window)
        or PLIST_PROPERTY_DTD_PATTERN.search(prefix_window)
    ):
        return True
    # Executables and other binaries can embed plist-shaped string tables.
    # Scan their printable bytes, but do not parse the entire binary as a plist.
    if b"\x00" in raw:
        return False
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return bool(
        PLIST_XML_PATTERN.search(raw)
        or PLIST_DOCTYPE_PATTERN.search(raw)
        or PLIST_PROPERTY_DTD_PATTERN.search(raw)
    )


def scan_file(path: Path, display: str, findings: list[tuple[str, str]], artifact: bool) -> None:
    if not path.is_file():
        report(findings, f"{display}:unreadable")
        return
    try:
        raw = path.read_bytes()
    except OSError:
        report(findings, f"{display}:unreadable")
        return

    if path.suffix.lower() in PLIST_SUFFIXES or looks_like_plist(raw):
        scan_plist(raw, display, findings, artifact=artifact)
    scan_bytes(path, display, raw, findings)


def scan_artifact(
    path: Path,
    findings: list[tuple[str, str]],
    label: str = "artifact-1",
    walker=None,
) -> None:
    try:
        root_mode = path.lstat().st_mode
    except OSError:
        report(findings, f"{label}:missing")
        return

    if stat.S_ISREG(root_mode):
        scan_file(path, f"{label}:file-1", findings, artifact=True)
        return
    if not stat.S_ISDIR(root_mode) or stat.S_ISLNK(root_mode):
        report(findings, f"{label}:unreadable-root")
        return

    if walker is None:
        walker = os.walk

    directory_labels: dict[Path, str] = {path: f"{label}:dir-1"}
    next_directory_number = 2
    next_file_number = 1

    def directory_label(directory: Path) -> str:
        nonlocal next_directory_number
        if directory not in directory_labels:
            directory_labels[directory] = f"{label}:dir-{next_directory_number}"
            next_directory_number += 1
        return directory_labels[directory]

    current_directory_label = directory_label(path)

    def traversal_error(_error: OSError) -> None:
        report(findings, f"{current_directory_label}:unreadable")

    try:
        for directory, directories, filenames in walker(
            path,
            topdown=True,
            onerror=traversal_error,
            followlinks=False,
        ):
            directory_path = Path(directory)
            current_directory_label = directory_label(directory_path)
            directories.sort()
            filenames.sort()
            for name in list(directories):
                child = directory_path / name
                child_directory_label = directory_label(child)
                try:
                    child_mode = child.lstat().st_mode
                except OSError:
                    directories.remove(name)
                    report(
                        findings,
                        f"{child_directory_label}:unreadable",
                    )
                    continue
                if stat.S_ISLNK(child_mode):
                    directories.remove(name)
                    report(
                        findings,
                        f"{child_directory_label}:symlink",
                    )

            for name in filenames:
                child = directory_path / name
                display = f"{label}:file-{next_file_number}"
                next_file_number += 1
                try:
                    child_mode = child.lstat().st_mode
                except OSError:
                    report(findings, f"{display}:unreadable")
                    continue
                if stat.S_ISLNK(child_mode):
                    report(findings, f"{display}:symlink")
                    continue
                scan_file(child, display, findings, artifact=True)
    except OSError:
        report(findings, f"{current_directory_label}:unreadable")


def main() -> int:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--extra-file", action="append", default=[], type=Path)
    parser.add_argument("--artifact", action="append", default=[], type=Path)
    args = parser.parse_args()

    root = args.root.resolve()
    findings: list[tuple[str, str]] = []
    try:
        files = tracked_files(root)
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError):
        report(findings, "tracked:git-files")
        files = []

    for index, path in enumerate(files, start=1):
        scan_file(path, f"tracked-file-{index}", findings, artifact=False)
    for index, path in enumerate(args.extra_file, start=1):
        scan_file(path, f"extra-file-{index}", findings, artifact=False)
    for index, path in enumerate(args.artifact, start=1):
        scan_artifact(path, findings, label=f"artifact-{index}")

    for location, _ in sorted(set(findings)):
        print(location)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())

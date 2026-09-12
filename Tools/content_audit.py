#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path


PROHIBITED_EXTENSIONS = {
    ".ff", ".ipak", ".sabs", ".sabl", ".pkg", ".iso", ".xiso",
    ".self", ".sprx", ".psarc", ".pak",
}
PROHIBITED_FILENAMES = {"eboot.bin"}
PROHIBITED_DIR_NAMES = {
    "ps3_game", "raw_dump", "game-data", "game_data",
    "extracted-assets", "extracted_assets", "runtime-expressive-cache",
}
IGNORED_DIR_NAMES = {".git", ".build", "build", "deriveddata", ".swiftpm", "__pycache__"}
TEXT_EXTENSIONS = {
    ".swift", ".m", ".mm", ".h", ".hpp", ".c", ".cc", ".cpp", ".py",
    ".md", ".txt", ".json", ".yml", ".yaml", ".plist", ".xml", ".html",
    ".css", ".js", ".ts", ".sh", ".gitignore",
}
MAX_UNREVIEWED_BINARY_BYTES = 8 * 1024 * 1024


@dataclass(frozen=True, order=True)
class Finding:
    path: str
    reason: str


def _is_allowlisted(relative_path: str, allowlist: set[str]) -> bool:
    normalized = relative_path.replace("\\", "/")
    return normalized in {item.replace("\\", "/").lstrip("./") for item in allowlist}


def _read_prefix(path: Path, count: int = 16) -> bytes:
    try:
        with path.open("rb") as handle:
            return handle.read(count)
    except OSError:
        return b""


def scan_tree(root: Path, allowlist: set[str]) -> list[Finding]:
    root = root.resolve()
    findings: list[Finding] = []

    for path in sorted(root.rglob("*")):
        try:
            relative = path.relative_to(root)
        except ValueError:
            continue
        parts_lower = [part.lower() for part in relative.parts]

        if any(part in IGNORED_DIR_NAMES for part in parts_lower):
            continue
        rel_text = relative.as_posix()
        if _is_allowlisted(rel_text, allowlist):
            continue

        prohibited_dir = next((part for part in parts_lower[:-1] if part in PROHIBITED_DIR_NAMES), None)
        if prohibited_dir:
            findings.append(Finding(rel_text, f"prohibited directory: {prohibited_dir}"))
            continue

        if not path.is_file():
            continue

        name_lower = path.name.lower()
        suffix_lower = path.suffix.lower()

        if name_lower in PROHIBITED_FILENAMES:
            findings.append(Finding(rel_text, f"prohibited filename: {path.name}"))
            continue
        if suffix_lower in PROHIBITED_EXTENSIONS:
            findings.append(Finding(rel_text, f"prohibited extension: {suffix_lower}"))
            continue

        prefix = _read_prefix(path)
        if prefix.startswith(b"\x7fELF"):
            findings.append(Finding(rel_text, "ELF signature detected"))
            continue
        if prefix.startswith(b"\x7fPKG"):
            findings.append(Finding(rel_text, "PKG signature detected"))
            continue
        if prefix.startswith(b"SCE\x00"):
            findings.append(Finding(rel_text, "SELF/SCE signature detected"))
            continue

        try:
            size = path.stat().st_size
        except OSError:
            continue
        if size > MAX_UNREVIEWED_BINARY_BYTES and suffix_lower not in TEXT_EXTENSIONS:
            findings.append(Finding(rel_text, f"unreviewed binary larger than {MAX_UNREVIEWED_BINARY_BYTES} bytes"))

    return sorted(set(findings))


def _load_allowlist(path: Path | None) -> set[str]:
    if path is None or not path.exists():
        return set()
    return {
        line.strip().lstrip("./")
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit a source tree or app bundle for non-redistributable game content.")
    parser.add_argument("path", type=Path)
    parser.add_argument("--allowlist", type=Path, default=None)
    args = parser.parse_args()

    findings = scan_tree(args.path, _load_allowlist(args.allowlist))
    if findings:
        for finding in findings:
            print(f"FAIL {finding.path}: {finding.reason}")
        return 1
    print(f"PASS {args.path}: no prohibited content detected")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

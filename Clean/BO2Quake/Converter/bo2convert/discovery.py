from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
from pathlib import Path


@dataclass(frozen=True)
class SourceFile:
    relative_path: str
    size: int
    sha256: str
    suffix: str


@dataclass(frozen=True)
class SourceInventory:
    root: str
    files: tuple[SourceFile, ...]


def _hash_file(path: Path) -> str:
    h = sha256()
    with path.open('rb') as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def discover_dump(root: Path) -> SourceInventory:
    root = root.resolve()
    if not root.is_dir():
        raise ValueError(f'BO2 dump root is not a directory: {root}')

    files: list[SourceFile] = []
    for path in root.rglob('*'):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        files.append(
            SourceFile(
                relative_path=relative,
                size=path.stat().st_size,
                sha256=_hash_file(path),
                suffix=path.suffix.lower(),
            )
        )
    files.sort(key=lambda item: item.relative_path)
    return SourceInventory(root=str(root), files=tuple(files))

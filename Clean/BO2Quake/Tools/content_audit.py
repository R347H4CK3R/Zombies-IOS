from pathlib import Path
import sys

BLOCKED_SUFFIXES = {'.ff', '.ipak', '.sabs', '.xpak'}
BLOCKED_NAMES = {'GameData'}
BLOCKED_MARKERS = (b'TAff0100', b'IPAK')
TEXT_SOURCE_SUFFIXES = {
    '.py', '.swift', '.c', '.h', '.m', '.mm', '.metal', '.md', '.txt', '.json', '.yml', '.yaml', '.plist'
}
GENERATED_NAMES = {'__pycache__'}
GENERATED_SUFFIXES = {'.pyc', '.pyo'}


def scan(root: Path) -> list[str]:
    failures: list[str] = []
    for path in root.rglob('*'):
        if any(part in GENERATED_NAMES for part in path.parts):
            continue
        if path.is_dir() and path.name in BLOCKED_NAMES:
            failures.append(f'blocked directory: {path}')
            continue
        if not path.is_file():
            continue
        suffix = path.suffix.lower()
        if suffix in GENERATED_SUFFIXES:
            continue
        if suffix in BLOCKED_SUFFIXES:
            failures.append(f'blocked retail extension: {path}')
            continue
        if suffix in TEXT_SOURCE_SUFFIXES:
            continue
        try:
            head = path.read_bytes()[:512]
        except OSError:
            continue
        for marker in BLOCKED_MARKERS:
            if marker in head:
                failures.append(f'blocked retail signature {marker!r}: {path}')
                break
    return failures


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
    failures = scan(root)
    if failures:
        print('\n'.join(failures))
        return 1
    print(f'content audit passed: {root}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

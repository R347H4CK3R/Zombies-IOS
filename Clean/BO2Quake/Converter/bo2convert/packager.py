from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import shutil
import tempfile
import zipfile

from .completion import validate_completion


@dataclass(frozen=True)
class PackageReport:
    complete: bool
    output: Path
    embedded_files: int
    bytes_written: int


def _copy_tree(src: Path, dst: Path) -> int:
    count = 0
    for path in sorted(src.rglob('*')):
        rel = path.relative_to(src)
        target = dst / rel
        if path.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        elif path.is_file():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
            count += 1
    return count


def package_self_contained_ipa(
    app_bundle: Path | str,
    gamedata_root: Path | str,
    output_ipa: Path | str,
) -> PackageReport:
    app = Path(app_bundle)
    game = Path(gamedata_root)
    out = Path(output_ipa)

    if not app.is_dir() or app.suffix != '.app':
        raise ValueError('app_bundle must be an existing .app directory')
    completion = validate_completion(game)
    if not completion.complete:
        raise ValueError('GameData is incomplete: ' + '; '.join(completion.failures[:12]))

    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='bo2quake-package-') as td:
        root = Path(td)
        payload = root / 'Payload'
        payload.mkdir()
        staged_app = payload / app.name
        shutil.copytree(app, staged_app, symlinks=True)
        staged_game = staged_app / 'GameData'
        if staged_game.exists():
            shutil.rmtree(staged_game)
        staged_game.mkdir()
        game_files = _copy_tree(game, staged_game)

        tmp = out.with_suffix(out.suffix + '.part')
        if tmp.exists():
            tmp.unlink()
        with zipfile.ZipFile(tmp, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
            for path in sorted(payload.rglob('*')):
                if path.is_file():
                    zf.write(path, path.relative_to(root).as_posix())
        tmp.replace(out)

    return PackageReport(
        complete=True,
        output=out,
        embedded_files=game_files,
        bytes_written=out.stat().st_size,
    )

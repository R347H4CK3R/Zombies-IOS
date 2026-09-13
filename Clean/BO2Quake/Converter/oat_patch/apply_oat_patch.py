from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess

PINNED_OAT_COMMIT = 'dfcbc6e206551a4345d969c6abc596f4704627bd'
INCLUDE_LINE = '#include "BO2IOS/GfxWorldResolvedDumperT6.h"'
REGISTER_LINE = '    RegisterAssetDumper(std::make_unique<bo2_ios::gfx_world::ResolvedDumperT6>());'


def apply_patch(oat_root: Path, *, verify_commit: bool = True) -> None:
    oat_root = oat_root.resolve()
    if verify_commit:
        head = subprocess.check_output(['git', '-C', str(oat_root), 'rev-parse', 'HEAD'], text=True).strip()
        if head != PINNED_OAT_COMMIT:
            raise RuntimeError(f'OpenAssetTools commit mismatch: expected {PINNED_OAT_COMMIT}, got {head}')

    source_root = oat_root / 'src' / 'ObjWriting' / 'Game' / 'T6'
    obj_writer = source_root / 'ObjWriterT6.cpp'
    if not obj_writer.is_file():
        raise FileNotFoundError(obj_writer)

    patch_root = Path(__file__).resolve().parent
    target_dir = source_root / 'BO2IOS'
    target_dir.mkdir(parents=True, exist_ok=True)
    for name in ('GfxWorldResolvedDumperT6.h', 'GfxWorldResolvedDumperT6.cpp'):
        shutil.copy2(patch_root / name, target_dir / name)

    text = obj_writer.read_text(encoding='utf-8')
    if INCLUDE_LINE not in text:
        anchor = '#include "Game/T6/Maps/MapEntsDumperT6.h"'
        if anchor not in text:
            raise RuntimeError('ObjWriterT6 include anchor changed')
        text = text.replace(anchor, anchor + '\n' + INCLUDE_LINE, 1)

    if REGISTER_LINE not in text:
        anchor = '    RegisterAssetDumper(std::make_unique<map_ents::DumperT6>());'
        if anchor not in text:
            raise RuntimeError('ObjWriterT6 register anchor changed')
        text = text.replace(anchor, anchor + '\n' + REGISTER_LINE, 1)

    obj_writer.write_text(text, encoding='utf-8')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('oat_root', type=Path)
    parser.add_argument('--no-verify-commit', action='store_true')
    args = parser.parse_args()
    apply_patch(args.oat_root, verify_commit=not args.no_verify_commit)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

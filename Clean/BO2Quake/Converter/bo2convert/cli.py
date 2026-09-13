from __future__ import annotations

import argparse
from pathlib import Path

from .discovery import discover_dump
from .ledger import ConversionLedger
from .manifest import write_source_manifest


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Convert a complete BO2 PS3 dump into BO2 Quake GameData.')
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    inventory = discover_dump(args.source)
    args.output.mkdir(parents=True, exist_ok=True)
    write_source_manifest(inventory, args.output / 'source-inventory.json')
    ConversionLedger.open(args.output / 'conversion-state.json').save()
    print(f'discovered {len(inventory.files)} files')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

from __future__ import annotations

import json
from pathlib import Path

from .discovery import SourceInventory


def write_source_manifest(inventory: SourceInventory, path: Path) -> None:
    payload = {
        'version': 1,
        'root': inventory.root,
        'files': [
            {
                'path': item.relative_path,
                'size': item.size,
                'sha256': item.sha256,
                'suffix': item.suffix,
            }
            for item in inventory.files
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, sort_keys=True, indent=2) + '\n')

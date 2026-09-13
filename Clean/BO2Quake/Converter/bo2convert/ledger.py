from __future__ import annotations

from dataclasses import dataclass, field
import json
from pathlib import Path
from typing import Any


@dataclass
class ConversionLedger:
    path: Path
    records: dict[str, dict[str, Any]] = field(default_factory=dict)

    @classmethod
    def open(cls, path: Path) -> 'ConversionLedger':
        if path.exists():
            raw = json.loads(path.read_text())
            return cls(path=path, records=dict(raw.get('records', {})))
        return cls(path=path)

    def is_current(self, source_hash: str, converter_version: str) -> bool:
        for record in self.records.values():
            if (
                record.get('status') == 'complete'
                and record.get('sourceHash') == source_hash
                and record.get('converterVersion') == converter_version
            ):
                return True
        return False

    def record_success(
        self,
        key: str,
        source_hash: str,
        converter_version: str,
        outputs: list[str],
    ) -> None:
        self.records[key] = {
            'status': 'complete',
            'sourceHash': source_hash,
            'converterVersion': converter_version,
            'outputs': list(outputs),
        }

    def record_failure(
        self,
        key: str,
        source_hash: str,
        converter_version: str,
        error: str,
    ) -> None:
        self.records[key] = {
            'status': 'failed',
            'sourceHash': source_hash,
            'converterVersion': converter_version,
            'error': error,
            'outputs': [],
        }

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {'version': 1, 'records': self.records}
        self.path.write_text(json.dumps(payload, sort_keys=True, indent=2) + '\n')

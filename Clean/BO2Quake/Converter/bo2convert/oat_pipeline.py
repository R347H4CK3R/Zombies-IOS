from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .discovery import SourceInventory
from .ledger import ConversionLedger
from .oat_backend import OATBackend

CONVERTER_VERSION = 'oat-batch-v1'


@dataclass(frozen=True)
class OATBatchResult:
    complete: bool
    zones_processed: int
    zones_skipped: int
    zones_failed: int
    outputs: tuple[Path, ...]
    failures: tuple[str, ...]


def _zone_output_dir(staging_root: Path, relative_path: str) -> Path:
    rel = Path(relative_path)
    # Preserve source hierarchy and isolate each FastFile by stem.
    return staging_root / rel.parent / rel.stem


def extract_fastfiles(
    inventory: SourceInventory,
    *,
    source_root: Path | str,
    staging_root: Path | str,
    backend: OATBackend,
    ledger: ConversionLedger,
) -> OATBatchResult:
    source = Path(source_root).resolve()
    staging = Path(staging_root)
    processed = skipped = failed = 0
    outputs: list[Path] = []
    failures: list[str] = []

    fastfiles = [item for item in inventory.files if item.suffix == '.ff']
    for item in fastfiles:
        key = 'oat:' + item.relative_path
        if ledger.is_current(item.sha256, CONVERTER_VERSION):
            skipped += 1
            record = ledger.records.get(key)
            if record:
                outputs.extend(Path(p) for p in record.get('outputs', []))
            continue

        zone = source / Path(item.relative_path)
        destination = _zone_output_dir(staging, item.relative_path)
        result = backend.dump_zone(
            zone,
            destination,
            expected_globs=[],
            search_path=zone.parent,
            image_format='dds',
            model_format='glb',
        )
        if not result.complete:
            failed += 1
            message = '; '.join(result.failures) or f'OpenAssetTools failed for {item.relative_path}'
            failures.append(f'{item.relative_path}: {message}')
            ledger.record_failure(key, item.sha256, CONVERTER_VERSION, message)
            ledger.save()
            continue

        processed += 1
        normalized = [str(path) for path in result.outputs]
        outputs.extend(result.outputs)
        ledger.record_success(key, item.sha256, CONVERTER_VERSION, normalized)
        ledger.save()

    return OATBatchResult(
        complete=failed == 0,
        zones_processed=processed,
        zones_skipped=skipped,
        zones_failed=failed,
        outputs=tuple(outputs),
        failures=tuple(failures),
    )

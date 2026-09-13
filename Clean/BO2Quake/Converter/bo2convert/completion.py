from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path, PurePosixPath

REQUIRED_FAMILIES = (
    'worlds', 'materials', 'textures', 'models', 'animations', 'audio',
    'weapons', 'entities', 'scripts', 'gamemodes', 'ui',
)
RETAIL_EXTENSIONS = {'.ff', '.ipak', '.sabs', '.sabl', '.self', '.bin'}


@dataclass(frozen=True)
class CompletionResult:
    complete: bool
    failures: tuple[str, ...]
    family_counts: dict[str, int]


def _safe_payload(root: Path, raw: str) -> Path:
    pure = PurePosixPath(raw)
    if pure.is_absolute() or '..' in pure.parts:
        raise ValueError(f'unsafe payload path: {raw}')
    return root.joinpath(*pure.parts)


def validate_completion(gamedata_root: Path | str) -> CompletionResult:
    root = Path(gamedata_root)
    failures: list[str] = []
    counts = {name: 0 for name in REQUIRED_FAMILIES}
    manifest_path = root / 'manifest.json'
    if not manifest_path.is_file():
        return CompletionResult(False, ('missing GameData/manifest.json',), counts)

    try:
        manifest = json.loads(manifest_path.read_text('utf-8'))
    except Exception as exc:
        return CompletionResult(False, (f'invalid GameData manifest: {exc}',), counts)

    if int(manifest.get('formatVersion', 0)) != 1:
        failures.append('unsupported GameData formatVersion')

    conversion_failures = list(manifest.get('conversionFailures') or [])
    unsupported = list(manifest.get('unsupportedSemantics') or [])
    if conversion_failures:
        failures.append(f'conversion failure count: {len(conversion_failures)}')
    if unsupported:
        failures.append(f'unsupported semantic count: {len(unsupported)}')

    assets = manifest.get('assets')
    if not isinstance(assets, list):
        failures.append('manifest assets must be an array')
        assets = []

    ids: set[str] = set()
    for index, asset in enumerate(assets):
        if not isinstance(asset, dict):
            failures.append(f'asset {index} is not an object')
            continue
        asset_id = str(asset.get('id', ''))
        kind = str(asset.get('kind', ''))
        if not asset_id:
            failures.append(f'asset {index} has no id')
        elif asset_id in ids:
            failures.append(f'duplicate asset id: {asset_id}')
        ids.add(asset_id)
        if kind in counts:
            counts[kind] += 1
        if asset.get('validation') != 'complete':
            failures.append(f'asset not complete: {asset_id or index}')
        payloads = asset.get('payloads') or []
        if not payloads:
            failures.append(f'asset has no payloads: {asset_id or index}')
        for raw in payloads:
            try:
                payload = _safe_payload(root, str(raw))
            except ValueError as exc:
                failures.append(str(exc)); continue
            if not payload.is_file():
                failures.append(f'missing payload: {raw}')
                continue
            suffix = payload.suffix.lower()
            if suffix in RETAIL_EXTENSIONS:
                failures.append(f'raw retail container not allowed in GameData: {raw}')

    for family, count in counts.items():
        if count == 0:
            failures.append(f'missing required asset family: {family}')

    dependency_ids = {str(asset.get('id')) for asset in assets if isinstance(asset, dict) and asset.get('id')}
    for asset in assets:
        if not isinstance(asset, dict):
            continue
        for dep in asset.get('dependencies') or []:
            if dep not in dependency_ids:
                failures.append(f"unresolved dependency: {asset.get('id', '?')} -> {dep}")

    return CompletionResult(not failures, tuple(failures), counts)

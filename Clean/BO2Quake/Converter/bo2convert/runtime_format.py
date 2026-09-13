from __future__ import annotations

from hashlib import sha256
import json
from pathlib import Path
from typing import Iterable

PACKAGE_DIRS = {
    'world': 'worlds',
    'material': 'materials',
    'texture': 'textures',
    'model': 'models',
    'animation': 'animations',
    'audio': 'audio',
    'weapon': 'weapons',
    'entity': 'entities',
    'script': 'scripts',
    'gamemode': 'gamemodes',
    'ui': 'ui',
}
FORMAT_VERSION = 1


def _safe_id(asset_id: str) -> str:
    return ''.join(ch if ch.isalnum() or ch in ('-', '_', '.') else '_' for ch in asset_id)


def _digest(data: bytes) -> str:
    return sha256(data).hexdigest()


class GameDataBuilder:
    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        for directory in PACKAGE_DIRS.values():
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        self.assets: dict[str, dict] = {}

    def add_asset(
        self,
        asset_id: str,
        kind: str,
        source_hash: str,
        dependencies: Iterable[str],
        payloads: dict[str, bytes],
        *,
        version: int = 1,
    ) -> dict:
        if kind not in PACKAGE_DIRS:
            raise ValueError(f'unsupported runtime asset kind: {kind}')
        if len(source_hash) != 64:
            raise ValueError('source_hash must be SHA-256 hex')
        if not payloads:
            raise ValueError('runtime asset requires at least one payload')

        folder = self.root / PACKAGE_DIRS[kind] / _safe_id(asset_id)
        folder.mkdir(parents=True, exist_ok=True)
        payload_records: list[dict] = []
        for name, data in sorted(payloads.items()):
            filename = _safe_id(name)
            target = folder / filename
            target.write_bytes(data)
            payload_records.append({
                'name': name,
                'path': target.relative_to(self.root).as_posix(),
                'size': len(data),
                'sha256': _digest(data),
            })

        record = {
            'id': asset_id,
            'kind': kind,
            'version': version,
            'sourceHash': source_hash,
            'dependencies': sorted(set(dependencies)),
            'payloads': payload_records,
            'validation': 'complete',
        }
        self.assets[asset_id] = record
        return record

    def finalize(self, required_classes: Iterable[str]) -> dict:
        required = sorted(set(required_classes))
        manifest = _build_manifest(self.root, self.assets, required)
        (self.root / 'manifest.json').write_text(
            json.dumps(manifest, sort_keys=True, separators=(',', ':')) + '\n'
        )
        return manifest


def _build_manifest(root: Path, assets: dict[str, dict], required_classes: list[str]) -> dict:
    failures: list[str] = []
    present_ids = set(assets)
    by_kind: dict[str, int] = {}
    for asset_id in sorted(assets):
        asset = assets[asset_id]
        by_kind[asset['kind']] = by_kind.get(asset['kind'], 0) + 1
        for dependency in asset['dependencies']:
            if dependency not in present_ids:
                failures.append(f'{asset_id}: missing dependency {dependency}')

    completion = {
        kind: {
            'required': True,
            'assetCount': by_kind.get(kind, 0),
            'complete': by_kind.get(kind, 0) > 0,
        }
        for kind in required_classes
    }
    for kind, state in completion.items():
        if not state['complete']:
            failures.append(f'missing required asset class {kind}')

    return {
        'formatVersion': FORMAT_VERSION,
        'assets': [assets[key] for key in sorted(assets)],
        'completion': completion,
        'failures': sorted(failures),
        'complete': not failures,
    }


def validate_gamedata(root: Path) -> dict:
    manifest_path = root / 'manifest.json'
    failures: list[str] = []
    if not manifest_path.is_file():
        return {'complete': False, 'failures': ['manifest.json missing']}
    try:
        manifest = json.loads(manifest_path.read_text())
    except Exception as exc:
        return {'complete': False, 'failures': [f'manifest parse failed: {exc}']}

    if manifest.get('formatVersion') != FORMAT_VERSION:
        failures.append(f'unsupported formatVersion {manifest.get("formatVersion")}')

    assets = {asset.get('id'): asset for asset in manifest.get('assets', []) if asset.get('id')}
    for asset_id, asset in assets.items():
        for dependency in asset.get('dependencies', []):
            if dependency not in assets:
                failures.append(f'{asset_id}: missing dependency {dependency}')
        for payload in asset.get('payloads', []):
            relative = payload.get('path', '')
            target = root / relative
            if not target.is_file():
                failures.append(f'{asset_id}: missing payload {relative}')
                continue
            data = target.read_bytes()
            if len(data) != payload.get('size'):
                failures.append(f'{asset_id}: size mismatch {relative}')
            if _digest(data) != payload.get('sha256'):
                failures.append(f'{asset_id}: hash mismatch {relative}')

    for kind, state in manifest.get('completion', {}).items():
        if state.get('required') and not state.get('complete'):
            failures.append(f'missing required asset class {kind}')

    failures.extend(str(item) for item in manifest.get('failures', []))
    failures = sorted(set(failures))
    return {'complete': not failures, 'failures': failures}

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path


@dataclass(frozen=True)
class WeaponExportResult:
    payloads: tuple[str, ...]
    dependencies: tuple[str, ...]


def parse_info_string(text: str) -> tuple[str, dict[str, str]]:
    fields = text.strip().split('\\')
    if not fields or not fields[0]:
        raise ValueError('empty info string')
    prefix = fields[0]
    rest = fields[1:]
    if len(rest) % 2:
        raise ValueError('info string has key without value')
    values: dict[str, str] = {}
    for i in range(0, len(rest), 2):
        key, value = rest[i], rest[i + 1]
        if not key:
            raise ValueError('info string has empty key')
        values[key] = value
    return prefix, values


def _required_int(values: dict[str, str], *names: str) -> int:
    for name in names:
        raw = values.get(name)
        if raw not in (None, ''):
            try:
                return int(float(raw))
            except ValueError as exc:
                raise ValueError(f'invalid integer weapon field {name}={raw!r}') from exc
    raise ValueError(f'missing required weapon field: {"/".join(names)}')


def _required_float(values: dict[str, str], label: str, *names: str) -> float:
    for name in names:
        raw = values.get(name)
        if raw not in (None, ''):
            try:
                return float(raw)
            except ValueError as exc:
                raise ValueError(f'invalid float weapon field {name}={raw!r}') from exc
    raise ValueError(f'missing required weapon {label}: {"/".join(names)}')


def _optional_int(values: dict[str, str], names: tuple[str, ...], default: int) -> int:
    for name in names:
        raw = values.get(name)
        if raw not in (None, ''):
            try:
                return int(float(raw))
            except ValueError as exc:
                raise ValueError(f'invalid integer weapon field {name}={raw!r}') from exc
    return default


def _optional_float(values: dict[str, str], names: tuple[str, ...]) -> float | None:
    for name in names:
        raw = values.get(name)
        if raw not in (None, ''):
            try:
                return float(raw)
            except ValueError as exc:
                raise ValueError(f'invalid float weapon field {name}={raw!r}') from exc
    return None


def _dependencies(values: dict[str, str]) -> tuple[str, ...]:
    deps: set[str] = set()
    for key, value in values.items():
        if not value or value in {'none', 'null'}:
            continue
        lower = key.lower()
        if 'model' in lower:
            deps.add(f'models:{value}')
        elif lower.endswith('anim') or 'anim' in lower:
            deps.add(f'animations:{value}')
        elif 'sound' in lower and 'map' not in lower:
            deps.add(f'audio:{value}')
        elif lower.endswith('fx') or 'effect' in lower:
            deps.add(f'effects:{value}')
        elif 'material' in lower or 'reticle' in lower or lower.endswith('icon'):
            deps.add(f'materials:{value}')
    return tuple(sorted(deps))


def export_weapon(info_text: str, destination: Path | str, *, weapon_id: str) -> WeaponExportResult:
    prefix, values = parse_info_string(info_text)
    clip_size = _required_int(values, 'iClipSize', 'clipSize')
    max_ammo = _required_int(values, 'iMaxAmmo', 'maxAmmo')
    fire_ms = _required_int(values, 'iFireTime', 'fireTime')
    reload_ms = _required_int(values, 'iReloadTime', 'reloadTime')
    damage = _required_int(values, 'damage', 'iDamage')
    min_damage = _required_int(values, 'minDamage', 'iMinDamage')
    max_damage_range = _required_float(values, 'damage range', 'maxDamageRange', 'fMaxDamageRange')
    min_damage_range = _required_float(values, 'damage range', 'minDamageRange', 'fMinDamageRange')
    if clip_size <= 0 or max_ammo < clip_size or fire_ms <= 0 or reload_ms <= 0 or damage < 0 or min_damage < 0:
        raise ValueError('invalid core weapon values')
    if max_damage_range <= 0 or min_damage_range < max_damage_range:
        raise ValueError('invalid weapon damage range')

    deps = _dependencies(values)
    data = {
        'formatVersion': 2,
        'id': weapon_id,
        'sourcePrefix': prefix,
        'displayName': values.get('displayName', weapon_id),
        'clipSize': clip_size,
        'maxAmmo': max_ammo,
        'fireIntervalMs': fire_ms,
        'reloadTimeMs': reload_ms,
        'reloadEmptyTimeMs': _optional_int(values, ('iReloadEmptyTime','reloadEmptyTime'), reload_ms),
        'damage': damage,
        'minDamage': min_damage,
        'maxDamageRange': max_damage_range,
        'minDamageRange': min_damage_range,
        'shotCount': _optional_int(values, ('shotCount',), 1),
        'fireType': values.get('fireType', ''),
        'weaponType': values.get('weaponType', ''),
        'weaponClass': values.get('weaponClass', ''),
        'adsTransInMs': _optional_int(values, ('adsTransInTime',), 0),
        'adsTransOutMs': _optional_int(values, ('adsTransOutTime',), 0),
        'adsZoomFov': _optional_float(values, ('adsZoomFov1',)),
        'gunModel': values.get('gunModel', ''),
        'handModel': values.get('handModel', ''),
        'fireAnim': values.get('fireAnim', ''),
        'reloadAnim': values.get('reloadAnim', ''),
        'reloadEmptyAnim': values.get('reloadEmptyAnim', ''),
        'idleAnim': values.get('idleAnim', ''),
        'adsFireAnim': values.get('adsFireAnim', ''),
        'adsUpAnim': values.get('adsUpAnim', ''),
        'adsDownAnim': values.get('adsDownAnim', ''),
        'fireSound': values.get('fireSound', ''),
        'reloadSound': values.get('reloadSound', ''),
        'ammoName': values.get('ammoName', ''),
        'clipName': values.get('clipName', ''),
        'dependencies': list(deps),
        'raw': dict(sorted(values.items())),
    }
    out = Path(destination)
    out.mkdir(parents=True, exist_ok=True)
    (out / 'weapon.json').write_text(json.dumps(data, sort_keys=True, separators=(',', ':')) + '\n', encoding='utf-8')
    return WeaponExportResult(('weapon.json',), deps)

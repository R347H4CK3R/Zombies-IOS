from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re

_PAIR = re.compile(r'^\s*"((?:\\.|[^"])*)"\s+"((?:\\.|[^"])*)"\s*$')

@dataclass(frozen=True)
class MapEntsExportResult:
    payloads: tuple[str, ...]
    dependencies: tuple[str, ...]


def _unescape(value: str) -> str:
    return value.replace('\\"', '"').replace('\\\\', '\\')


def _vec3(value: str) -> list[float]:
    parts = value.split()
    if len(parts) != 3:
        raise ValueError(f'invalid vec3: {value}')
    x, y, z = (float(v) for v in parts)
    # BO2 Z-up -> runtime Y-up.
    return [x, z, -y]


def parse_mapents(text: str) -> list[dict]:
    entities: list[dict] = []
    current: dict[str, object] | None = None
    for line_no, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith('//'):
            continue
        if line == '{':
            if current is not None:
                raise ValueError(f'nested entity at line {line_no}')
            current = {}
            continue
        if line == '}':
            if current is None:
                raise ValueError(f'unmatched closing brace at line {line_no}')
            if 'classname' not in current:
                raise ValueError(f'entity ending line {line_no} has no classname')
            entities.append(current); current = None
            continue
        if current is None:
            raise ValueError(f'entity key outside braces at line {line_no}')
        match = _PAIR.fullmatch(line)
        if not match:
            raise ValueError(f'invalid entity key/value at line {line_no}: {line}')
        key, value = _unescape(match.group(1)), _unescape(match.group(2))
        if key in current:
            raise ValueError(f'duplicate entity key {key!r} at line {line_no}')
        if key == 'origin':
            current[key] = _vec3(value)
        elif key == 'angles':
            current[key] = [float(v) for v in value.split()]
            if len(current[key]) != 3:
                raise ValueError(f'invalid angles at line {line_no}')
        elif key in {'modelscale','modelscale_vec'}:
            current[key] = value
        else:
            current[key] = value
    if current is not None:
        raise ValueError('unterminated entity')
    return entities


def export_mapents(text: str, destination: Path | str, *, map_id: str) -> MapEntsExportResult:
    entities = parse_mapents(text)
    spawns, models, triggers, objectives = [], [], [], []
    deps: set[str] = set()
    objective_prefixes = ('ctf_flag_', 'sd_', 'dom_', 'hq_', 'koth_', 'hardpoint_')
    spawn_names = {'mp_dm_spawn','mp_tdm_spawn','mp_ctf_spawn_allies','mp_ctf_spawn_axis','mp_sd_spawn_attacker','mp_sd_spawn_defender'}

    for index, entity in enumerate(entities):
        cls = str(entity.get('classname',''))
        model = str(entity.get('model',''))
        record = {'entityIndex': index, **entity}
        if cls in spawn_names or cls.endswith('_spawn'):
            spawns.append(record)
        if cls == 'script_model' and model and not model.startswith('*'):
            models.append(record); deps.add(f'models:{model}')
        if cls.startswith('trigger_') or cls.endswith('_trig') or cls == 'bombtrigger':
            triggers.append(record)
        if cls.startswith(objective_prefixes) or cls in {'bombtrigger'}:
            objectives.append(record)
        if cls == 'worldspawn':
            sky = str(entity.get('skyboxmodel',''))
            if sky: deps.add(f'models:{sky}')

    payload = {
        'formatVersion': 1,
        'map': map_id,
        'coordinateSystem': 'rhs-y-up-xz-neg-y',
        'entityCount': len(entities),
        'entities': entities,
        'spawns': spawns,
        'scriptModels': models,
        'triggers': triggers,
        'objectives': objectives,
    }
    out = Path(destination); out.mkdir(parents=True, exist_ok=True)
    (out/'entities.json').write_text(json.dumps(payload, sort_keys=True, separators=(',', ':'))+'\n', encoding='utf-8')
    return MapEntsExportResult(('entities.json',), tuple(sorted(deps)))

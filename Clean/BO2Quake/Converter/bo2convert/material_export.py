from __future__ import annotations

from dataclasses import dataclass
import json
from typing import Mapping, Sequence

SUPPORTED_RENDER_CLASSES = {'opaque', 'alpha_test', 'blended'}
SUPPORTED_CULL = {'back', 'front', 'none'}


@dataclass(frozen=True)
class MaterialTextureBinding:
    semantic: str
    texture_id: str
    name_hash: int
    sampler_state: int


@dataclass(frozen=True)
class MaterialPayloadResult:
    payloads: dict[str, bytes]
    dependencies: tuple[str, ...]


def build_material_payloads(
    *,
    material_name: str,
    technique_set: str,
    render_class: str,
    textures: Sequence[MaterialTextureBinding],
    state_bits: Mapping[str, object],
) -> MaterialPayloadResult:
    if not material_name:
        raise ValueError('material name is required')
    if not technique_set:
        raise ValueError('material technique set is required')
    if render_class not in SUPPORTED_RENDER_CLASSES:
        raise ValueError(f'unsupported material render class: {render_class}')

    semantics: set[str] = set()
    texture_records: list[dict] = []
    dependencies: set[str] = set()
    for binding in textures:
        if not binding.semantic:
            raise ValueError('texture semantic is required')
        if binding.semantic in semantics:
            raise ValueError(f'duplicate texture semantic: {binding.semantic}')
        semantics.add(binding.semantic)
        if not binding.texture_id:
            raise ValueError(f'empty texture id for semantic {binding.semantic}')
        if not 0 <= int(binding.name_hash) <= 0xFFFFFFFF:
            raise ValueError('texture name hash exceeds UInt32')
        if not 0 <= int(binding.sampler_state) <= 0xFF:
            raise ValueError('texture sampler state exceeds UInt8')
        dependencies.add(binding.texture_id)
        texture_records.append({
            'semantic': binding.semantic,
            'texture': binding.texture_id,
            'nameHash': int(binding.name_hash),
            'samplerState': int(binding.sampler_state),
        })

    normalized_state = dict(state_bits)
    cull = normalized_state.get('cull')
    if cull is not None and cull not in SUPPORTED_CULL:
        raise ValueError(f'unsupported cull mode: {cull}')
    for key in ('depthWrite', 'depthTest'):
        if key in normalized_state and not isinstance(normalized_state[key], bool):
            raise ValueError(f'{key} must be boolean')

    payload = {
        'formatVersion': 1,
        'name': material_name,
        'techniqueSet': technique_set,
        'renderClass': render_class,
        'textures': texture_records,
        'stateBits': normalized_state,
    }
    encoded = (json.dumps(payload, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')
    return MaterialPayloadResult(
        payloads={'material.json': encoded},
        dependencies=tuple(sorted(dependencies)),
    )

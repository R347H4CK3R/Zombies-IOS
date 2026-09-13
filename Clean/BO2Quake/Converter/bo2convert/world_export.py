from __future__ import annotations

from dataclasses import dataclass
import json
import struct
from typing import Mapping, Sequence

from .t6.gfxworld import (
    GfxSurfaceRecord,
    WorldVertexData0,
    WorldVertexData1,
    read_surface_source_indices,
    remap_surface_indices,
)

RUNTIME_VERTEX_STRIDE = 44


@dataclass(frozen=True)
class WorldPayloadResult:
    payloads: dict[str, bytes]
    dependencies: tuple[str, ...]
    vertex_count: int
    index_count: int
    surface_count: int


def _encode_vertex(v0: WorldVertexData0, v1: WorldVertexData1) -> bytes:
    return struct.pack(
        '<3ff4B4fII',
        v0.position[0], v0.position[1], v0.position[2],
        v0.binormal_sign,
        v0.color[0], v0.color[1], v0.color[2], v0.color[3],
        v0.uv[0], v0.uv[1],
        v0.lightmap_uv[0], v0.lightmap_uv[1],
        v1.normal_packed,
        v1.tangent_packed,
    )


def build_world_payloads(
    vertices0: Sequence[WorldVertexData0],
    vertices1: Sequence[WorldVertexData1],
    source_index_data: bytes,
    surfaces: Sequence[GfxSurfaceRecord],
    material_bindings: Mapping[int, str],
    *,
    endian: str = '>',
) -> WorldPayloadResult:
    if endian not in ('>', '<'):
        raise ValueError('endian must be > or <')
    if len(vertices0) != len(vertices1):
        raise ValueError('T6 world vertex streams have different counts')
    if not surfaces:
        raise ValueError('world contains no render surfaces')

    vertex_blob = bytearray()
    runtime_indices: list[int] = []
    surface_records: list[dict] = []
    dependencies: set[str] = set()
    runtime_vertex_count = 0

    for surface_index, surface in enumerate(surfaces):
        if surface.material_ref not in material_bindings:
            raise ValueError(
                f'unresolved material reference 0x{surface.material_ref:08X} '
                f'for surface {surface_index}'
            )
        material_id = material_bindings[surface.material_ref]
        if not material_id:
            raise ValueError(f'empty material binding for surface {surface_index}')

        first = surface.first_vertex
        end = first + surface.vertex_count
        if first < 0 or end > len(vertices0):
            raise ValueError(f'surface {surface_index} vertex range outside world vertex buffers')

        runtime_first_vertex = runtime_vertex_count
        for v0, v1 in zip(vertices0[first:end], vertices1[first:end]):
            vertex_blob.extend(_encode_vertex(v0, v1))
        runtime_vertex_count += surface.vertex_count

        source_indices = read_surface_source_indices(source_index_data, surface, endian)
        mapped = remap_surface_indices(
            source_indices,
            first_vertex=surface.first_vertex,
            vertex_count=surface.vertex_count,
            base_output=runtime_first_vertex,
        )
        runtime_first_index = len(runtime_indices)
        runtime_indices.extend(mapped)
        dependencies.add(material_id)

        surface_records.append({
            'sourceSurface': surface_index,
            'firstVertex': runtime_first_vertex,
            'vertexCount': surface.vertex_count,
            'firstIndex': runtime_first_index,
            'indexCount': len(mapped),
            'triangleCount': surface.triangle_count,
            'material': material_id,
            'lightmapIndex': surface.lightmap_index,
            'reflectionProbeIndex': surface.reflection_probe_index,
            'primaryLightIndex': surface.primary_light_index,
            'flags': surface.flags,
            'mins': list(surface.mins),
            'maxs': list(surface.maxs),
        })

    if any(index < 0 or index > 0xFFFFFFFF for index in runtime_indices):
        raise ValueError('runtime index exceeds UInt32')
    index_blob = struct.pack('<' + ('I' * len(runtime_indices)), *runtime_indices)

    metadata = {
        'formatVersion': 1,
        'vertexStride': RUNTIME_VERTEX_STRIDE,
        'vertexCount': runtime_vertex_count,
        'indexType': 'uint32',
        'indexCount': len(runtime_indices),
        'surfaceCount': len(surface_records),
        'coordinateSystem': 'right-handed-y-up-x-z-negY-from-t6',
        'surfaces': surface_records,
    }
    metadata_blob = (json.dumps(metadata, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')

    return WorldPayloadResult(
        payloads={
            'vertices.bin': bytes(vertex_blob),
            'indices.bin': index_blob,
            'surfaces.json': metadata_blob,
        },
        dependencies=tuple(sorted(dependencies)),
        vertex_count=runtime_vertex_count,
        index_count=len(runtime_indices),
        surface_count=len(surface_records),
    )

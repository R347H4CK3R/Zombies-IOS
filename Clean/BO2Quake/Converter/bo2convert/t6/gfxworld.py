from __future__ import annotations

from dataclasses import dataclass
import struct
from typing import Iterable

VERTEX_DATA0_STRIDE = 36
VERTEX_DATA1_STRIDE = 8
GFX_SURFACE_STRIDE = 0x50


@dataclass(frozen=True)
class WorldVertexData0:
    position: tuple[float, float, float]
    binormal_sign: float
    color: tuple[int, int, int, int]
    uv: tuple[float, float]
    lightmap_uv: tuple[float, float]


@dataclass(frozen=True)
class WorldVertexData1:
    normal_packed: int
    tangent_packed: int


@dataclass(frozen=True)
class GfxSurfaceRecord:
    mins: tuple[float, float, float]
    maxs: tuple[float, float, float]
    vertex_data_offset0: int
    vertex_data_offset1: int
    first_vertex: int
    himip_radius_inv_sq: float
    vertex_count: int
    triangle_count: int
    base_index: int
    material_ref: int
    lightmap_index: int
    reflection_probe_index: int
    primary_light_index: int
    flags: int


def _runtime_position(x: float, y: float, z: float) -> tuple[float, float, float]:
    # T6 is Z-up; the clean runtime is Y-up and preserves BO2 world scale.
    return (x, z, -y)


def decode_vertex_data0(data: bytes, endian: str = '>') -> list[WorldVertexData0]:
    if endian not in ('>', '<'):
        raise ValueError('endian must be > or <')
    if len(data) % VERTEX_DATA0_STRIDE:
        raise ValueError('vertex data 0 length is not a multiple of 36 bytes')
    out: list[WorldVertexData0] = []
    fmt = endian + '3ff4B4f'
    for offset in range(0, len(data), VERTEX_DATA0_STRIDE):
        x, y, z, sign, r, g, b, a, u, v, lu, lv = struct.unpack_from(fmt, data, offset)
        out.append(WorldVertexData0(
            position=_runtime_position(x, y, z),
            binormal_sign=sign,
            color=(r, g, b, a),
            uv=(u, v),
            lightmap_uv=(lu, lv),
        ))
    return out


def decode_vertex_data1(data: bytes, endian: str = '>') -> list[WorldVertexData1]:
    if endian not in ('>', '<'):
        raise ValueError('endian must be > or <')
    if len(data) % VERTEX_DATA1_STRIDE:
        raise ValueError('vertex data 1 length is not a multiple of 8 bytes')
    out: list[WorldVertexData1] = []
    for offset in range(0, len(data), VERTEX_DATA1_STRIDE):
        normal, tangent = struct.unpack_from(endian + 'II', data, offset)
        out.append(WorldVertexData1(normal_packed=normal, tangent_packed=tangent))
    return out


def parse_surface(data: bytes, offset: int = 0, endian: str = '>') -> GfxSurfaceRecord:
    if offset < 0 or offset + GFX_SURFACE_STRIDE > len(data):
        raise ValueError('surface record outside buffer')
    mins = struct.unpack_from(endian + '3f', data, offset)
    vertex_data_offset0 = struct.unpack_from(endian + 'i', data, offset + 0x0C)[0]
    maxs = struct.unpack_from(endian + '3f', data, offset + 0x10)
    vertex_data_offset1 = struct.unpack_from(endian + 'i', data, offset + 0x1C)[0]
    first_vertex = struct.unpack_from(endian + 'i', data, offset + 0x20)[0]
    himip_radius_inv_sq = struct.unpack_from(endian + 'f', data, offset + 0x24)[0]
    vertex_count, triangle_count = struct.unpack_from(endian + 'HH', data, offset + 0x28)
    base_index = struct.unpack_from(endian + 'I', data, offset + 0x2C)[0]
    material_ref = struct.unpack_from(endian + 'I', data, offset + 0x30)[0]
    lightmap_index, reflection_probe_index, primary_light_index, flags = struct.unpack_from('4B', data, offset + 0x34)

    if first_vertex < 0 or vertex_count < 3 or triangle_count < 1:
        raise ValueError('invalid T6 surface counts')
    if not all(value == value and abs(value) < 2_000_000 for value in (*mins, *maxs)):
        raise ValueError('invalid T6 surface bounds')
    return GfxSurfaceRecord(
        mins=tuple(mins),
        maxs=tuple(maxs),
        vertex_data_offset0=vertex_data_offset0,
        vertex_data_offset1=vertex_data_offset1,
        first_vertex=first_vertex,
        himip_radius_inv_sq=himip_radius_inv_sq,
        vertex_count=vertex_count,
        triangle_count=triangle_count,
        base_index=base_index,
        material_ref=material_ref,
        lightmap_index=lightmap_index,
        reflection_probe_index=reflection_probe_index,
        primary_light_index=primary_light_index,
        flags=flags,
    )


def parse_surfaces(data: bytes, count: int, *, offset: int = 0, endian: str = '>') -> list[GfxSurfaceRecord]:
    if count < 0:
        raise ValueError('negative surface count')
    return [parse_surface(data, offset + index * GFX_SURFACE_STRIDE, endian) for index in range(count)]


def remap_surface_indices(
    source_indices: Iterable[int],
    *,
    first_vertex: int,
    vertex_count: int,
    base_output: int,
) -> list[int]:
    values = [int(value) for value in source_indices]
    if vertex_count <= 0 or first_vertex < 0 or base_output < 0:
        raise ValueError('invalid surface index bounds')

    are_local = all(0 <= value < vertex_count for value in values)
    are_global = all(first_vertex <= value < first_vertex + vertex_count for value in values)
    if not are_local and not are_global:
        raise ValueError('surface contains indices outside its vertex range')

    if are_local:
        mapped = [base_output + value for value in values]
    else:
        mapped = [base_output + (value - first_vertex) for value in values]

    # Runtime indices are deliberately not narrowed to UInt16. Python ints are
    # serialized as 32-bit unsigned values by the GameData world writer.
    if any(value < 0 or value > 0xFFFFFFFF for value in mapped):
        raise ValueError('runtime world index exceeds UInt32')
    return mapped


def read_surface_source_indices(index_data: bytes, surface: GfxSurfaceRecord, endian: str = '>') -> list[int]:
    start = surface.base_index * 2
    count = surface.triangle_count * 3
    end = start + count * 2
    if start < 0 or end > len(index_data):
        raise ValueError('surface index range outside index buffer')
    return list(struct.unpack_from(endian + f'{count}H', index_data, start))

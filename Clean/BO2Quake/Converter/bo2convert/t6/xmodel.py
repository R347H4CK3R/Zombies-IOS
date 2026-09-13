from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re
import struct
from typing import Iterable


@dataclass(frozen=True)
class Bone:
    index: int
    parent: int
    name: str
    offset: tuple[float, float, float]
    scale: tuple[float, float, float]
    basis_x: tuple[float, float, float]
    basis_y: tuple[float, float, float]
    basis_z: tuple[float, float, float]


@dataclass(frozen=True)
class Position:
    index: int
    offset: tuple[float, float, float]
    weights: tuple[tuple[int, float], ...]


@dataclass(frozen=True)
class FaceVertex:
    position_index: int
    normal: tuple[float, float, float]
    color: tuple[float, float, float, float]
    uv: tuple[float, float]


@dataclass(frozen=True)
class Face:
    object_index: int
    material_index: int
    vertices: tuple[FaceVertex, FaceVertex, FaceVertex]


@dataclass(frozen=True)
class Material:
    index: int
    name: str
    material_type: str
    color_map: str


@dataclass(frozen=True)
class XModelExport:
    bones: tuple[Bone, ...]
    positions: tuple[Position, ...]
    faces: tuple[Face, ...]
    objects: tuple[str, ...]
    materials: tuple[Material, ...]


@dataclass(frozen=True)
class ModelExportResult:
    payloads: tuple[str, ...]
    dependencies: tuple[str, ...]


_VEC3_RE = re.compile(r'^([A-Z]+)\s+([-+0-9.eE]+),?\s+([-+0-9.eE]+),?\s+([-+0-9.eE]+)$')


def _vec3(line: str, label: str) -> tuple[float, float, float]:
    clean = line.replace(',', '')
    parts = clean.split()
    if len(parts) != 4 or parts[0] != label:
        raise ValueError(f'expected {label} vector, got {line!r}')
    return tuple(float(v) for v in parts[1:4])  # type: ignore[return-value]


def _vec4(line: str, label: str) -> tuple[float, float, float, float]:
    clean = line.replace(',', '')
    parts = clean.split()
    if len(parts) != 5 or parts[0] != label:
        raise ValueError(f'expected {label} vector, got {line!r}')
    return tuple(float(v) for v in parts[1:5])  # type: ignore[return-value]


def _noncomment_lines(text: str) -> list[str]:
    return [line.strip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith('//')]


def parse_xmodel_export(text: str) -> XModelExport:
    lines = _noncomment_lines(text)
    i = 0
    if i >= len(lines) or lines[i] != 'MODEL':
        raise ValueError('not an XMODEL_EXPORT MODEL')
    i += 1
    if i >= len(lines) or not lines[i].startswith('VERSION '):
        raise ValueError('missing XMODEL_EXPORT version')
    version = int(lines[i].split()[1]); i += 1
    if version != 6:
        raise ValueError(f'unsupported XMODEL_EXPORT version {version}')

    if i >= len(lines) or not lines[i].startswith('NUMBONES '):
        raise ValueError('missing NUMBONES')
    bone_count = int(lines[i].split()[1]); i += 1
    headers: list[tuple[int, int, str]] = []
    for _ in range(bone_count):
        m = re.fullmatch(r'BONE\s+(\d+)\s+(-?\d+)\s+"(.*)"', lines[i])
        if not m: raise ValueError('invalid bone header')
        headers.append((int(m.group(1)), int(m.group(2)), m.group(3))); i += 1
    bones: list[Bone] = []
    for expected, parent, name in headers:
        if i >= len(lines) or lines[i] != f'BONE {expected}': raise ValueError('bone transform order mismatch')
        i += 1
        offset = _vec3(lines[i], 'OFFSET'); i += 1
        scale = _vec3(lines[i], 'SCALE'); i += 1
        bx = _vec3(lines[i], 'X'); i += 1
        by = _vec3(lines[i], 'Y'); i += 1
        bz = _vec3(lines[i], 'Z'); i += 1
        bones.append(Bone(expected, parent, name, offset, scale, bx, by, bz))
    for n, bone in enumerate(bones):
        if bone.index != n: raise ValueError('bone indices must be contiguous')
        if bone.parent >= n or bone.parent < -1: raise ValueError('invalid bone parent')

    if i >= len(lines) or not lines[i].startswith('NUMVERTS '): raise ValueError('missing NUMVERTS')
    position_count = int(lines[i].split()[1]); i += 1
    positions: list[Position] = []
    for expected in range(position_count):
        if lines[i] != f'VERT {expected}': raise ValueError('position indices must be contiguous')
        i += 1
        offset = _vec3(lines[i], 'OFFSET'); i += 1
        if not lines[i].startswith('BONES '): raise ValueError('missing vertex bone count')
        weight_count = int(lines[i].split()[1]); i += 1
        weights: list[tuple[int, float]] = []
        for _ in range(weight_count):
            parts = lines[i].split(); i += 1
            if len(parts) != 3 or parts[0] != 'BONE': raise ValueError('invalid vertex bone weight')
            bone_index, weight = int(parts[1]), float(parts[2])
            if not 0 <= bone_index < bone_count or weight < 0: raise ValueError('invalid vertex bone weight')
            weights.append((bone_index, weight))
        total = sum(weight for _, weight in weights)
        if weights and abs(total - 1.0) > 1e-3: raise ValueError(f'vertex weights do not sum to one: {total}')
        positions.append(Position(expected, offset, tuple(weights)))

    if i >= len(lines) or not lines[i].startswith('NUMFACES '): raise ValueError('missing NUMFACES')
    face_count = int(lines[i].split()[1]); i += 1
    faces: list[Face] = []
    for _ in range(face_count):
        parts = lines[i].split(); i += 1
        if len(parts) < 3 or parts[0] != 'TRI': raise ValueError('invalid TRI')
        object_index, material_index = int(parts[1]), int(parts[2])
        verts: list[FaceVertex] = []
        for _corner in range(3):
            vp = lines[i].split(); i += 1
            if len(vp) != 2 or vp[0] != 'VERT': raise ValueError('invalid face vertex')
            pos_index = int(vp[1])
            if not 0 <= pos_index < position_count: raise ValueError('face position index out of range')
            normal = tuple(float(v) for v in lines[i].split()[1:4]);
            if not lines[i].startswith('NORMAL ') or len(normal) != 3: raise ValueError('invalid face normal')
            i += 1
            color = tuple(float(v) for v in lines[i].split()[1:5]);
            if not lines[i].startswith('COLOR ') or len(color) != 4: raise ValueError('invalid face color')
            i += 1
            uv_parts = lines[i].split(); i += 1
            if len(uv_parts) != 4 or uv_parts[0] != 'UV' or uv_parts[1] != '1': raise ValueError('invalid face UV')
            uv = (float(uv_parts[2]), float(uv_parts[3]))
            verts.append(FaceVertex(pos_index, normal, color, uv))
        faces.append(Face(object_index, material_index, tuple(verts)))  # type: ignore[arg-type]

    if i >= len(lines) or not lines[i].startswith('NUMOBJECTS '): raise ValueError('missing NUMOBJECTS')
    object_count = int(lines[i].split()[1]); i += 1
    objects: list[str] = []
    for expected in range(object_count):
        m = re.fullmatch(r'OBJECT\s+(\d+)\s+"(.*)"', lines[i]); i += 1
        if not m or int(m.group(1)) != expected: raise ValueError('invalid object record')
        objects.append(m.group(2))

    if i >= len(lines) or not lines[i].startswith('NUMMATERIALS '): raise ValueError('missing NUMMATERIALS')
    material_count = int(lines[i].split()[1]); i += 1
    materials: list[Material] = []
    for expected in range(material_count):
        m = re.fullmatch(r'MATERIAL\s+(\d+)\s+"(.*)"\s+"(.*)"\s+"(.*)"', lines[i]); i += 1
        if not m or int(m.group(1)) != expected: raise ValueError('invalid material record')
        materials.append(Material(expected, m.group(2), m.group(3), m.group(4)))
        # OAT v6 writes 11 material-property lines after each material header.
        required = ('COLOR ','TRANSPARENCY ','AMBIENTCOLOR ','INCANDESCENCE ','COEFFS ','GLOW ','REFRACTIVE ','SPECULARCOLOR ','REFLECTIVECOLOR ','REFLECTIVE ','BLINN ','PHONG ')
        for prefix in required:
            if i >= len(lines) or not lines[i].startswith(prefix): raise ValueError(f'missing material property {prefix.strip()}')
            i += 1

    if i != len(lines): raise ValueError(f'unparsed XMODEL_EXPORT trailing records: {len(lines)-i}')
    for face in faces:
        if not 0 <= face.object_index < object_count: raise ValueError('face object index out of range')
        if not 0 <= face.material_index < material_count: raise ValueError('face material index out of range')
    return XModelExport(tuple(bones), tuple(positions), tuple(faces), tuple(objects), tuple(materials))


def export_runtime_model(model: XModelExport, destination: Path | str, *, model_id: str) -> ModelExportResult:
    out = Path(destination); out.mkdir(parents=True, exist_ok=True)
    # Runtime face vertices are expanded to preserve per-corner normal/UV/color.
    vertices = bytearray(); indices: list[int] = []
    for face in model.faces:
        for corner in face.vertices:
            position = model.positions[corner.position_index].offset
            vertices.extend(struct.pack('<3f3f4f2f', *position, *corner.normal, *corner.color, *corner.uv))
            indices.append(len(indices))
    positions_blob = b''.join(struct.pack('<3f', *p.offset) for p in model.positions)
    skin_blob = bytearray()
    for p in model.positions:
        weights = list(p.weights[:4])
        while len(weights) < 4: weights.append((0, 0.0))
        skin_blob.extend(struct.pack('<4H4f', *(b for b,_ in weights), *(w for _,w in weights)))
    index_blob = struct.pack('<' + 'I'*len(indices), *indices) if indices else b''

    meta = {
        'formatVersion': 1,
        'id': model_id,
        'vertexFormat': 'pos3f-normal3f-color4f-uv2f',
        'vertexStride': 48,
        'vertexCount': len(indices),
        'positionCount': len(model.positions),
        'indexType': 'uint32',
        'indexCount': len(indices),
        'bones': [
            {'name': b.name, 'parent': b.parent, 'offset': b.offset, 'scale': b.scale,
             'basisX': b.basis_x, 'basisY': b.basis_y, 'basisZ': b.basis_z}
            for b in model.bones
        ],
        'objects': list(model.objects),
        'materials': [f'materials:{m.name}' for m in model.materials],
        'faces': [{'object': f.object_index, 'material': f.material_index} for f in model.faces],
    }
    (out/'model.json').write_text(json.dumps(meta, sort_keys=True, separators=(',', ':'))+'\n')
    (out/'positions.bin').write_bytes(positions_blob)
    (out/'skin.bin').write_bytes(bytes(skin_blob))
    (out/'vertices.bin').write_bytes(bytes(vertices))
    (out/'indices.bin').write_bytes(index_blob)
    return ModelExportResult(
        payloads=('model.json','positions.bin','skin.bin','vertices.bin','indices.bin'),
        dependencies=tuple(sorted(f'materials:{m.name}' for m in model.materials)),
    )

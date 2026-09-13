from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import struct

SUPPORTED_VERSIONS = {17, 18, 19}


@dataclass(frozen=True)
class CompiledXAnimHeader:
    version: int
    stored_frame_count: int
    bone_count: int
    flags: int
    asset_type: int
    frame_rate: int
    header_size: int

    @property
    def looping(self) -> bool:
        # Across OAT v17/v18/v19, the loop flag occupies bit 0.
        return bool(self.flags & 0x01)

    @property
    def frame_count(self) -> int:
        # OAT writes numframes for looped assets and numframes + 1 otherwise.
        return self.stored_frame_count if self.looping else max(0, self.stored_frame_count - 1)

    @property
    def duration(self) -> float:
        if self.frame_rate <= 0:
            return 0.0
        return float(self.frame_count) / float(self.frame_rate)


def parse_compiled_xanim_header(data: bytes) -> CompiledXAnimHeader:
    if len(data) < 10:
        raise ValueError('compiled XAnim is shorter than its fixed header')
    version, stored_frames, bone_count, flags, asset_type, frame_rate = struct.unpack_from('<HHHBBH', data, 0)
    if version not in SUPPORTED_VERSIONS:
        raise ValueError(f'unsupported compiled XAnim version {version}')
    if bone_count > 8192:
        raise ValueError(f'invalid compiled XAnim bone count {bone_count}')
    if frame_rate <= 0 or frame_rate > 1000:
        raise ValueError(f'invalid compiled XAnim frame rate {frame_rate}')
    return CompiledXAnimHeader(
        version=version,
        stored_frame_count=stored_frames,
        bone_count=bone_count,
        flags=flags,
        asset_type=asset_type,
        frame_rate=frame_rate,
        header_size=10,
    )


def export_compiled_xanim(
    source: Path | str,
    destination: Path | str,
    *,
    animation_id: str,
    source_hash: str,
) -> tuple[str, ...]:
    src = Path(source)
    payload = src.read_bytes()
    header = parse_compiled_xanim_header(payload)
    if not animation_id:
        raise ValueError('animation id is required')
    if len(source_hash) != 64:
        raise ValueError('source_hash must be SHA-256 hex')

    out = Path(destination)
    out.mkdir(parents=True, exist_ok=True)
    (out / 'animation.xanim').write_bytes(payload)
    metadata = {
        'formatVersion': 1,
        'id': animation_id,
        'compiledXAnimVersion': header.version,
        'frameCount': header.frame_count,
        'storedFrameCount': header.stored_frame_count,
        'frameRate': header.frame_rate,
        'duration': header.duration,
        'boneCount': header.bone_count,
        'flags': header.flags,
        'looping': header.looping,
        'assetType': header.asset_type,
        'sourceHash': source_hash,
    }
    (out / 'animation.json').write_text(
        json.dumps(metadata, sort_keys=True, separators=(',', ':')) + '\n',
        encoding='utf-8',
    )
    return ('animation.xanim', 'animation.json')

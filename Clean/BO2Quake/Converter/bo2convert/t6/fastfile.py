from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct
import zlib

from .salsa20 import T6SalsaState, T6_STREAM_COUNT

T6_FF_MAGIC = b'TAff0100'
T6_PS3_VERSION = 0x92
T6_AUTH_MAGIC = b'PHEEBs71'
T6_AUTH_HEADER_SIZE = 8 + 4 + 32 + 256
T6_XCHUNK_SIZE = 0x8000
T6_VANILLA_BUFFER_SIZE = 0x80000


@dataclass(frozen=True)
class DecodedZone:
    zone_name: str
    flags: int
    chunk_count: int
    zone_bytes: bytes


def _inflate_t6_chunk(clear: bytes) -> bytes:
    errors: list[str] = []
    for wbits in (zlib.MAX_WBITS, -zlib.MAX_WBITS):
        try:
            return zlib.decompress(clear, wbits)
        except zlib.error as exc:
            errors.append(str(exc))
    raise ValueError('zlib inflate failed: ' + ' | '.join(errors))


def decode_fastfile(path: Path) -> DecodedZone:
    with path.open('rb') as src:
        head = src.read(12)
        if len(head) != 12:
            raise ValueError('fastfile header truncated')
        magic = head[:8]
        version = struct.unpack('>I', head[8:12])[0]
        if magic != T6_FF_MAGIC:
            raise ValueError(f'unsupported fastfile magic {magic!r}')
        if version != T6_PS3_VERSION:
            raise ValueError(f'unexpected PS3 BO2 fastfile version 0x{version:X}')

        auth = src.read(T6_AUTH_HEADER_SIZE)
        if len(auth) != T6_AUTH_HEADER_SIZE:
            raise ValueError('fastfile auth header truncated')
        if auth[:8] != T6_AUTH_MAGIC:
            raise ValueError(f'invalid auth magic {auth[:8]!r}')

        flags = struct.unpack('>I', auth[8:12])[0]
        raw_name = auth[12:44].split(b'\0', 1)[0]
        zone_name = raw_name.decode('ascii', 'ignore') or path.stem
        salsa = T6SalsaState(zone_name)

        chunks: list[bytes] = []
        chunk_index = 0
        vanilla_offset = src.tell() % T6_VANILLA_BUFFER_SIZE
        while True:
            if vanilla_offset + 4 > T6_VANILLA_BUFFER_SIZE:
                skip = T6_VANILLA_BUFFER_SIZE - vanilla_offset
                if len(src.read(skip)) != skip:
                    break
                vanilla_offset = 0

            size_raw = src.read(4)
            if not size_raw:
                break
            if len(size_raw) != 4:
                raise ValueError('truncated XChunk size')
            vanilla_offset = (vanilla_offset + 4) % T6_VANILLA_BUFFER_SIZE
            chunk_size = struct.unpack('>I', size_raw)[0]
            if chunk_size == 0:
                break
            if chunk_size > T6_XCHUNK_SIZE:
                raise ValueError(f'invalid XChunk size {chunk_size} > {T6_XCHUNK_SIZE}')

            encrypted = src.read(chunk_size)
            if len(encrypted) != chunk_size:
                raise ValueError('truncated XChunk payload')
            vanilla_offset = (vanilla_offset + chunk_size) % T6_VANILLA_BUFFER_SIZE
            stream = chunk_index % T6_STREAM_COUNT
            clear = salsa.decrypt(stream, encrypted)
            chunks.append(_inflate_t6_chunk(clear))
            chunk_index += 1

    zone_bytes = b''.join(chunks)
    if chunk_index == 0 or len(zone_bytes) < 40:
        raise ValueError('no usable XChunks were decoded')
    return DecodedZone(zone_name=zone_name, flags=flags, chunk_count=chunk_index, zone_bytes=zone_bytes)


def parse_xfile_header(zone_bytes: bytes) -> dict:
    if len(zone_bytes) < 40:
        raise ValueError('decompressed zone is shorter than the 0x28-byte XFile header')
    vals = struct.unpack('>10I', zone_bytes[:40])
    names = [
        'temp', 'runtime_virtual', 'runtime_physical', 'delay_virtual',
        'delay_physical', 'virtual', 'physical', 'streamer_reserve',
    ]
    return {
        'size': vals[0],
        'external_size': vals[1],
        'block_sizes': {names[i]: vals[i + 2] for i in range(8)},
    }

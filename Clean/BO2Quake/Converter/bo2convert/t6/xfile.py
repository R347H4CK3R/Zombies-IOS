from __future__ import annotations

from dataclasses import dataclass
import struct
from typing import Mapping

T6_BLOCK_NAMES = (
    'temp',
    'runtime_virtual',
    'runtime_physical',
    'delay_virtual',
    'delay_physical',
    'virtual',
    'physical',
    'streamer_reserve',
)


@dataclass(frozen=True)
class XFileBlockRange:
    name: str
    start: int
    size: int

    @property
    def end(self) -> int:
        return self.start + self.size


class XFileBlockCursor:
    def __init__(self, payload: memoryview, block: XFileBlockRange):
        self._payload = payload
        self.block = block
        self._offset = 0

    def tell(self) -> int:
        return self._offset

    def remaining(self) -> int:
        return self.block.size - self._offset

    def seek(self, offset: int) -> None:
        if offset < 0 or offset > self.block.size:
            raise ValueError(f'XFile block bounds exceeded for {self.block.name}')
        self._offset = offset

    def align(self, alignment: int) -> None:
        if alignment <= 0 or alignment & (alignment - 1):
            raise ValueError('alignment must be a positive power of two')
        aligned = (self._offset + alignment - 1) & ~(alignment - 1)
        self.seek(aligned)

    def read(self, size: int) -> bytes:
        if size < 0 or self._offset + size > self.block.size:
            raise ValueError(f'XFile block bounds exceeded for {self.block.name}')
        start = self.block.start + self._offset
        end = start + size
        self._offset += size
        return bytes(self._payload[start:end])


@dataclass(frozen=True)
class XFileLayout:
    payload: bytes
    declared_size: int
    external_size: int
    blocks: Mapping[str, XFileBlockRange]

    @classmethod
    def parse(cls, payload: bytes) -> 'XFileLayout':
        if len(payload) < 40:
            raise ValueError('XFile payload shorter than 40-byte header')
        values = struct.unpack_from('>10I', payload, 0)
        declared_size, external_size = values[:2]
        sizes = values[2:]
        block_total = sum(sizes)

        # T6 decoded zone bytes consist of the 40-byte XFile header followed by
        # the eight logical blocks in XFileBlock enum order.  The first size
        # field describes the serialized in-file block bytes; external_size is
        # tracked separately for externally streamed content.
        if declared_size != block_total:
            raise ValueError(
                f'XFile size mismatch: declared {declared_size}, block total {block_total}'
            )
        if len(payload) != 40 + block_total:
            raise ValueError(
                f'XFile size mismatch: payload has {len(payload) - 40} block bytes, '
                f'header describes {block_total}'
            )

        offset = 40
        blocks: dict[str, XFileBlockRange] = {}
        for name, size in zip(T6_BLOCK_NAMES, sizes):
            block = XFileBlockRange(name=name, start=offset, size=size)
            blocks[name] = block
            offset = block.end

        return cls(
            payload=payload,
            declared_size=declared_size,
            external_size=external_size,
            blocks=blocks,
        )

    def cursor(self, block_name: str) -> XFileBlockCursor:
        try:
            block = self.blocks[block_name]
        except KeyError as exc:
            raise ValueError(f'unknown T6 XFile block: {block_name}') from exc
        return XFileBlockCursor(memoryview(self.payload), block)

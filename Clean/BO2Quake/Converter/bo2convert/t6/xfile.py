from __future__ import annotations

from dataclasses import dataclass
import struct
from typing import Mapping

XFILE_HEADER_SIZE = 40
POINTER_BITS = 32
BLOCK_BITS = 3
OFFSET_BITS = POINTER_BITS - BLOCK_BITS
OFFSET_MASK = (1 << OFFSET_BITS) - 1
FOLLOWING_POINTER = 0xFFFFFFFF
INSERT_POINTER = 0xFFFFFFFE

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

T6_BLOCK_TYPES = {
    'temp': 'temp',
    'runtime_virtual': 'runtime',
    'runtime_physical': 'runtime',
    'delay_virtual': 'delay',
    'delay_physical': 'delay',
    'virtual': 'normal',
    'physical': 'normal',
    'streamer_reserve': 'normal',
}


@dataclass(frozen=True)
class XFileBlockRange:
    name: str
    start: int  # logical aggregate base only; never a physical payload offset
    size: int
    block_type: str

    @property
    def end(self) -> int:
        return self.start + self.size


@dataclass(frozen=True)
class XFilePointerRef:
    block_index: int
    block_name: str
    offset: int


@dataclass(frozen=True)
class XFileLayout:
    payload: bytes
    declared_size: int
    external_size: int
    blocks: Mapping[str, XFileBlockRange]

    @classmethod
    def parse(cls, payload: bytes) -> 'XFileLayout':
        if len(payload) < XFILE_HEADER_SIZE:
            raise ValueError('XFile payload shorter than 40-byte header')
        values = struct.unpack_from('>10I', payload, 0)
        declared_size, external_size = values[:2]
        sizes = values[2:]
        block_total = sum(sizes)
        if declared_size != block_total:
            raise ValueError(
                f'XFile size mismatch: declared {declared_size}, block total {block_total}'
            )

        # The bytes after the header are one serialized traversal stream.  They
        # are NOT eight concatenated block images.  ZoneInputStream loads TEMP
        # and NORMAL fields from this stream while maintaining an independent
        # logical cursor per block.  RUNTIME blocks are zero-filled and consume
        # no serialized bytes; DELAY blocks are unsupported by the T6 loader.
        logical_base = 0
        blocks: dict[str, XFileBlockRange] = {}
        for name, size in zip(T6_BLOCK_NAMES, sizes):
            blocks[name] = XFileBlockRange(
                name=name,
                start=logical_base,
                size=size,
                block_type=T6_BLOCK_TYPES[name],
            )
            logical_base += size
        return cls(payload, declared_size, external_size, blocks)

    @property
    def serialized_size(self) -> int:
        return max(0, len(self.payload) - XFILE_HEADER_SIZE)

    def pointer_type(self, value: int) -> str:
        value &= 0xFFFFFFFF
        if value == 0:
            return 'null'
        if value == FOLLOWING_POINTER:
            return 'following'
        if value == INSERT_POINTER:
            return 'insert'
        return 'offset'

    def decode_offset_pointer(self, value: int) -> XFilePointerRef:
        if self.pointer_type(value) != 'offset':
            raise ValueError(f'pointer 0x{value & 0xFFFFFFFF:08X} is not an offset pointer')
        raw = ((value & 0xFFFFFFFF) - 1) & 0xFFFFFFFF
        block_index = (raw >> OFFSET_BITS) & ((1 << BLOCK_BITS) - 1)
        offset = raw & OFFSET_MASK
        name = T6_BLOCK_NAMES[block_index]
        block = self.blocks[name]
        if offset >= block.size:
            raise ValueError(
                f'XFile pointer offset {offset} exceeds {name} block size {block.size}'
            )
        return XFilePointerRef(block_index, name, offset)


class XFileSerializedStream:
    """Replays the logical XBlock semantics over one serialized zone stream.

    This mirrors the behavior relevant to T6 in OpenAssetTools' ZoneInputStream:
    TEMP/NORMAL loads consume bytes from the serialized input; RUNTIME loads are
    zero-filled; logical alignment never consumes serialized bytes; popping TEMP
    restores the logical temp cursor to its value at push time.
    """

    def __init__(self, layout: XFileLayout):
        self.layout = layout
        self.serialized_offset = XFILE_HEADER_SIZE
        self._logical_offsets = {name: 0 for name in T6_BLOCK_NAMES}
        self._stack: list[str] = []
        self._temp_snapshots: list[int] = []

    def logical_offset(self, block_name: str) -> int:
        self._block(block_name)
        return self._logical_offsets[block_name]

    def remaining(self, block_name: str) -> int:
        block = self._block(block_name)
        return block.size - self._logical_offsets[block_name]

    def push_block(self, block_name: str) -> None:
        block = self._block(block_name)
        self._stack.append(block_name)
        if block.block_type == 'temp':
            self._temp_snapshots.append(self._logical_offsets[block_name])

    def pop_block(self) -> str:
        if not self._stack:
            raise ValueError('XFile block stack is empty')
        name = self._stack.pop()
        if self.layout.blocks[name].block_type == 'temp':
            self._logical_offsets[name] = self._temp_snapshots.pop()
        return name

    def align(self, block_name: str, alignment: int) -> None:
        if alignment <= 0 or alignment & (alignment - 1):
            raise ValueError('alignment must be a positive power of two')
        block = self._block(block_name)
        offset = self._logical_offsets[block_name]
        aligned = (offset + alignment - 1) & ~(alignment - 1)
        if aligned > block.size:
            raise ValueError(f'XFile block bounds exceeded for {block_name}')
        self._logical_offsets[block_name] = aligned

    def align_current(self, alignment: int) -> None:
        if not self._stack:
            raise ValueError('XFile block stack is empty')
        self.align(self._stack[-1], alignment)

    def load_current(self, size: int) -> bytes:
        if not self._stack:
            raise ValueError('XFile block stack is empty')
        return self.load(self._stack[-1], size)

    def load(self, block_name: str, size: int) -> bytes:
        block = self._block(block_name)
        if size < 0:
            raise ValueError('negative XFile load size')
        logical = self._logical_offsets[block_name]
        if logical + size > block.size:
            raise ValueError(f'XFile block bounds exceeded for {block_name}')

        if block.block_type == 'runtime':
            data = bytes(size)
        elif block.block_type == 'delay':
            raise ValueError(f'T6 delay block load is unsupported: {block_name}')
        else:
            end = self.serialized_offset + size
            if end > len(self.layout.payload):
                raise ValueError(
                    f'XFile serialized stream exhausted loading {size} bytes into {block_name}'
                )
            data = self.layout.payload[self.serialized_offset:end]
            self.serialized_offset = end

        self._logical_offsets[block_name] = logical + size
        return data

    def load_c_string(self, block_name: str, *, encoding: str = 'utf-8') -> str:
        block = self._block(block_name)
        if block.block_type in {'runtime', 'delay'}:
            raise ValueError(f'cannot load serialized string into {block.block_type} block')
        out = bytearray()
        while True:
            byte = self.load(block_name, 1)[0]
            if byte == 0:
                break
            out.append(byte)
        try:
            return out.decode(encoding)
        except UnicodeDecodeError:
            return out.decode('latin-1')

    def _block(self, block_name: str) -> XFileBlockRange:
        try:
            return self.layout.blocks[block_name]
        except KeyError as exc:
            raise ValueError(f'unknown T6 XFile block: {block_name}') from exc

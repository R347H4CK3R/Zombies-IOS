from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct

MAX_LZO_BLOCK_OUTPUT = 0x1000000


class LZOError(Exception):
    pass


@dataclass(frozen=True)
class IPAKSegment:
    type: int
    offset: int
    size: int
    entry_count: int


@dataclass(frozen=True)
class IPAKEntry:
    index: int
    key: int
    offset: int
    compressed_size: int


@dataclass(frozen=True)
class IPAKIndex:
    endian: str
    endian_name: str
    version: int
    declared_size: int
    entries: tuple[IPAKEntry, ...]
    data_segment: IPAKSegment


@dataclass(frozen=True)
class DecodedIPAKEntry:
    key: int
    data: bytes
    raw_blocks: int
    lzo_blocks: int
    padding_blocks: int
    consumed: int


def lzo1x_decompress(data: bytes, max_output: int = MAX_LZO_BLOCK_OUTPUT) -> bytes:
    src = memoryview(data)
    n = len(src)
    ip = 0
    out = bytearray()
    m2_max_offset = 0x0800

    def need(k: int) -> None:
        if k < 0 or ip + k > n:
            raise LZOError(f'truncated stream at input offset {ip}, need {k} byte(s)')

    def get1() -> int:
        nonlocal ip
        need(1)
        value = int(src[ip])
        ip += 1
        return value

    def get16le() -> int:
        nonlocal ip
        need(2)
        value = int(src[ip]) | (int(src[ip + 1]) << 8)
        ip += 2
        return value

    def ensure_output(k: int) -> None:
        if k < 0 or len(out) + k > max_output:
            raise LZOError('decoded block exceeds output safety cap')

    def copy_literals(k: int) -> None:
        nonlocal ip
        if k < 0:
            raise LZOError('negative literal count')
        need(k)
        ensure_output(k)
        out.extend(src[ip:ip + k])
        ip += k

    def copy_match(distance: int, length: int) -> None:
        if distance <= 0 or distance > len(out):
            raise LZOError(f'invalid match distance {distance} with output size {len(out)}')
        ensure_output(length)
        for _ in range(length):
            out.append(out[-distance])

    def extended(base: int) -> int:
        total = 0
        while True:
            b = get1()
            if b:
                total += b
                break
            total += 255
            if total > max_output:
                raise LZOError('unreasonable extended length')
        return total + base

    if n == 0:
        raise LZOError('empty LZO stream')

    first = get1()
    state = 'main'
    t = first
    if first > 17:
        t = first - 17
        if t < 4:
            copy_literals(t)
            t = get1()
            state = 'match'
        else:
            copy_literals(t)
            state = 'first_literal_run'
    else:
        ip -= 1

    while True:
        if state == 'main':
            if ip >= n:
                raise LZOError('LZO EOF marker not found')
            t = get1()
            if t >= 16:
                state = 'match'
                continue
            if t == 0:
                t = extended(15)
            copy_literals(t + 3)
            state = 'first_literal_run'
            continue

        if state == 'first_literal_run':
            t = get1()
            if t >= 16:
                state = 'match'
                continue
            b = get1()
            distance = 1 + m2_max_offset + (t >> 2) + (b << 2)
            copy_match(distance, 3)
            trailing = t & 3
            if trailing:
                copy_literals(trailing)
                t = get1()
                state = 'match'
            else:
                state = 'main'
            continue

        if t >= 64:
            b = get1()
            distance = 1 + ((t >> 2) & 7) + (b << 3)
            length = (t >> 5) + 1
            copy_match(distance, length)
            trailing = t & 3
        elif t >= 32:
            length_code = t & 31
            if length_code == 0:
                length_code = extended(31)
            desc = get16le()
            distance = 1 + (desc >> 2)
            length = length_code + 2
            copy_match(distance, length)
            trailing = desc & 3
        elif t >= 16:
            high = (t & 8) << 11
            length_code = t & 7
            if length_code == 0:
                length_code = extended(7)
            desc = get16le()
            raw_distance = high + (desc >> 2)
            if raw_distance == 0:
                if ip != n:
                    tail = bytes(src[ip:])
                    if any(tail):
                        raise LZOError(f'LZO input not fully consumed ({n - ip} trailing byte(s))')
                return bytes(out)
            distance = raw_distance + 0x4000
            length = length_code + 2
            copy_match(distance, length)
            trailing = desc & 3
        else:
            b = get1()
            distance = 1 + (t >> 2) + (b << 2)
            copy_match(distance, 2)
            trailing = t & 3

        if trailing:
            copy_literals(trailing)
            t = get1()
            state = 'match'
        else:
            state = 'main'


def _parse_header(path: Path) -> tuple[str, str, int, int, tuple[IPAKSegment, ...]]:
    size = path.stat().st_size
    with path.open('rb') as handle:
        head = handle.read(min(4096, size))
    if len(head) < 48 or head[:4] != b'IPAK':
        raise ValueError('not an IPAK file or header too small')

    candidates: list[tuple[int, str, str, int, int, tuple[IPAKSegment, ...]]] = []
    for endian, endian_name in (('>', 'big'), ('<', 'little')):
        try:
            _, version, declared_size, segment_count = struct.unpack_from(endian + '4I', head, 0)
        except struct.error:
            continue
        if not (1 <= segment_count <= 32) or 16 + segment_count * 16 > len(head):
            continue
        score = 0
        segments: list[IPAKSegment] = []
        plausible_types: set[int] = set()
        for index in range(segment_count):
            offset = 16 + index * 16
            segment_type, segment_offset, segment_size, entry_count = struct.unpack_from(endian + '4I', head, offset)
            plausible = (
                segment_type in range(0, 9)
                and 0 <= segment_offset <= size
                and 0 <= segment_size <= size
                and segment_offset + segment_size <= size
                and 0 <= entry_count < 10_000_000
            )
            if plausible:
                score += 3
                plausible_types.add(segment_type)
                segments.append(IPAKSegment(segment_type, segment_offset, segment_size, entry_count))
        if 1 in plausible_types:
            score += 5
        if 2 in plausible_types:
            score += 5
        if version < 0x1000000:
            score += 1
        if declared_size == size:
            score += 2
        candidates.append((score, endian, endian_name, version, declared_size, tuple(segments)))

    if not candidates:
        raise ValueError('no plausible IPAK byte order/layout')
    candidates.sort(key=lambda item: item[0], reverse=True)
    score, endian, endian_name, version, declared_size, segments = candidates[0]
    if score < 10:
        raise ValueError('IPAK layout confidence too low')
    return endian, endian_name, version, declared_size, segments


def _parse_block_header(raw: bytes, endian: str) -> tuple[int, int, tuple[int, ...]]:
    if len(raw) < 128:
        raise EOFError('short IPAK block header')
    first = struct.unpack_from(endian + 'I', raw, 0)[0]
    if endian == '<':
        count = (first >> 24) & 0xFF
        packed_offset = first & 0xFFFFFF
    else:
        count_a = (first >> 24) & 0xFF
        count_b = first & 0xFF
        if 0 < count_a <= 31:
            count = count_a
            packed_offset = first & 0xFFFFFF
        else:
            count = count_b
            packed_offset = (first >> 8) & 0xFFFFFF
    commands = struct.unpack_from(endian + '31I', raw, 4)
    return packed_offset, count, commands


class IPAKArchive:
    def __init__(self, path: Path):
        self.path = Path(path)
        self._index: IPAKIndex | None = None

    def index(self) -> IPAKIndex:
        if self._index is not None:
            return self._index
        endian, endian_name, version, declared_size, segments = _parse_header(self.path)
        entries_segment = next((segment for segment in segments if segment.type == 1), None)
        data_segment = next((segment for segment in segments if segment.type == 2), None)
        if entries_segment is None or data_segment is None:
            raise ValueError('IPAK missing entry or data segment')
        if entries_segment.entry_count * 16 > entries_segment.size:
            raise ValueError('IPAK entry count exceeds entry segment size')

        entries: list[IPAKEntry] = []
        file_size = self.path.stat().st_size
        with self.path.open('rb') as handle:
            handle.seek(entries_segment.offset)
            for index in range(entries_segment.entry_count):
                raw = handle.read(16)
                if len(raw) != 16:
                    raise EOFError('truncated IPAK entry table')
                key, offset, compressed_size = struct.unpack(endian + 'QII', raw)
                absolute_start = data_segment.offset + offset
                if absolute_start < data_segment.offset or absolute_start >= file_size:
                    raise ValueError(f'IPAK entry {index} starts outside data segment/file')
                if compressed_size <= 0 or absolute_start + compressed_size > file_size:
                    raise ValueError(f'IPAK entry {index} encoded span exceeds file')
                entries.append(IPAKEntry(index, key, offset, compressed_size))

        self._index = IPAKIndex(endian, endian_name, version, declared_size, tuple(entries), data_segment)
        return self._index

    def decode_entry(self, key: int | str) -> DecodedIPAKEntry:
        index = self.index()
        normalized = int(key, 16) if isinstance(key, str) else int(key)
        entry = next((item for item in index.entries if item.key == normalized), None)
        if entry is None:
            raise KeyError(f'IPAK key not found: {normalized:016x}')

        start = index.data_segment.offset + entry.offset
        target = entry.compressed_size
        file_size = self.path.stat().st_size
        consumed = 0
        output = bytearray()
        raw_blocks = 0
        lzo_blocks = 0
        padding_blocks = 0

        with self.path.open('rb') as source:
            source.seek(start)
            while consumed < target:
                header_position = source.tell()
                header = source.read(128)
                if len(header) != 128:
                    raise EOFError(f'truncated block header at 0x{header_position:X}')
                _, count, commands = _parse_block_header(header, index.endian)
                if not 1 <= count <= 31:
                    raise ValueError(f'invalid IPAK command count {count}')
                consumed += 128

                for command_index in range(count):
                    command = commands[command_index]
                    block_size = command & 0xFFFFFF
                    flag = (command >> 24) & 0xFF
                    if block_size == 0:
                        continue
                    position = source.tell()
                    if position + block_size > file_size:
                        raise EOFError('IPAK data block extends beyond file')
                    block = source.read(block_size)
                    if len(block) != block_size:
                        raise EOFError('short IPAK data block')

                    if flag == 0:
                        output.extend(block)
                        raw_blocks += 1
                    elif flag == 1:
                        output.extend(lzo1x_decompress(block))
                        lzo_blocks += 1
                    else:
                        padding_blocks += 1

                    padding = 0
                    if command_index + 1 == count:
                        aligned = (source.tell() + 0x7F) & ~0x7F
                        padding = aligned - source.tell()
                        if padding:
                            source.seek(padding, 1)
                    consumed += block_size + padding
                    if consumed >= target:
                        break

        if consumed < target:
            raise EOFError('IPAK entry ended before encoded span was consumed')
        return DecodedIPAKEntry(
            key=entry.key,
            data=bytes(output),
            raw_blocks=raw_blocks,
            lzo_blocks=lzo_blocks,
            padding_blocks=padding_blocks,
            consumed=consumed,
        )

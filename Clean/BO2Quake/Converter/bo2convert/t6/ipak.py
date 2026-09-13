from __future__ import annotations

MAX_LZO_BLOCK_OUTPUT = 0x1000000


class LZOError(Exception):
    pass


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

from __future__ import annotations

import hashlib
import struct

T6_STREAM_COUNT = 4
T6_PS3_SALSA20_KEY = bytes([
    0xC8, 0x0B, 0x0E, 0x0C, 0x15, 0x4B, 0xFF, 0x91,
    0x76, 0xA0, 0xC5, 0xC8, 0xD2, 0x4F, 0xA5, 0xE3,
    0xEE, 0x09, 0xEE, 0x90, 0x6F, 0x72, 0x90, 0x80,
    0xA3, 0x92, 0x75, 0xFD, 0x3E, 0xA7, 0x13, 0x39,
])


def _rotl32(v: int, n: int) -> int:
    v &= 0xFFFFFFFF
    return ((v << n) | (v >> (32 - n))) & 0xFFFFFFFF


def salsa20_block(key: bytes, nonce8: bytes, counter: int) -> bytes:
    if len(key) != 32 or len(nonce8) != 8:
        raise ValueError('Salsa20 requires 32-byte key and 8-byte nonce')
    sigma = b'expand 32-byte k'
    k = struct.unpack('<8I', key)
    n0, n1 = struct.unpack('<2I', nonce8)
    c = struct.unpack('<4I', sigma)
    state = [
        c[0], k[0], k[1], k[2], k[3], c[1], n0, n1,
        counter & 0xFFFFFFFF, (counter >> 32) & 0xFFFFFFFF,
        c[2], k[4], k[5], k[6], k[7], c[3],
    ]
    x = state[:]
    for _ in range(10):
        x[4] ^= _rotl32((x[0] + x[12]) & 0xFFFFFFFF, 7)
        x[8] ^= _rotl32((x[4] + x[0]) & 0xFFFFFFFF, 9)
        x[12] ^= _rotl32((x[8] + x[4]) & 0xFFFFFFFF, 13)
        x[0] ^= _rotl32((x[12] + x[8]) & 0xFFFFFFFF, 18)
        x[9] ^= _rotl32((x[5] + x[1]) & 0xFFFFFFFF, 7)
        x[13] ^= _rotl32((x[9] + x[5]) & 0xFFFFFFFF, 9)
        x[1] ^= _rotl32((x[13] + x[9]) & 0xFFFFFFFF, 13)
        x[5] ^= _rotl32((x[1] + x[13]) & 0xFFFFFFFF, 18)
        x[14] ^= _rotl32((x[10] + x[6]) & 0xFFFFFFFF, 7)
        x[2] ^= _rotl32((x[14] + x[10]) & 0xFFFFFFFF, 9)
        x[6] ^= _rotl32((x[2] + x[14]) & 0xFFFFFFFF, 13)
        x[10] ^= _rotl32((x[6] + x[2]) & 0xFFFFFFFF, 18)
        x[3] ^= _rotl32((x[15] + x[11]) & 0xFFFFFFFF, 7)
        x[7] ^= _rotl32((x[3] + x[15]) & 0xFFFFFFFF, 9)
        x[11] ^= _rotl32((x[7] + x[3]) & 0xFFFFFFFF, 13)
        x[15] ^= _rotl32((x[11] + x[7]) & 0xFFFFFFFF, 18)
        x[1] ^= _rotl32((x[0] + x[3]) & 0xFFFFFFFF, 7)
        x[2] ^= _rotl32((x[1] + x[0]) & 0xFFFFFFFF, 9)
        x[3] ^= _rotl32((x[2] + x[1]) & 0xFFFFFFFF, 13)
        x[0] ^= _rotl32((x[3] + x[2]) & 0xFFFFFFFF, 18)
        x[6] ^= _rotl32((x[5] + x[4]) & 0xFFFFFFFF, 7)
        x[7] ^= _rotl32((x[6] + x[5]) & 0xFFFFFFFF, 9)
        x[4] ^= _rotl32((x[7] + x[6]) & 0xFFFFFFFF, 13)
        x[5] ^= _rotl32((x[4] + x[7]) & 0xFFFFFFFF, 18)
        x[11] ^= _rotl32((x[10] + x[9]) & 0xFFFFFFFF, 7)
        x[8] ^= _rotl32((x[11] + x[10]) & 0xFFFFFFFF, 9)
        x[9] ^= _rotl32((x[8] + x[11]) & 0xFFFFFFFF, 13)
        x[10] ^= _rotl32((x[9] + x[8]) & 0xFFFFFFFF, 18)
        x[12] ^= _rotl32((x[15] + x[14]) & 0xFFFFFFFF, 7)
        x[13] ^= _rotl32((x[12] + x[15]) & 0xFFFFFFFF, 9)
        x[14] ^= _rotl32((x[13] + x[12]) & 0xFFFFFFFF, 13)
        x[15] ^= _rotl32((x[14] + x[13]) & 0xFFFFFFFF, 18)
    return struct.pack('<16I', *[((x[i] + state[i]) & 0xFFFFFFFF) for i in range(16)])


def salsa20_xor(data: bytes, key: bytes, nonce8: bytes) -> bytes:
    out = bytearray(len(data))
    counter = 0
    for off in range(0, len(data), 64):
        block = salsa20_block(key, nonce8, counter)
        piece = data[off:off + 64]
        for i, b in enumerate(piece):
            out[off + i] = b ^ block[i]
        counter += 1
    return bytes(out)


class T6SalsaState:
    BLOCK_HASHES_COUNT = 200
    SHA1_SIZE = 20

    def __init__(self, zone_name: str):
        zone_name = zone_name[:31]
        if not zone_name:
            raise ValueError('empty fastfile zone name')
        total = self.BLOCK_HASHES_COUNT * T6_STREAM_COUNT * self.SHA1_SIZE
        self.hashes = bytearray(total)
        name_bytes = zone_name.encode('ascii', 'ignore') or b'?'
        pos = 0
        for i in range(0, total, 4):
            ch = name_bytes[pos]
            self.hashes[i:i + 4] = bytes([ch]) * 4
            pos = (pos + 1) % len(name_bytes)
        self.indices = [0] * T6_STREAM_COUNT

    def _block_offset(self, stream: int) -> int:
        if stream < 0 or stream >= T6_STREAM_COUNT:
            raise ValueError('invalid T6 stream index')
        return ((self.indices[stream] * T6_STREAM_COUNT + stream) * self.SHA1_SIZE)

    def crypt_without_advance(self, stream: int, data: bytes) -> bytes:
        off = self._block_offset(stream)
        nonce = bytes(self.hashes[off:off + 8])
        return salsa20_xor(data, T6_PS3_SALSA20_KEY, nonce)

    def decrypt(self, stream: int, encrypted: bytes) -> bytes:
        off = self._block_offset(stream)
        nonce = bytes(self.hashes[off:off + 8])
        clear = salsa20_xor(encrypted, T6_PS3_SALSA20_KEY, nonce)
        digest = hashlib.sha1(clear).digest()
        self.indices[stream] = (self.indices[stream] + 1) % self.BLOCK_HASHES_COUNT
        next_off = self._block_offset(stream)
        for i, b in enumerate(digest):
            self.hashes[next_off + i] ^= b
        return clear

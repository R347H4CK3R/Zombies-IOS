#!/usr/bin/env python3
import argparse
import json
import struct
import sys
import zlib
from pathlib import Path

MAX_BLACK_PIXEL_RATIO = 0.90
BLACK_THRESHOLD = 18


def _read_png_rgb(path: Path):
    data = path.read_bytes()
    signature = b"\x89PNG\r\n\x1a\n"
    if not data.startswith(signature):
        raise ValueError("not a PNG file")

    pos = len(signature)
    width = height = None
    bit_depth = color_type = None
    compressed = bytearray()
    while pos + 12 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        chunk_type = data[pos + 4:pos + 8]
        chunk_data = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, compression, filt, interlace = struct.unpack(">IIBBBBB", chunk_data)
            if compression != 0 or filt != 0 or interlace != 0:
                raise ValueError("unsupported PNG encoding")
            if bit_depth != 8 or color_type not in (2, 6):
                raise ValueError("only 8-bit RGB/RGBA PNG is supported")
        elif chunk_type == b"IDAT":
            compressed.extend(chunk_data)
        elif chunk_type == b"IEND":
            break

    if not width or not height or bit_depth is None or color_type is None:
        raise ValueError("missing PNG header")

    channels = 3 if color_type == 2 else 4
    stride = width * channels
    raw = zlib.decompress(bytes(compressed))
    expected = height * (stride + 1)
    if len(raw) != expected:
        raise ValueError(f"unexpected PNG payload length: {len(raw)} != {expected}")

    rows = []
    previous = bytearray(stride)
    offset = 0
    for _ in range(height):
        filter_type = raw[offset]
        offset += 1
        current = bytearray(raw[offset:offset + stride])
        offset += stride
        _unfilter(current, previous, filter_type, channels)
        rows.append(bytes(current))
        previous = current
    return width, height, channels, rows


def _paeth(a, b, c):
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _unfilter(row, previous, filter_type, bpp):
    if filter_type == 0:
        return
    for i in range(len(row)):
        left = row[i - bpp] if i >= bpp else 0
        up = previous[i]
        upper_left = previous[i - bpp] if i >= bpp else 0
        if filter_type == 1:
            row[i] = (row[i] + left) & 0xFF
        elif filter_type == 2:
            row[i] = (row[i] + up) & 0xFF
        elif filter_type == 3:
            row[i] = (row[i] + ((left + up) // 2)) & 0xFF
        elif filter_type == 4:
            row[i] = (row[i] + _paeth(left, up, upper_left)) & 0xFF
        else:
            raise ValueError(f"unsupported PNG filter {filter_type}")


def black_pixel_ratio(path: Path) -> float:
    width, height, channels, rows = _read_png_rgb(path)
    black = 0
    total = width * height
    for row in rows:
        for offset in range(0, len(row), channels):
            r, g, b = row[offset], row[offset + 1], row[offset + 2]
            if r < BLACK_THRESHOLD and g < BLACK_THRESHOLD and b < BLACK_THRESHOLD:
                black += 1
    return black / max(1, total)


def validate_metrics(metrics: dict, screenshot_ratio: float):
    failures = []
    if int(metrics.get("drawnSurfaces", 0)) <= 0:
        failures.append("drawnSurfaces == 0")
    if int(metrics.get("submittedTriangles", 0)) <= 0:
        failures.append("submittedTriangles == 0")
    if int(metrics.get("nonFallbackMaterials", 0)) <= 0:
        failures.append("nonFallbackMaterials == 0")
    if int(metrics.get("residentTextures", 0)) <= 0:
        failures.append("residentTextures == 0")
    if metrics.get("validCamera") is not True:
        failures.append("validCamera != true")

    reported = float(metrics.get("blackPixelRatio", 1.0))
    effective_ratio = max(reported, screenshot_ratio)
    if effective_ratio >= MAX_BLACK_PIXEL_RATIO:
        failures.append(f"blackPixelRatio >= {MAX_BLACK_PIXEL_RATIO:.2f} ({effective_ratio:.4f})")
    return failures, effective_ratio


def main(argv=None):
    parser = argparse.ArgumentParser(description="Reject empty/black/fallback-only ZombiesIOS render evidence.")
    parser.add_argument("screenshot", type=Path)
    parser.add_argument("metrics", type=Path)
    args = parser.parse_args(argv)

    try:
        ratio = black_pixel_ratio(args.screenshot)
        metrics = json.loads(args.metrics.read_text())
        failures, effective = validate_metrics(metrics, ratio)
    except Exception as exc:
        print(f"render gate error: {exc}", file=sys.stderr)
        return 2

    print(f"render gate black ratio: {effective:.4f}")
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    print("PASS: render evidence is structurally non-empty, textured, and non-black")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

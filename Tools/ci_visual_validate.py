#!/usr/bin/env python3
import argparse
import json
import math
from pathlib import Path
from statistics import pstdev

from PIL import Image, ImageChops, ImageStat


def analyze_image(path: Path):
    image = Image.open(path).convert("RGB")
    w, h = image.size
    crop = image.crop((int(w * 0.05), int(h * 0.18), int(w * 0.95), int(h * 0.72)))
    gray = crop.convert("L")
    values = list(gray.getdata())
    if not values:
        return {"passes_visibility": False, "mean_luminance": 0.0, "bright_fraction_18": 0.0, "bright_fraction_40": 0.0, "luminance_stddev": 0.0}
    mean = sum(values) / len(values)
    bright18 = sum(v > 18 for v in values) / len(values)
    bright40 = sum(v > 40 for v in values) / len(values)
    stddev = pstdev(values)
    passed = bright18 >= 0.02 and stddev >= 4.0
    return {
        "passes_visibility": passed,
        "mean_luminance": mean,
        "bright_fraction_18": bright18,
        "bright_fraction_40": bright40,
        "luminance_stddev": stddev,
    }


def validate_diagnostics(diag):
    checks = {
        "ready": diag.get("ready") is True,
        "vertex_count": int(diag.get("vertexCount", 0)) >= 3,
        "index_count": int(diag.get("indexCount", 0)) >= 3,
        "triangle_count": int(diag.get("triangleCount", 0)) >= 1,
        "world_in_frustum": diag.get("worldInFrustum") is True,
        "frame_count": int(diag.get("frameCount", 0)) >= 10,
        "timestamp": float(diag.get("lastFrameTimestamp", 0) or 0) > 0,
    }
    return {"passes_diagnostics": all(checks.values()), "checks": checks}


def images_identical(path1: Path, path2: Path):
    a = Image.open(path1).convert("RGB")
    b = Image.open(path2).convert("RGB")
    if a.size != b.size:
        return False
    return ImageChops.difference(a, b).getbbox() is None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--screenshot-1", type=Path, required=True)
    p.add_argument("--screenshot-2", type=Path, required=True)
    p.add_argument("--diagnostics", type=Path, required=True)
    p.add_argument("--report", type=Path, required=True)
    args = p.parse_args()

    diag = json.loads(args.diagnostics.read_text())
    image1 = analyze_image(args.screenshot_1)
    image2 = analyze_image(args.screenshot_2)
    diagnostics = validate_diagnostics(diag)
    identical = images_identical(args.screenshot_1, args.screenshot_2)

    passed = image1["passes_visibility"] and image2["passes_visibility"] and diagnostics["passes_diagnostics"]
    report = {
        "passed": passed,
        "screenshot1": image1,
        "screenshot2": image2,
        "diagnostics": diagnostics,
        "pixel_identical": identical,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True))
    print(json.dumps(report, indent=2, sort_keys=True))
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()

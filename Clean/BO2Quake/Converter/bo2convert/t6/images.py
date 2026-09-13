from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path


@dataclass(frozen=True)
class TextureConversionResult:
    payloads: tuple[str, ...]
    dependencies: tuple[str, ...] = ()


def convert_image_to_png(source: Path | str, destination: Path | str, *, texture_id: str) -> TextureConversionResult:
    try:
        from PIL import Image
    except Exception as exc:  # pragma: no cover - environment guard
        raise RuntimeError('Pillow is required for texture conversion') from exc

    src = Path(source)
    out = Path(destination)
    if not src.is_file():
        raise ValueError(f'texture source does not exist: {src}')
    out.mkdir(parents=True, exist_ok=True)

    try:
        with Image.open(src) as image:
            rgba = image.convert('RGBA')
            width, height = rgba.size
            if width <= 0 or height <= 0 or width > 16384 or height > 16384:
                raise ValueError(f'unsupported texture dimensions {width}x{height}')
            png = out / 'texture.png'
            rgba.save(png, format='PNG', optimize=False)
    except ValueError:
        raise
    except Exception as exc:
        raise ValueError(f'unsupported or corrupt texture {src.name}: {exc}') from exc

    meta = {
        'formatVersion': 1,
        'id': texture_id,
        'width': width,
        'height': height,
        'pixelFormat': 'rgba8-srgb',
        'sourceContainerFormat': src.suffix.lower().lstrip('.'),
        'mipPolicy': 'generate-runtime',
    }
    (out / 'texture.json').write_text(json.dumps(meta, sort_keys=True, separators=(',', ':')) + '\n')
    return TextureConversionResult(('texture.png', 'texture.json'))

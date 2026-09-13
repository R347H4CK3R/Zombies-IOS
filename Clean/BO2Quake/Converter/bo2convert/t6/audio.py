from __future__ import annotations

from dataclasses import dataclass
import csv
import json
from pathlib import Path, PurePosixPath
import shutil


@dataclass(frozen=True)
class AudioConversionResult:
    alias_count: int
    payloads: tuple[str, ...]
    dependencies: tuple[str, ...] = ()


def _bool(value: str, *, default: bool = False) -> bool:
    raw = (value or '').strip().lower()
    if not raw:
        return default
    if raw in {'1','true','yes','y','looping','loop'}:
        return True
    if raw in {'0','false','no','n','nonlooping','non-looping'}:
        return False
    raise ValueError(f'unsupported boolean/enum value: {value}')


def _float(row: dict[str, str], key: str, default: float = 0.0) -> float:
    raw = (row.get(key) or '').strip()
    return float(raw) if raw else default


def _safe_relative(raw: str) -> PurePosixPath:
    path = PurePosixPath(raw.replace('\\','/'))
    if path.is_absolute() or '..' in path.parts:
        raise ValueError(f'unsafe audio path: {raw}')
    return path


def convert_sound_alias_csv(
    alias_csv: Path | str,
    extracted_root: Path | str,
    destination: Path | str,
    *,
    bank_id: str,
) -> AudioConversionResult:
    csv_path = Path(alias_csv)
    source_root = Path(extracted_root).resolve()
    out = Path(destination)
    out.mkdir(parents=True, exist_ok=True)
    file_root = out / 'files'
    file_root.mkdir(exist_ok=True)

    aliases: list[dict] = []
    payloads: set[str] = {'aliases.json'}
    with csv_path.open('r', encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames or 'Name' not in reader.fieldnames or 'FileSource' not in reader.fieldnames:
            raise ValueError('sound alias CSV is missing Name/FileSource columns')
        for row_num, row in enumerate(reader, start=2):
            name = (row.get('Name') or '').strip()
            if not name:
                raise ValueError(f'sound alias row {row_num} has no name')
            file_source = (row.get('FileSource') or '').strip()
            output_file = ''
            if file_source:
                rel = _safe_relative(file_source)
                src = source_root.joinpath(*rel.parts).resolve()
                try:
                    src.relative_to(source_root)
                except ValueError as exc:
                    raise ValueError(f'audio source escapes extraction root: {file_source}') from exc
                if not src.is_file():
                    raise ValueError(f'missing audio file for alias {name}: {file_source}')
                if src.suffix.lower() not in {'.wav', '.flac'}:
                    raise ValueError(f'unsupported audio codec for alias {name}: {src.suffix}')
                dst = file_root.joinpath(*rel.parts)
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
                output_file = (PurePosixPath('files') / rel).as_posix()
                payloads.add(output_file)

            pan = (row.get('PanType') or '').strip().lower()
            looping_raw = (row.get('Looping') or '').strip()
            music_raw = (row.get('IsMusic') or '').strip()
            pause_raw = (row.get('Pauseable') or '').strip()
            aliases.append({
                'name': name,
                'file': output_file,
                'secondary': (row.get('Secondary') or '').strip(),
                'bus': (row.get('Bus') or '').strip(),
                'volumeMin': _float(row, 'VolMin', 0.0),
                'volumeMax': _float(row, 'VolMax', 0.0),
                'distanceMin': _float(row, 'DistMin', 0.0),
                'distanceMax': _float(row, 'DistMaxDry', 0.0),
                'pitchMin': _float(row, 'PitchMin', 0.0),
                'pitchMax': _float(row, 'PitchMax', 0.0),
                'spatial': pan in {'3d','3d_default','3d_front'},
                'looping': _bool(looping_raw, default=False) if looping_raw else False,
                'probability': _float(row, 'Probability', 1.0),
                'startDelayMs': _float(row, 'StartDelay', 0.0),
                'music': _bool(music_raw, default=False) if music_raw else False,
                'fadeInMs': _float(row, 'FadeIn', 0.0),
                'fadeOutMs': _float(row, 'FadeOut', 0.0),
                'pauseable': _bool(pause_raw, default=True) if pause_raw else True,
            })

    names = [a['name'] for a in aliases]
    if len(names) != len(set(names)):
        raise ValueError('duplicate sound alias name in bank')
    payload = {'formatVersion': 1, 'id': bank_id, 'aliases': aliases}
    (out / 'aliases.json').write_text(json.dumps(payload, sort_keys=True, separators=(',', ':')) + '\n', encoding='utf-8')
    return AudioConversionResult(len(aliases), tuple(sorted(payloads)))

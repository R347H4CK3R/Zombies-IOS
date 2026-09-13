from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import subprocess
from typing import Sequence


@dataclass(frozen=True)
class OATResult:
    complete: bool
    returncode: int
    outputs: tuple[Path, ...]
    failures: tuple[str, ...]
    stdout: str
    stderr: str


class OATBackend:
    def __init__(self, unlinker_path: Path | str):
        self.unlinker_path = Path(unlinker_path)

    def dump_zone(
        self,
        zone_path: Path | str,
        destination: Path | str,
        *,
        expected_globs: Sequence[str],
        search_path: Path | str | None = None,
        image_format: str = 'dds',
        model_format: str = 'glb',
    ) -> OATResult:
        zone = Path(zone_path)
        out = Path(destination)
        out.mkdir(parents=True, exist_ok=True)

        failures: list[str] = []
        if not self.unlinker_path.is_file():
            return OATResult(False, -1, (), (f'unlinker missing: {self.unlinker_path}',), '', '')
        if image_format.lower() not in {'dds', 'iwi'}:
            return OATResult(False, -1, (), (f'unsupported OAT image format: {image_format}',), '', '')
        if model_format.lower() not in {'xmodel_export', 'xmodel_bin', 'obj', 'gltf', 'glb'}:
            return OATResult(False, -1, (), (f'unsupported OAT model format: {model_format}',), '', '')

        command = [
            str(self.unlinker_path),
            '-o', str(out),
            '--image-format', image_format.lower(),
            '--model-format', model_format.lower(),
        ]
        if search_path is not None:
            command.extend(['--search-path', str(Path(search_path))])
        command.append(str(zone))

        proc = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            failures.append(f'OpenAssetTools exited with code {proc.returncode}')

        root = out.resolve()
        collected: dict[str, Path] = {}

        def collect(candidate: Path) -> None:
            if not candidate.is_file():
                return
            resolved = candidate.resolve()
            try:
                resolved.relative_to(root)
            except ValueError:
                failures.append(f'output escaped destination: {candidate}')
                return
            collected[str(resolved)] = candidate

        if expected_globs:
            for pattern in expected_globs:
                matches = list(out.glob(pattern))
                if not matches:
                    failures.append(f'expected output not produced: {pattern}')
                    continue
                for candidate in matches:
                    collect(candidate)
        else:
            for candidate in out.rglob('*'):
                collect(candidate)

        outputs = tuple(collected[key] for key in sorted(collected))
        return OATResult(
            complete=not failures,
            returncode=proc.returncode,
            outputs=outputs,
            failures=tuple(failures),
            stdout=proc.stdout,
            stderr=proc.stderr,
        )

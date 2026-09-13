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
    ) -> OATResult:
        zone = Path(zone_path)
        out = Path(destination)
        out.mkdir(parents=True, exist_ok=True)

        failures: list[str] = []
        if not self.unlinker_path.is_file():
            return OATResult(False, -1, (), (f'unlinker missing: {self.unlinker_path}',), '', '')

        proc = subprocess.run(
            [str(self.unlinker_path), str(zone), str(out)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            failures.append(f'OpenAssetTools exited with code {proc.returncode}')

        root = out.resolve()
        collected: dict[str, Path] = {}
        for pattern in expected_globs:
            matches = list(out.glob(pattern))
            if not matches:
                failures.append(f'expected output not produced: {pattern}')
                continue
            for candidate in matches:
                if not candidate.is_file():
                    continue
                resolved = candidate.resolve()
                try:
                    resolved.relative_to(root)
                except ValueError:
                    failures.append(f'output escaped destination: {candidate}')
                    continue
                collected[str(resolved)] = candidate

        outputs = tuple(collected[key] for key in sorted(collected))
        return OATResult(
            complete=not failures,
            returncode=proc.returncode,
            outputs=outputs,
            failures=tuple(failures),
            stdout=proc.stdout,
            stderr=proc.stderr,
        )

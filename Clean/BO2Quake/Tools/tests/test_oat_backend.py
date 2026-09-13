from pathlib import Path
from tempfile import TemporaryDirectory
import stat
import unittest

from Clean.BO2Quake.Converter.bo2convert.oat_backend import OATBackend


class OATBackendTests(unittest.TestCase):
    def _tool(self, root: Path, body: str) -> Path:
        tool = root / 'fake-unlinker'
        tool.write_text('#!/bin/sh\nset -eu\n' + body + '\n')
        tool.chmod(tool.stat().st_mode | stat.S_IXUSR)
        return tool

    def test_success_requires_expected_output_not_only_exit_zero(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            tool = self._tool(root, 'exit 0')
            backend = OATBackend(tool)
            result = backend.dump_zone(root / 'zone.ff', root / 'out', expected_globs=['model_export/*'])
            self.assertFalse(result.complete)
            self.assertTrue(any('expected output' in failure for failure in result.failures))

    def test_validates_real_output_paths_stay_under_destination(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            tool = self._tool(root, 'mkdir -p "$2/model_export"; printf x > "$2/model_export/a.glb"')
            backend = OATBackend(tool)
            result = backend.dump_zone(root / 'zone.ff', root / 'out', expected_globs=['model_export/*.glb'])
            self.assertTrue(result.complete)
            self.assertEqual(len(result.outputs), 1)
            self.assertEqual(result.outputs[0].name, 'a.glb')

    def test_nonzero_tool_exit_is_failure(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            tool = self._tool(root, 'echo nope >&2; exit 7')
            backend = OATBackend(tool)
            result = backend.dump_zone(root / 'zone.ff', root / 'out', expected_globs=[])
            self.assertFalse(result.complete)
            self.assertEqual(result.returncode, 7)

    def test_empty_expected_globs_returns_full_recursive_inventory(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            body = 'mkdir -p "$2/materials" "$2/xmodel"; printf m > "$2/materials/a.json"; printf g > "$2/xmodel/b.glb"'
            tool = self._tool(root, body)
            backend = OATBackend(tool)
            result = backend.dump_zone(root / 'zone.ff', root / 'out', expected_globs=[])
            self.assertTrue(result.complete, result.failures)
            rel = {p.relative_to(root / 'out').as_posix() for p in result.outputs}
            self.assertEqual(rel, {'materials/a.json', 'xmodel/b.glb'})

    def test_invocation_uses_real_unlinker_flags(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            args_file = root / 'args.txt'
            body = f'printf "%s\\n" "$@" > "{args_file}"; exit 0'
            tool = self._tool(root, body)
            backend = OATBackend(tool)
            backend.dump_zone(root / 'zone.ff', root / 'out', expected_globs=[])
            args = args_file.read_text().splitlines()
            self.assertEqual(args[:6], ['-o', str(root / 'out'), '--image-format', 'dds', '--model-format', 'glb'])
            self.assertEqual(args[-1], str(root / 'zone.ff'))


if __name__ == '__main__':
    unittest.main()

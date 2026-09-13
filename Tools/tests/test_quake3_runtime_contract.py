from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
HEADER = ROOT / "Engine/Quake3/zq3_runtime.h"
SOURCE = ROOT / "Engine/Quake3/zq3_runtime.c"
README = ROOT / "Engine/Quake3/README.md"
PROJECT = ROOT / "project.yml"


class QuakeRuntimeContractTests(unittest.TestCase):
    def test_c_facade_exports_required_runtime_calls(self):
        text = HEADER.read_text(encoding="utf-8")
        for symbol in (
            "zq3_init", "zq3_load_world", "zq3_set_input",
            "zq3_step", "zq3_get_player_state", "zq3_shutdown"
        ):
            self.assertIn(symbol, text)

    def test_runtime_keeps_quake_attribution(self):
        readme = README.read_text(encoding="utf-8")
        source = SOURCE.read_text(encoding="utf-8")
        self.assertIn("id Software", readme)
        self.assertIn("GPL", readme)
        self.assertIn("Quake III Arena", source)

    def test_xcodegen_builds_engine_and_metal(self):
        text = PROJECT.read_text(encoding="utf-8")
        self.assertIn("Engine/Quake3", text)
        self.assertIn("MetalKit.framework", text)


if __name__ == "__main__":
    unittest.main()

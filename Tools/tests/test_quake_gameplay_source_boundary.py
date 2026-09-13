from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
VIEW = ROOT / "Sources/ZombiesIOS/Views/QuakeGameplayView.swift"
CONTROLLER = ROOT / "Sources/ZombiesIOS/EngineBridge/QuakeRuntimeController.swift"
CI = ROOT / "Sources/ZombiesIOS/Views/CIGameplayValidationEntryView.swift"


class QuakeGameplaySourceBoundaryTests(unittest.TestCase):
    def test_quake_view_is_metal_backed(self):
        text = VIEW.read_text(encoding="utf-8")
        self.assertIn("MTKView", text)
        self.assertIn("MTKViewDelegate", text)
        self.assertNotIn("SceneKit", text)

    def test_controller_calls_c_runtime(self):
        text = CONTROLLER.read_text(encoding="utf-8")
        for symbol in ("zq3_init", "zq3_load_world", "zq3_set_input", "zq3_step"):
            self.assertIn(symbol, text)

    def test_ci_entry_uses_quake_view(self):
        text = CI.read_text(encoding="utf-8")
        self.assertIn("QuakeGameplayView", text)
        self.assertNotIn("NativeFPSSceneView", text)
        self.assertNotIn("SceneKit", text)


if __name__ == "__main__":
    unittest.main()

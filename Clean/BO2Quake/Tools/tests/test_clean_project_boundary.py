from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[4]
CLEAN = ROOT / "Clean" / "BO2Quake"


class CleanProjectBoundaryTests(unittest.TestCase):
    def test_clean_app_is_metal_quake_only(self):
        project = (CLEAN / "project.yml").read_text()
        app = CLEAN / "Sources" / "App" / "BO2QuakeApp.swift"
        self.assertTrue(app.exists())
        self.assertIn("MetalKit.framework", project)
        self.assertIn("Engine/Quake3", project)
        self.assertNotIn("SceneKit.framework", project)

    def test_public_content_audit_blocks_retail_payloads(self):
        audit = (CLEAN / "Tools" / "content_audit.py").read_text()
        for marker in (".ff", ".ipak", ".sabs", ".xpak", "GameData"):
            self.assertIn(marker, audit)


if __name__ == "__main__":
    unittest.main()

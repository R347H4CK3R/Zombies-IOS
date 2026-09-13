from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BO2QuakePrimaryRuntimeTests(unittest.TestCase):
    def test_runtime_package_boundary_exists(self):
        package = ROOT / "Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2RuntimePackage.swift"
        writer = ROOT / "Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2RuntimePackageWriter.swift"
        self.assertTrue(package.exists())
        self.assertTrue(writer.exists())
        text = package.read_text()
        self.assertIn("static let formatVersion: UInt32 = 1", text)
        self.assertIn("let indices: [UInt32]", text)
        self.assertIn("let spawns: [BO2RuntimeSpawn]", text)
        self.assertIn("let entities: [BO2RuntimeEntity]", text)
        self.assertIn("RuntimeCachePolicy.expressiveDirectory()", writer.read_text())

    def test_quake_c_runtime_and_metal_host_exist(self):
        header = ROOT / "Engine/Quake3/zq3_runtime.h"
        source = ROOT / "Engine/Quake3/zq3_runtime.c"
        controller = ROOT / "Sources/ZombiesIOS/EngineBridge/QuakeRuntimeController.swift"
        view = ROOT / "Sources/ZombiesIOS/Views/QuakeGameplayView.swift"
        for path in (header, source, controller, view):
            self.assertTrue(path.exists(), path)
        api = header.read_text()
        for symbol in ("zq3_init", "zq3_load_world", "zq3_set_input", "zq3_step", "zq3_get_player_state", "zq3_shutdown"):
            self.assertIn(symbol, api)
        runtime = source.read_text()
        self.assertIn("world_floor", runtime)
        self.assertIn("barycentric_height", runtime)
        metal = view.read_text()
        self.assertIn("MTKView", metal)
        self.assertIn("playerState", metal)
        self.assertIn("CameraUniforms", metal)

    def test_xcodegen_compiles_engine_and_metal(self):
        project = (ROOT / "project.yml").read_text()
        self.assertIn("Engine/Quake3", project)
        self.assertIn("MetalKit.framework", project)

    def test_xcodegen_excludes_engine_test_programs_from_app(self):
        project = (ROOT / "project.yml").read_text()
        self.assertIn("excludes:", project)
        self.assertIn("Engine/Quake3/tests", project)

    def test_hijacked_is_primary_map_target(self):
        target = ROOT / "Sources/ZombiesIOS/Models/BO2MapTarget.swift"
        loader = ROOT / "Sources/ZombiesIOS/Services/BO2MapRuntimeLoader.swift"
        self.assertTrue(target.exists())
        self.assertTrue(loader.exists())
        self.assertIn('case hijacked = "mp_hijacked"', target.read_text())
        text = loader.read_text()
        self.assertIn("T6PS3PayloadDecoder", text)
        self.assertIn("T6GfxSurfaceMeshExtractor", text)
        self.assertIn("BO2RuntimePackageWriter", text)
        self.assertIn("BO2EntityParser.extractEntityLump", text)
        self.assertIn("BO2EntityParser.parse", text)

    def test_mapents_parser_maps_multiplayer_spawns(self):
        parser = ROOT / "Sources/ZombiesIOS/Services/BO2RuntimePackage/BO2EntityParser.swift"
        self.assertTrue(parser.exists())
        text = parser.read_text()
        self.assertIn("worldspawn", text)
        self.assertIn("mp_dm_spawn", text)
        self.assertIn("mp_tdm_spawn", text)
        self.assertIn("BO2RuntimeSpawn", text)
        self.assertIn("convertOrigin", text)

    def test_production_app_routes_to_quake_not_scenekit(self):
        app = (ROOT / "Sources/ZombiesIOS/ZombiesIOSApp.swift").read_text()
        content = (ROOT / "Sources/ZombiesIOS/ContentView.swift").read_text()
        ci = (ROOT / "Sources/ZombiesIOS/Views/CIGameplayValidationEntryView.swift").read_text()
        self.assertIn("BO2QuakeRootView", app)
        self.assertIn("QuakeGameplayView", content)
        self.assertNotIn("NativeFPSSceneView(", content)
        self.assertNotIn("SceneKit", ci)


if __name__ == "__main__":
    unittest.main()

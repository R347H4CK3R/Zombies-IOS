from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ConvertedAssetArchitectureTests(unittest.TestCase):
    def test_manifest_and_paths_contract_exist(self):
        manifest = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitManifest.swift").read_text()
        paths = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitPaths.swift").read_text()
        fingerprint = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedSourceFingerprint.swift").read_text()
        self.assertIn("packageFormatVersion", manifest)
        self.assertIn("complete", manifest)
        self.assertIn("ConvertedTranzit", paths)
        self.assertIn("applicationSupportDirectory", paths)
        self.assertIn("modificationDate", fingerprint)
        self.assertIn("fileSize", fingerprint)

    def test_native_mesh_format_contract_exists(self):
        mesh = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedMeshFormat.swift").read_text()
        self.assertIn("0x5A4D5348", mesh)
        self.assertIn("formatVersion", mesh)
        self.assertIn("littleEndian", mesh)
        self.assertIn("vertexCount", mesh)
        self.assertIn("indexCount", mesh)
        self.assertIn("boundsMin", mesh)
        self.assertIn("boundsMax", mesh)
        self.assertIn("indexOutOfRange", mesh)
        self.assertIn("roundTripSelfCheck", mesh)

    def test_transactional_package_store_and_validator_exist(self):
        validator = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedPackageValidator.swift").read_text()
        store = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedPackageStore.swift").read_text()
        self.assertIn("complete", validator)
        self.assertIn("packageFormatVersion", validator)
        self.assertIn("pathTraversal", validator)
        self.assertIn("collisionBoundsDoNotOverlap", validator)
        self.assertIn("ConvertedMeshFormat.decode", validator)
        self.assertIn("beginStaging", store)
        self.assertIn("promoteStaging", store)
        self.assertIn("backup", store)
        self.assertIn("moveItem", store)
        self.assertIn("activeManifest", store)

    def test_world_importer_decodes_ps3_only_during_conversion(self):
        importer = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedWorldImporter.swift").read_text()
        self.assertIn("T6PS3PayloadDecoder", importer)
        self.assertIn("T6GfxSurfaceMeshExtractor.extract", importer)
        self.assertIn("T6GfxBoundsFallbackExtractor.extract", importer)
        self.assertIn("ConvertedMeshFormat.encode", importer)
        self.assertIn("ConvertedMeshFormat.decode", importer)
        self.assertIn("world/area.mesh", importer)
        self.assertIn("selectedSourceFile", importer)
        self.assertIn("decodedChunkCount", importer)
        self.assertIn("vertexOffset", importer)
        self.assertIn("indexOffset", importer)
        self.assertIn("boundsFallbackUsed", importer)
        self.assertNotIn("SCNNode", importer)

    def test_material_and_texture_conversion_contract_exists(self):
        manifest = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedMaterialManifest.swift").read_text()
        importer = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedMaterialImporter.swift").read_text()
        self.assertIn("ConvertedMaterialRecord", manifest)
        self.assertIn("diffuseTexturePath", manifest)
        self.assertIn("fallbackReason", manifest)
        self.assertIn("doubleSided", manifest)
        self.assertIn("textures/", importer)
        self.assertIn("pngData", importer)
        self.assertIn("fallbackReason", importer)
        self.assertIn("materials/materials.json", importer)
        self.assertIn("fullFidelity", importer)

    def test_collision_conversion_is_separate_and_validated(self):
        collision = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedCollisionImporter.swift").read_text()
        self.assertIn("world/collision.mesh", collision)
        self.assertIn("ConvertedMeshFormat.decode", collision)
        self.assertIn("boundsOverlap", collision)
        self.assertIn("collisionBoundsDoNotOverlap", collision)
        self.assertNotIn("SCNPhysicsBody", collision)

    def test_weapon_conversion_requires_real_source_mesh_and_transform(self):
        weapon = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedWeaponImporter.swift").read_text()
        self.assertIn("weapons/primary.mesh", weapon)
        self.assertIn("weapons/primary.material.json", weapon)
        self.assertIn("firstPersonPosition", weapon)
        self.assertIn("firstPersonEulerAngles", weapon)
        self.assertIn("missingSourceMesh", weapon)
        self.assertIn("ConvertedMeshFormat.encode", weapon)
        self.assertNotIn("SCNBox", weapon)
        self.assertNotIn("SCNCylinder", weapon)

    def test_import_orchestrator_is_resumable_and_reports_stages(self):
        importer = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitImporter.swift").read_text()
        report = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedImportReport.swift").read_text()
        for stage in ["scanning", "decodingWorld", "convertingGeometry", "convertingTextures", "buildingCollision", "convertingWeapon", "validating", "ready"]:
            self.assertIn(stage, importer)
        self.assertIn("ConvertedSourceFingerprint.make", importer)
        self.assertIn("ConvertedStagingState.fileName", importer)
        self.assertIn("staging-state.json", report)
        self.assertIn("beginStaging", importer)
        self.assertIn("promoteStaging", importer)
        self.assertIn("manifest.json", importer)
        self.assertIn("import-report.json", report)
        self.assertIn("completedStages", report)
        self.assertIn("sourceFingerprint", report)

    def test_runtime_loader_reads_only_converted_package(self):
        loader = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedTranzitLoader.swift").read_text()
        package = (ROOT / "Sources/ZombiesIOS/ConvertedAssets/ConvertedRuntimePackage.swift").read_text()
        self.assertIn("ConvertedPackageValidator.validate", loader)
        self.assertIn("ConvertedMeshFormat.decode", loader)
        self.assertIn("ConvertedMaterialManifest", loader)
        self.assertIn("ConvertedWeaponMaterialMetadata", loader)
        self.assertIn("sourceFingerprint", package)
        self.assertIn("worldMesh", package)
        self.assertIn("collisionMesh", package)
        self.assertIn("weaponMesh", package)
        self.assertNotIn("T6PS3PayloadDecoder", loader)
        self.assertNotIn("T6GfxSurfaceMeshExtractor", loader)
        self.assertNotIn("zm_transit.ff", loader)


if __name__ == "__main__":
    unittest.main()

import Foundation
import UIKit

#if DEBUG
enum CIConvertedPackageFixture {
    static func makeAndLoad() throws -> ConvertedRuntimePackage {
        let store = ConvertedPackageStore()
        let root = try store.beginStaging()
        let fm = FileManager.default

        try fm.createDirectory(at: root.appendingPathComponent("world", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("materials", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("textures", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("weapons", isDirectory: true), withIntermediateDirectories: true)

        let world = roomMesh()
        try ConvertedMeshFormat.encode(world).write(
            to: root.appendingPathComponent("world/area.mesh"),
            options: .atomic
        )
        try ConvertedMeshFormat.encode(world).write(
            to: root.appendingPathComponent("world/collision.mesh"),
            options: .atomic
        )

        let texturePath = "textures/ci-checker.png"
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let image = renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            context.fill(CGRect(x: 32, y: 32, width: 32, height: 32))
        }
        guard let png = image.pngData() else { throw FixtureError.textureEncodingFailed }
        try png.write(to: root.appendingPathComponent(texturePath), options: .atomic)

        let materialManifest = ConvertedMaterialManifest(
            materials: [
                ConvertedMaterialRecord(
                    id: 0,
                    name: "ci_checker",
                    diffuseTexturePath: texturePath,
                    fallbackReason: nil,
                    doubleSided: true
                )
            ],
            fullFidelity: true
        )
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try jsonEncoder.encode(materialManifest).write(
            to: root.appendingPathComponent("materials/materials.json"),
            options: .atomic
        )

        let weapon = weaponMesh()
        try ConvertedMeshFormat.encode(weapon).write(
            to: root.appendingPathComponent("weapons/primary.mesh"),
            options: .atomic
        )
        let weaponMaterial = ConvertedWeaponMaterialMetadata(
            name: "ci_weapon",
            diffuseTexturePath: texturePath,
            fallbackReason: nil,
            transform: ConvertedWeaponTransform(
                firstPersonPosition: ConvertedFloat3(SIMD3<Float>(0.30, -0.28, -0.70)),
                firstPersonEulerAngles: ConvertedFloat3(SIMD3<Float>(0, 0, 0)),
                scale: 0.55
            )
        )
        try jsonEncoder.encode(weaponMaterial).write(
            to: root.appendingPathComponent("weapons/primary.material.json"),
            options: .atomic
        )

        let manifest = ConvertedTranzitManifest(
            formatVersion: ConvertedTranzitManifest.packageFormatVersion,
            sourceFingerprint: ConvertedSourceFingerprint(files: []),
            sourceAreaName: "CI Converted Room",
            createdAt: Date(),
            converterBuild: "CI-CONVERTED-FIXTURE",
            worldMeshPath: "world/area.mesh",
            collisionMeshPath: "world/collision.mesh",
            materialManifestPath: "materials/materials.json",
            weaponMeshPath: "weapons/primary.mesh",
            convertedTextureCount: 1,
            vertexCount: world.positions.count,
            indexCount: world.indices.count,
            worldBoundsMin: ConvertedFloat3(world.boundsMin),
            worldBoundsMax: ConvertedFloat3(world.boundsMax),
            complete: true,
            stageDiagnostics: ["fixture": "converted-package"]
        )
        let manifestEncoder = JSONEncoder()
        manifestEncoder.dateEncodingStrategy = .iso8601
        manifestEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try manifestEncoder.encode(manifest).write(
            to: root.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        _ = try ConvertedPackageValidator.validate(at: root)
        try store.promoteStaging()
        return try ConvertedTranzitLoader().load()
    }

    private static func roomMesh() -> ConvertedMesh {
        let p: [SIMD3<Float>] = [
            SIMD3(-8, 0, -8), SIMD3(8, 0, -8), SIMD3(8, 0, 8), SIMD3(-8, 0, 8),
            SIMD3(-8, 7, -8), SIMD3(8, 7, -8), SIMD3(8, 7, 8), SIMD3(-8, 7, 8)
        ]
        let i: [UInt32] = [
            0, 2, 1, 0, 3, 2,
            0, 1, 5, 0, 5, 4,
            1, 2, 6, 1, 6, 5,
            2, 3, 7, 2, 7, 6,
            3, 0, 4, 3, 4, 7
        ]
        return ConvertedMesh(
            positions: p,
            indices: i,
            boundsMin: SIMD3(-8, 0, -8),
            boundsMax: SIMD3(8, 7, 8),
            materialGroups: [.init(materialID: 0, firstIndex: 0, indexCount: UInt32(i.count))]
        )
    }

    private static func weaponMesh() -> ConvertedMesh {
        let p: [SIMD3<Float>] = [
            SIMD3(-0.22, -0.10, 0), SIMD3(0.22, -0.10, 0), SIMD3(0.18, 0.10, 0), SIMD3(-0.18, 0.10, 0),
            SIMD3(-0.16, -0.08, -0.8), SIMD3(0.16, -0.08, -0.8), SIMD3(0.14, 0.08, -0.8), SIMD3(-0.14, 0.08, -0.8)
        ]
        let i: [UInt32] = [
            0, 1, 2, 0, 2, 3,
            4, 6, 5, 4, 7, 6,
            0, 4, 5, 0, 5, 1,
            1, 5, 6, 1, 6, 2,
            2, 6, 7, 2, 7, 3,
            3, 7, 4, 3, 4, 0
        ]
        return ConvertedMesh(
            positions: p,
            indices: i,
            boundsMin: SIMD3(-0.22, -0.10, -0.8),
            boundsMax: SIMD3(0.22, 0.10, 0),
            materialGroups: [.init(materialID: 0, firstIndex: 0, indexCount: UInt32(i.count))]
        )
    }

    enum FixtureError: Error {
        case textureEncodingFailed
    }
}
#endif

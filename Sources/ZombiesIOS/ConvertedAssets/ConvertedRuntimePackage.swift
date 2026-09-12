import Foundation

struct ConvertedRuntimePackage {
    let rootURL: URL
    let manifest: ConvertedTranzitManifest
    let worldMesh: ConvertedMesh
    let collisionMesh: ConvertedMesh
    let materialManifest: ConvertedMaterialManifest
    let weaponMesh: ConvertedMesh
    let weaponMaterial: ConvertedWeaponMaterialMetadata

    var sourceFingerprint: ConvertedSourceFingerprint {
        manifest.sourceFingerprint
    }

    func textureURL(for material: ConvertedMaterialRecord) -> URL? {
        guard let relative = material.diffuseTexturePath else { return nil }
        return rootURL.appendingPathComponent(relative, isDirectory: false)
    }
}

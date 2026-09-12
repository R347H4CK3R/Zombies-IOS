import Foundation

enum T6TextureFormat: Hashable, Sendable {
    case rgba8Unorm
    case bc1Unorm
    case unsupported(dxgi: Int32)
}

struct T6DecodedTexture: Hashable, Sendable {
    let imageID: T6AssetID
    let width: Int
    let height: Int
    let depth: Int
    let mipCount: Int
    let format: T6TextureFormat
    let hasAlpha: Bool
    let rgba8: Data
}

enum T6MaterialAlphaMode: String, Hashable, Sendable {
    case opaque
    case mask
    case blend
}

struct T6RenderableMaterial: Hashable, Sendable {
    let materialID: T6AssetID
    let baseColorTexture: T6DecodedTexture?
    let alphaMode: T6MaterialAlphaMode
    let isFallback: Bool
}

struct T6RenderableProp: Hashable, Sendable {
    let modelID: T6AssetID
    let transform: simd_float4x4
}

struct T6RenderableWeapon: Hashable, Sendable {
    let weaponID: T6AssetID
    let modelID: T6AssetID?
}

struct T6RenderDiagnostics: Hashable, Sendable {
    let unresolvedMaterialPointers: [UInt32]
    let unsupportedTextureFormats: [Int32]
    let notes: [String]
}

struct T6RenderableWorld: Sendable {
    let surfaces: [T6WorldSurface]
    let materials: [T6AssetID: T6RenderableMaterial]
    let props: [T6RenderableProp]
    let firstPersonWeapon: T6RenderableWeapon?
    let spawnPosition: SIMD3<Float>
    let spawnForward: SIMD3<Float>
    let usesDiagnosticGeometry: Bool
    let diagnostics: T6RenderDiagnostics

    var triangleCount: Int {
        surfaces.reduce(0) { $0 + ($1.indices.count / 3) }
    }

    var nonFallbackMaterialCount: Int {
        materials.values.reduce(0) { $0 + ($1.isFallback ? 0 : 1) }
    }

    var isCertifiable: Bool {
        !usesDiagnosticGeometry && triangleCount > 0 && nonFallbackMaterialCount > 0
    }
}

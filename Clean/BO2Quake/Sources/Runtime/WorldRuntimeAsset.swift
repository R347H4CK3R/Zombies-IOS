import Foundation
import simd

enum WorldRuntimeAssetError: LocalizedError {
    case missingWorldAsset
    case missingPayload(String)
    case invalidMetadata(String)
    case invalidVertexBuffer
    case invalidIndexBuffer

    var errorDescription: String? {
        switch self {
        case .missingWorldAsset: return "No converted world asset is present in GameData."
        case .missingPayload(let name): return "World payload is missing: \(name)"
        case .invalidMetadata(let message): return "Invalid world metadata: \(message)"
        case .invalidVertexBuffer: return "World vertex buffer is malformed."
        case .invalidIndexBuffer: return "World index buffer is malformed."
        }
    }
}

struct WorldSurfaceMetadata: Codable, Equatable {
    let sourceSurface: Int
    let firstVertex: Int
    let vertexCount: Int
    let firstIndex: Int
    let indexCount: Int
    let triangleCount: Int
    let material: String
    let lightmapIndex: Int
    let reflectionProbeIndex: Int
    let primaryLightIndex: Int
    let flags: Int
    let mins: [Float]
    let maxs: [Float]
}

struct WorldRuntimeMetadata: Codable, Equatable {
    let formatVersion: Int
    let vertexStride: Int
    let vertexCount: Int
    let indexType: String
    let indexCount: Int
    let surfaceCount: Int
    let coordinateSystem: String
    let surfaces: [WorldSurfaceMetadata]
}

struct WorldRuntimeAsset {
    static let vertexStride = 44

    let id: String
    let vertexData: Data
    let indexData: Data
    let metadata: WorldRuntimeMetadata
    let center: SIMD3<Float>
    let radius: Float

    static func loadFirst(from gameData: LoadedGameData) throws -> WorldRuntimeAsset {
        guard let asset = gameData.manifest.assets.first(where: { $0.kind == "world" }) else {
            throw WorldRuntimeAssetError.missingWorldAsset
        }
        return try load(asset: asset, from: gameData)
    }

    static func load(asset: GameDataAsset, from gameData: LoadedGameData) throws -> WorldRuntimeAsset {
        func payloadURL(_ name: String) throws -> URL {
            guard let payload = asset.payloads.first(where: { $0.name == name }) else {
                throw WorldRuntimeAssetError.missingPayload(name)
            }
            return gameData.root.appendingPathComponent(payload.path)
        }

        let vertexData = try Data(contentsOf: payloadURL("vertices.bin"), options: .mappedIfSafe)
        let indexData = try Data(contentsOf: payloadURL("indices.bin"), options: .mappedIfSafe)
        let metadataData = try Data(contentsOf: payloadURL("surfaces.json"), options: .mappedIfSafe)
        let metadata = try JSONDecoder().decode(WorldRuntimeMetadata.self, from: metadataData)

        guard metadata.formatVersion == 1 else {
            throw WorldRuntimeAssetError.invalidMetadata("unsupported version \(metadata.formatVersion)")
        }
        guard metadata.vertexStride == Self.vertexStride else {
            throw WorldRuntimeAssetError.invalidMetadata("vertexStride \(metadata.vertexStride) != \(Self.vertexStride)")
        }
        guard metadata.indexType == "uint32" else {
            throw WorldRuntimeAssetError.invalidMetadata("indexType must be uint32")
        }
        guard metadata.surfaceCount == metadata.surfaces.count else {
            throw WorldRuntimeAssetError.invalidMetadata("surface count mismatch")
        }
        guard vertexData.count == metadata.vertexCount * Self.vertexStride else {
            throw WorldRuntimeAssetError.invalidVertexBuffer
        }
        guard indexData.count == metadata.indexCount * MemoryLayout<UInt32>.size else {
            throw WorldRuntimeAssetError.invalidIndexBuffer
        }

        for (surfaceIndex, surface) in metadata.surfaces.enumerated() {
            guard surface.firstVertex >= 0,
                  surface.vertexCount >= 3,
                  surface.firstVertex + surface.vertexCount <= metadata.vertexCount else {
                throw WorldRuntimeAssetError.invalidMetadata("surface \(surfaceIndex) vertex range")
            }
            guard surface.firstIndex >= 0,
                  surface.indexCount == surface.triangleCount * 3,
                  surface.firstIndex + surface.indexCount <= metadata.indexCount else {
                throw WorldRuntimeAssetError.invalidMetadata("surface \(surfaceIndex) index range")
            }
            guard gameData.assetsByID[surface.material]?.kind == "material" else {
                throw WorldRuntimeAssetError.invalidMetadata("surface \(surfaceIndex) unresolved material \(surface.material)")
            }
        }

        let bounds = try computeBounds(vertexData: vertexData, vertexCount: metadata.vertexCount)
        return WorldRuntimeAsset(
            id: asset.id,
            vertexData: vertexData,
            indexData: indexData,
            metadata: metadata,
            center: bounds.center,
            radius: bounds.radius
        )
    }

    private static func computeBounds(vertexData: Data, vertexCount: Int) throws -> (center: SIMD3<Float>, radius: Float) {
        guard vertexCount > 0 else { throw WorldRuntimeAssetError.invalidVertexBuffer }
        var minPoint = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxPoint = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        for index in 0..<vertexCount {
            let base = index * Self.vertexStride
            let x = readFloatLE(vertexData, base)
            let y = readFloatLE(vertexData, base + 4)
            let z = readFloatLE(vertexData, base + 8)
            guard x.isFinite, y.isFinite, z.isFinite else {
                throw WorldRuntimeAssetError.invalidVertexBuffer
            }
            let point = SIMD3<Float>(x, y, z)
            minPoint = simd_min(minPoint, point)
            maxPoint = simd_max(maxPoint, point)
        }
        let center = (minPoint + maxPoint) * 0.5
        let radius = max(simd_length(maxPoint - center), 1.0)
        return (center, radius)
    }

    private static func readFloatLE(_ data: Data, _ offset: Int) -> Float {
        let bits: UInt32 = data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        return Float(bitPattern: UInt32(littleEndian: bits))
    }
}

import Foundation

struct T6MaterialConversionResult: Sendable {
    let materials: [TranzitCachedMaterial]
    let warnings: [String]
}

enum T6MaterialConverter {
    static func convert(payload: Data, assets: T6ResolvedAssetIndex) -> T6MaterialConversionResult {
        let records = assets.all(.material)
        var materials: [TranzitCachedMaterial] = []
        var warnings: [String] = []
        materials.reserveCapacity(max(1, records.count))

        for (id, record) in records.enumerated() {
            let offset = T6AssetResolver.payloadOffset(for: record, payloadCount: payload.count)
            let name: String
            if let offset, offset + 4 <= payload.count,
               let nameOffset = payloadOffset(be32(payload, offset), count: payload.count),
               let resolved = cString(payload, at: nameOffset) {
                name = resolved
            } else {
                name = "t6_material_\(id)"
                warnings.append("Material \(id) uses an unresolved serialized pointer; fallback name/material mapping retained.")
            }

            materials.append(TranzitCachedMaterial(
                id: id,
                name: name,
                diffuseTexture: nil,
                normalTexture: nil,
                specularTexture: nil,
                alphaCutout: false
            ))
        }

        if materials.isEmpty {
            warnings.append("No directly resolvable T6 materials were available; renderer will use the diagnostic world material.")
            materials = [TranzitCachedMaterial(
                id: 0,
                name: "diagnostic_world",
                diffuseTexture: nil,
                normalTexture: nil,
                specularTexture: nil,
                alphaCutout: false
            )]
        }
        return T6MaterialConversionResult(materials: materials, warnings: warnings)
    }

    private static func payloadOffset(_ pointer: UInt32, count: Int) -> Int? {
        guard pointer != .max, pointer != 0xfffffffe, Int(pointer) >= 0, Int(pointer) < count else { return nil }
        return Int(pointer)
    }

    private static func cString(_ data: Data, at offset: Int, maxLength: Int = 256) -> String? {
        guard offset >= 0, offset < data.count else { return nil }
        var bytes: [UInt8] = []
        for i in offset..<min(data.count, offset + maxLength) {
            let b = data[i]
            if b == 0 { break }
            guard b >= 0x20, b <= 0x7e else { return nil }
            bytes.append(b)
        }
        guard !bytes.isEmpty else { return nil }
        return String(bytes: bytes, encoding: .utf8)
    }

    private static func be32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return .max }
        return (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
    }
}

import Foundation

struct T6MaterialConversionResult: Sendable {
    let materials: [TranzitCachedMaterial]
    let warnings: [String]
}

enum T6MaterialConverter {
    private static let materialMinimumSize = 96
    private static let textureDefStride = 16

    static func convert(payload: Data, assets: T6ResolvedAssetIndex) -> T6MaterialConversionResult {
        let records = assets.all(.material)
        let imageRecords = assets.all(.gfxImage)
        var imageNameByPointer: [UInt32: String] = [:]
        for (index, image) in imageRecords.enumerated() where imageNameByPointer[image.rawPointer] == nil {
            imageNameByPointer[image.rawPointer] = String(format: "gfximage_%05d.png", index)
        }

        var materials: [TranzitCachedMaterial] = []
        var warnings: [String] = []
        materials.reserveCapacity(max(1, records.count))

        for (id, record) in records.enumerated() {
            guard let offset = T6AssetResolver.payloadOffset(for: record, payloadCount: payload.count),
                  offset + materialMinimumSize <= payload.count else {
                materials.append(fallbackMaterial(id: id, name: "t6_material_\(id)"))
                warnings.append("Material \(id) uses an unresolved serialized pointer; diagnostic bindings retained.")
                continue
            }

            let name: String
            if let nameOffset = payloadOffset(be32(payload, offset), count: payload.count),
               let resolved = cString(payload, at: nameOffset) {
                name = resolved
            } else {
                name = "t6_material_\(id)"
            }

            // T6 32-bit Material layout (OpenAssetTools): MaterialInfo is 32 bytes,
            // followed by stateBitsEntry[36]. textureCount is therefore +0x44.
            // After six one-byte count/flag fields and 2-byte alignment padding,
            // techniqueSet is +0x4C and textureTable is +0x50.
            let textureCount = min(Int(payload[offset + 0x44]), 64)
            let textureTablePointer = be32(payload, offset + 0x50)
            var diffuse: String?
            var normal: String?
            var specular: String?

            if textureCount > 0,
               let tableOffset = payloadOffset(textureTablePointer, count: payload.count),
               tableOffset + textureCount * textureDefStride <= payload.count {
                for textureIndex in 0..<textureCount {
                    let entry = tableOffset + textureIndex * textureDefStride
                    let semantic = payload[entry + 7]
                    let imagePointer = be32(payload, entry + 12)
                    guard let fileName = imageNameByPointer[imagePointer] else { continue }
                    switch semantic {
                    case 2: // TS_COLOR_MAP
                        if diffuse == nil { diffuse = fileName }
                    case 5: // TS_NORMAL_MAP
                        if normal == nil { normal = fileName }
                    case 8: // TS_SPECULAR_MAP
                        if specular == nil { specular = fileName }
                    case 0: // TS_2D: use as a base color only when no explicit color map exists.
                        if diffuse == nil { diffuse = fileName }
                    default:
                        break
                    }
                }
            } else if textureCount > 0 {
                warnings.append("Material \(id) (\(name)): texture table pointer is unresolved; fallback texture bindings retained.")
            }

            materials.append(TranzitCachedMaterial(
                id: id,
                name: name,
                diffuseTexture: diffuse,
                normalTexture: normal,
                specularTexture: specular,
                alphaCutout: false
            ))
        }

        if materials.isEmpty {
            warnings.append("No directly resolvable T6 materials were available; renderer will use the diagnostic world material.")
            materials = [fallbackMaterial(id: 0, name: "diagnostic_world")]
        }
        return T6MaterialConversionResult(materials: materials, warnings: warnings)
    }

    private static func fallbackMaterial(id: Int, name: String) -> TranzitCachedMaterial {
        TranzitCachedMaterial(
            id: id,
            name: name,
            diffuseTexture: nil,
            normalTexture: nil,
            specularTexture: nil,
            alphaCutout: false
        )
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

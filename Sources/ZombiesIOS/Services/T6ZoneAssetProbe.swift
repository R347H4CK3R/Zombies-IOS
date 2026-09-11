import Foundation

struct T6ZoneAssetProbeReport: Sendable {
    let printableStringCount: Int
    let candidateAssetCount: Int
    let modelLikeCount: Int
    let materialLikeCount: Int
    let soundLikeCount: Int
    let mapLikeCount: Int
    let sampleNames: [String]

    let topLevelParsed: Bool
    let topLevelAssetCount: Int
    let xModelAssetCount: Int
    let materialAssetCount: Int
    let imageAssetCount: Int
    let assetTableOffset: Int?
    let topLevelTypeCounts: [String: Int]

    var summary: String {
        if topLevelParsed {
            return "XASSETS \(topLevelAssetCount)  XMODELS \(xModelAssetCount)  IMAGES \(imageAssetCount)"
        }
        return "ASSETS \(candidateAssetCount)  MODELS \(modelLikeCount)"
    }
}

enum T6ZoneAssetProbe {
    // T6 asset type ids from the game's XAssetType enum.
    private static let assetTypeNames: [String] = [
        "XModelPieces", "PhysPreset", "PhysConstraints", "DestructibleDef",
        "XAnimParts", "XModel", "Material", "MaterialTechniqueSet", "GfxImage",
        "SndBank", "SndPatch", "clipMap_t", "clipMapPvs", "ComWorld",
        "GameWorldSp", "GameWorldMp", "MapEnts", "GfxWorld", "GfxLightDef",
        "UiMap", "Font_s", "FontIcon", "MenuList", "menuDef_t", "LocalizeEntry",
        "WeaponVariantDef", "WeaponDef", "WeaponVariant", "WeaponFull",
        "WeaponAttachment", "WeaponAttachmentUnique", "WeaponCamo", "SndDriverGlobals",
        "FxEffectDef", "FxImpactTable", "AiType", "MpType", "MpBody", "MpHead",
        "Character", "XModelAlias", "RawFile", "StringTable", "LeaderboardDef",
        "XGlobals", "ddlRoot_t", "Glasses", "EmblemSet", "ScriptParseTree",
        "KeyValuePairs", "VehicleDef", "MemoryBlock", "AddonMapEnts", "TracerDef",
        "SkinnedVertsDef", "Qdb", "Slug", "FootstepTableDef", "FootstepFXTableDef",
        "ZBarrierDef"
    ]

    private struct TopLevelIndex {
        let assetCount: Int
        let assetTableOffset: Int
        let typeCounts: [String: Int]

        var xModelCount: Int { typeCounts["XModel", default: 0] }
        var materialCount: Int { typeCounts["Material", default: 0] }
        var imageCount: Int { typeCounts["GfxImage", default: 0] }
    }

    static func analyze(_ data: Data, maxSamples: Int = 10) -> T6ZoneAssetProbeReport {
        let topLevel = parseTopLevelIndex(data)

        var strings: [String] = []
        strings.reserveCapacity(1024)

        var current = [UInt8]()
        current.reserveCapacity(96)

        func flush() {
            guard current.count >= 4,
                  current.count <= 160,
                  let value = String(bytes: current, encoding: .ascii) else {
                current.removeAll(keepingCapacity: true)
                return
            }
            strings.append(value)
            current.removeAll(keepingCapacity: true)
        }

        for byte in data {
            if byte >= 0x20 && byte <= 0x7E {
                if current.count < 160 {
                    current.append(byte)
                } else {
                    flush()
                }
            } else {
                flush()
            }
        }
        flush()

        var unique = Set<String>()
        var candidates: [String] = []
        candidates.reserveCapacity(strings.count / 3)

        var modelLike = 0
        var materialLike = 0
        var soundLike = 0
        var mapLike = 0

        for raw in strings {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = value.lowercased()

            guard value.count >= 4,
                  value.rangeOfCharacter(from: .letters) != nil,
                  value.contains("_") || value.contains("/") || value.contains(".") else {
                continue
            }
            guard unique.insert(value).inserted else { continue }

            let isModel = lower.contains("xmodel") ||
                lower.contains("model_") ||
                lower.contains("zombie") ||
                lower.contains("weapon_") ||
                lower.hasPrefix("p6_")
            let isMaterial = lower.contains("material") ||
                lower.hasPrefix("mtl_") ||
                lower.contains("/mtl_") ||
                lower.contains(".iwi") ||
                lower.contains("image_")
            let isSound = lower.contains("sound") ||
                lower.contains(".wav") ||
                lower.contains(".mp3") ||
                lower.contains("vox_") ||
                lower.contains("audio")
            let isMap = lower.contains("zm_") ||
                lower.contains("transit") ||
                lower.contains("tranzit") ||
                lower.contains("gump_")

            if isModel { modelLike += 1 }
            if isMaterial { materialLike += 1 }
            if isSound { soundLike += 1 }
            if isMap { mapLike += 1 }

            if isModel || isMaterial || isSound || isMap {
                candidates.append(value)
            }
        }

        let orderedSamples = candidates
            .sorted { lhs, rhs in
                let l = lhs.lowercased()
                let r = rhs.lowercased()
                let lp = samplePriority(l)
                let rp = samplePriority(r)
                if lp != rp { return lp < rp }
                return lhs.count < rhs.count
            }
            .prefix(max(0, maxSamples))

        return T6ZoneAssetProbeReport(
            printableStringCount: strings.count,
            candidateAssetCount: candidates.count,
            modelLikeCount: modelLike,
            materialLikeCount: materialLike,
            soundLikeCount: soundLike,
            mapLikeCount: mapLike,
            sampleNames: Array(orderedSamples),
            topLevelParsed: topLevel != nil,
            topLevelAssetCount: topLevel?.assetCount ?? 0,
            xModelAssetCount: topLevel?.xModelCount ?? 0,
            materialAssetCount: topLevel?.materialCount ?? 0,
            imageAssetCount: topLevel?.imageCount ?? 0,
            assetTableOffset: topLevel?.assetTableOffset,
            topLevelTypeCounts: topLevel?.typeCounts ?? [:]
        )
    }

    // A decoded T6 stream normally starts with a 0x28-byte XFile block-size header,
    // then XAssetList. Some PS3 files encountered in dumps have extra alignment or
    // platform-specific bytes, so first try the canonical location and then scan a
    // small header window. If the declared list cannot be walked, fall back to finding
    // the serialized XAsset[type,pointer] table directly. Asset types are a very strong
    // signature because every first dword in an entry is a small enum value.
    private static func parseTopLevelIndex(_ data: Data) -> TopLevelIndex? {
        guard data.count >= 64 else { return nil }

        var offsets = [0x28, 0x20, 0x24, 0x2C, 0x30, 0]
        for offset in stride(from: 4, through: min(0x400, max(4, data.count - 24)), by: 4) {
            if !offsets.contains(offset) { offsets.append(offset) }
        }

        for contentOffset in offsets {
            if let parsed = parseDeclaredIndex(data, contentOffset: contentOffset) {
                return parsed
            }
        }

        return scanBestAssetTable(data)
    }

    private static func parseDeclaredIndex(_ data: Data, contentOffset: Int) -> TopLevelIndex? {
        guard contentOffset >= 0, data.count >= contentOffset + 24 else { return nil }

        let scriptCount = Int(be32(data, contentOffset))
        let dependencyCount = Int(be32(data, contentOffset + 8))
        let assetCount = Int(be32(data, contentOffset + 16))

        guard scriptCount >= 0, scriptCount <= 1_000_000,
              dependencyCount >= 0, dependencyCount <= 1_000_000,
              assetCount >= 8, assetCount <= 250_000 else { return nil }

        let searchStart = contentOffset + 24
        let searchEnd = min(data.count, searchStart + 2 * 1024 * 1024)
        guard let tableOffset = findDeclaredAssetTable(
            data,
            expectedCount: assetCount,
            start: searchStart,
            end: searchEnd
        ) else { return nil }

        return buildIndex(data, offset: tableOffset, count: assetCount)
    }

    private static func findDeclaredAssetTable(
        _ data: Data,
        expectedCount: Int,
        start: Int,
        end: Int
    ) -> Int? {
        guard expectedCount >= 8, start < end else { return nil }
        let sampleCount = min(expectedCount, 16)
        var offset = align4(start)
        let upper = min(end, data.count - sampleCount * 8)

        while offset <= upper {
            var valid = true
            for index in 0..<sampleCount {
                let type = Int(be32(data, offset + index * 8))
                if type < 0 || type >= assetTypeNames.count {
                    valid = false
                    break
                }
            }

            if valid {
                let bytesNeeded = expectedCount.multipliedReportingOverflow(by: 8)
                if !bytesNeeded.overflow,
                   offset <= data.count,
                   bytesNeeded.partialValue <= data.count - offset {
                    var fullValid = true
                    for index in 0..<expectedCount {
                        let type = Int(be32(data, offset + index * 8))
                        if type < 0 || type >= assetTypeNames.count {
                            fullValid = false
                            break
                        }
                    }
                    if fullValid { return offset }
                }
            }
            offset += 4
        }
        return nil
    }

    private static func scanBestAssetTable(_ data: Data) -> TopLevelIndex? {
        let scanEnd = min(data.count, 4 * 1024 * 1024)
        guard scanEnd >= 8 * 24 else { return nil }

        var bestOffset: Int?
        var bestCount = 0
        var offset = 0

        while offset + 8 * 24 <= scanEnd {
            let firstType = Int(be32(data, offset))
            if firstType >= 0 && firstType < assetTypeNames.count {
                var count = 0
                var cursor = offset
                while cursor + 8 <= scanEnd, count < 250_000 {
                    let type = Int(be32(data, cursor))
                    guard type >= 0 && type < assetTypeNames.count else { break }
                    count += 1
                    cursor += 8
                }

                if count >= 24 && count > bestCount {
                    bestCount = count
                    bestOffset = offset
                }

                if count > 0 {
                    offset += max(4, count * 8)
                    continue
                }
            }
            offset += 4
        }

        guard let bestOffset, bestCount >= 24 else { return nil }
        return buildIndex(data, offset: bestOffset, count: bestCount)
    }

    private static func buildIndex(_ data: Data, offset: Int, count: Int) -> TopLevelIndex? {
        guard count > 0, offset >= 0, offset + count * 8 <= data.count else { return nil }
        var counts: [String: Int] = [:]
        counts.reserveCapacity(24)

        for index in 0..<count {
            let rawType = Int(be32(data, offset + index * 8))
            guard rawType >= 0, rawType < assetTypeNames.count else { return nil }
            counts[assetTypeNames[rawType], default: 0] += 1
        }

        return TopLevelIndex(assetCount: count, assetTableOffset: offset, typeCounts: counts)
    }

    private static func align4(_ value: Int) -> Int {
        (value + 3) & ~3
    }

    private static func be32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, data.count >= offset + 4 else { return UInt32.max }
        return (UInt32(data[offset]) << 24) |
            (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) |
            UInt32(data[offset + 3])
    }

    private static func samplePriority(_ value: String) -> Int {
        if value.contains("transit") || value.contains("tranzit") || value.contains("zm_") { return 0 }
        if value.contains("xmodel") || value.contains("model_") || value.contains("zombie") || value.hasPrefix("p6_") { return 1 }
        if value.contains("weapon_") { return 2 }
        if value.contains("material") || value.hasPrefix("mtl_") || value.contains("/mtl_") || value.contains(".iwi") { return 3 }
        if value.contains("sound") || value.contains(".wav") || value.contains("vox_") { return 4 }
        return 5
    }
}

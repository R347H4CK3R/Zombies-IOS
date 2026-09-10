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
                lower.contains("weapon_")
            let isMaterial = lower.contains("material") ||
                lower.hasPrefix("mtl_") ||
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

    // The decompressed T6 stream starts with a 0x28-byte XFile header:
    // zoneSize, externalZoneSize and eight XFile block sizes. XAssetList follows it.
    // XAssetList on 32-bit PS3/Xenon is six big-endian uint32 fields:
    // scriptStringCount/pointer, dependencyCount/pointer, assetCount/pointer.
    private static func parseTopLevelIndex(_ data: Data) -> TopLevelIndex? {
        let contentOffset = 0x28
        guard data.count >= contentOffset + 24 else { return nil }

        let scriptCount = Int(be32(data, contentOffset))
        let scriptPointer = be32(data, contentOffset + 4)
        let dependencyCount = Int(be32(data, contentOffset + 8))
        let dependencyPointer = be32(data, contentOffset + 12)
        let assetCount = Int(be32(data, contentOffset + 16))
        let assetPointer = be32(data, contentOffset + 20)

        guard scriptCount >= 0, scriptCount <= 1_000_000,
              dependencyCount >= 0, dependencyCount <= 1_000_000,
              assetCount > 0, assetCount <= 1_000_000 else { return nil }

        var cursor = contentOffset + 24

        if scriptPointer == 0xFFFF_FFFF {
            guard let advanced = advanceFollowingXStrings(data, offset: cursor, count: scriptCount) else { return nil }
            cursor = advanced
        } else if scriptPointer != 0 && scriptCount > 0 {
            return nil
        }

        if dependencyPointer == 0xFFFF_FFFF {
            guard let advanced = advanceFollowingXStrings(data, offset: cursor, count: dependencyCount) else { return nil }
            cursor = advanced
        } else if dependencyPointer != 0 && dependencyCount > 0 {
            return nil
        }

        guard assetPointer == 0xFFFF_FFFF else { return nil }
        let tableBytes = assetCount.multipliedReportingOverflow(by: 8)
        guard !tableBytes.overflow, cursor <= data.count,
              tableBytes.partialValue <= data.count - cursor else { return nil }

        var counts: [String: Int] = [:]
        counts.reserveCapacity(16)

        for index in 0..<assetCount {
            let entry = cursor + index * 8
            let rawType = Int(be32(data, entry))
            guard rawType >= 0, rawType < 4096 else { return nil }
            let name = rawType < assetTypeNames.count ? assetTypeNames[rawType] : "TYPE_\(rawType)"
            counts[name, default: 0] += 1
        }

        return TopLevelIndex(assetCount: assetCount, assetTableOffset: cursor, typeCounts: counts)
    }

    private static func advanceFollowingXStrings(_ data: Data, offset: Int, count: Int) -> Int? {
        guard count >= 0 else { return nil }
        let tableBytes = count.multipliedReportingOverflow(by: 4)
        guard !tableBytes.overflow, offset <= data.count,
              tableBytes.partialValue <= data.count - offset else { return nil }

        let tableEnd = offset + tableBytes.partialValue
        var cursor = tableEnd

        for index in 0..<count {
            let pointer = be32(data, offset + index * 4)
            if pointer == 0xFFFF_FFFF {
                guard cursor < data.count,
                      let nul = data[cursor...].firstIndex(of: 0) else { return nil }
                cursor = nul + 1
            }
        }
        return cursor
    }

    private static func be32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, data.count >= offset + 4 else { return 0 }
        return (UInt32(data[offset]) << 24) |
            (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) |
            UInt32(data[offset + 3])
    }

    private static func samplePriority(_ value: String) -> Int {
        if value.contains("transit") || value.contains("tranzit") || value.contains("zm_") { return 0 }
        if value.contains("xmodel") || value.contains("model_") || value.contains("zombie") { return 1 }
        if value.contains("weapon_") { return 2 }
        if value.contains("material") || value.hasPrefix("mtl_") || value.contains(".iwi") { return 3 }
        if value.contains("sound") || value.contains(".wav") || value.contains("vox_") { return 4 }
        return 5
    }
}

import Foundation

struct T6ZoneAssetProbeReport: Sendable {
    let printableStringCount: Int
    let candidateAssetCount: Int
    let modelLikeCount: Int
    let materialLikeCount: Int
    let soundLikeCount: Int
    let mapLikeCount: Int
    let sampleNames: [String]

    var summary: String {
        "ASSETS \(candidateAssetCount)  MODELS \(modelLikeCount)"
    }
}

enum T6ZoneAssetProbe {
    static func analyze(_ data: Data, maxSamples: Int = 10) -> T6ZoneAssetProbeReport {
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
            sampleNames: Array(orderedSamples)
        )
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

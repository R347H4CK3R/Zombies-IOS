import Foundation

enum BO2EntityParser {
    struct Result {
        let entities: [BO2RuntimeEntity]
        let spawns: [BO2RuntimeSpawn]
    }

    private static let spawnClasses: Set<String> = [
        "mp_dm_spawn", "mp_tdm_spawn", "mp_dom_spawn",
        "mp_ctf_spawn_axis", "mp_ctf_spawn_allies",
        "mp_dem_spawn_attacker", "mp_dem_spawn_defender"
    ]

    static func extractEntityLump(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let bytes = [UInt8](data)
        let marker = Array("\"classname\" \"worldspawn\"".utf8)
        guard let markerStart = find(bytes, needle: marker) else { return nil }

        var start = markerStart
        while start > 0 {
            start -= 1
            if bytes[start] == 0x7B { break }
            if markerStart - start > 16_384 { return nil }
        }
        guard bytes[start] == 0x7B else { return nil }

        var cursor = start
        var depth = 0
        var inQuote = false
        var escaped = false
        var lastBalancedEnd: Int?
        var entityCount = 0
        let maxBytes = min(bytes.count, start + 2 * 1024 * 1024)

        while cursor < maxBytes {
            let b = bytes[cursor]
            if inQuote {
                if escaped { escaped = false }
                else if b == 0x5C { escaped = true }
                else if b == 0x22 { inQuote = false }
            } else {
                if b == 0x22 { inQuote = true }
                else if b == 0x7B { depth += 1 }
                else if b == 0x7D {
                    depth -= 1
                    if depth == 0 {
                        entityCount += 1
                        lastBalancedEnd = cursor + 1
                    }
                    if depth < 0 { break }
                } else if depth == 0, lastBalancedEnd != nil, b == 0 {
                    break
                }
            }
            cursor += 1
        }

        guard entityCount > 0, let end = lastBalancedEnd, end > start else { return nil }
        return String(bytes: bytes[start..<end], encoding: .utf8)
    }

    static func parse(_ text: String) -> Result {
        var entities: [BO2RuntimeEntity] = []
        var spawns: [BO2RuntimeSpawn] = []
        var cursor = text.startIndex

        while let open = text[cursor...].firstIndex(of: "{") {
            guard let close = matchingClose(in: text, from: open) else { break }
            let body = String(text[text.index(after: open)..<close])
            let properties = parsePairs(body)
            let classname = properties["classname"] ?? "unknown"
            let entity = BO2RuntimeEntity(classname: classname, properties: properties)
            entities.append(entity)

            if spawnClasses.contains(classname), let originText = properties["origin"], let origin = parseVector(originText) {
                let runtimeOrigin = convertOrigin(origin)
                let yaw: Float
                if let single = properties["angle"], let value = Float(single) {
                    yaw = value
                } else if let angles = properties["angles"], let values = parseVector(angles) {
                    yaw = values.y
                } else {
                    yaw = 0
                }
                spawns.append(BO2RuntimeSpawn(origin: runtimeOrigin, yaw: yaw, classname: classname))
            }
            cursor = text.index(after: close)
        }

        return Result(entities: entities, spawns: spawns)
    }

    static func convertOrigin(_ bo2: SIMD3<Float>) -> BO2RuntimeVertex {
        // T6 is Z-up. The iOS runtime is Y-up. Preserve BO2 scale so world,
        // collision, entities and static-model placements remain aligned.
        BO2RuntimeVertex(x: bo2.x, y: bo2.z, z: -bo2.y)
    }

    private static func parsePairs(_ body: String) -> [String: String] {
        let pattern = #"\"((?:\\.|[^\"\\])*)\"\s+\"((?:\\.|[^\"\\])*)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let ns = body as NSString
        let range = NSRange(location: 0, length: ns.length)
        var result: [String: String] = [:]
        for match in regex.matches(in: body, range: range) where match.numberOfRanges == 3 {
            result[ns.substring(with: match.range(at: 1))] = ns.substring(with: match.range(at: 2))
        }
        return result
    }

    private static func parseVector(_ text: String) -> SIMD3<Float>? {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 3, let x = Float(parts[0]), let y = Float(parts[1]), let z = Float(parts[2]) else { return nil }
        return SIMD3<Float>(x, y, z)
    }

    private static func matchingClose(in text: String, from open: String.Index) -> String.Index? {
        var index = open
        var depth = 0
        var quoted = false
        var escaped = false
        while index < text.endIndex {
            let c = text[index]
            if quoted {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { quoted = false }
            } else {
                if c == "\"" { quoted = true }
                else if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { return index }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func find(_ haystack: [UInt8], needle: [UInt8]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for i in 0...(haystack.count - needle.count) where haystack[i..<(i + needle.count)].elementsEqual(needle) {
            return i
        }
        return nil
    }
}

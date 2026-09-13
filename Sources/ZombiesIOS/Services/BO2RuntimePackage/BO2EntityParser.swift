import Foundation
import simd

enum BO2EntityParser {
    static func parse(_ text: String) -> [BO2RuntimeEntity] {
        var result: [BO2RuntimeEntity] = []
        var properties: [String: String] = [:]
        var tokens: [String] = []
        var current = ""
        var inQuote = false
        var escaping = false

        func flushPairTokens() {
            while tokens.count >= 2 {
                let key = tokens.removeFirst()
                let value = tokens.removeFirst()
                properties[key] = value
            }
        }

        for scalar in text.unicodeScalars {
            let c = Character(scalar)
            if inQuote {
                if escaping {
                    current.append(c)
                    escaping = false
                } else if c == "\\" {
                    escaping = true
                } else if c == "\"" {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                    inQuote = false
                } else {
                    current.append(c)
                }
                continue
            }

            if c == "\"" {
                inQuote = true
            } else if c == "{" {
                properties.removeAll(keepingCapacity: true)
                tokens.removeAll(keepingCapacity: true)
            } else if c == "}" {
                flushPairTokens()
                if !properties.isEmpty { result.append(BO2RuntimeEntity(properties: properties)) }
                properties.removeAll(keepingCapacity: true)
                tokens.removeAll(keepingCapacity: true)
            } else if c == "\n" || c == "\r" {
                flushPairTokens()
            }
        }
        return result
    }

    static func spawns(from entities: [BO2RuntimeEntity]) -> [BO2RuntimeSpawn] {
        let spawnClasses: Set<String> = [
            "mp_dm_spawn", "mp_tdm_spawn", "mp_ctf_spawn", "mp_dom_spawn",
            "mp_spawn", "info_player_start", "info_player_deathmatch"
        ]
        return entities.compactMap { entity in
            let classname = entity.classname.lowercased()
            guard spawnClasses.contains(classname),
                  let rawOrigin = entity.properties["origin"],
                  let origin = parseVector(rawOrigin) else { return nil }
            let converted = BO2RuntimePackage.bo2ToRuntime(origin)
            let yaw = Float(entity.properties["angle"] ?? entity.properties["angles"]?.split(separator: " ").dropFirst().first.map(String.init) ?? "0") ?? 0
            return BO2RuntimeSpawn(
                classname: classname,
                origin: BO2RuntimeVertex(converted),
                yawDegrees: -yaw
            )
        }
    }

    private static func parseVector(_ value: String) -> SIMD3<Float>? {
        let parts = value.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 3,
              let x = Float(parts[0]),
              let y = Float(parts[1]),
              let z = Float(parts[2]) else { return nil }
        return SIMD3<Float>(x, y, z)
    }
}

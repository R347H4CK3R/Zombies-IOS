import Foundation

enum T6AssetTableDecoder {
    static func decode(_ entries: [T6ZoneAssetEntry]) -> [T6AssetRecord] {
        entries.enumerated().map { index, entry in
            T6AssetRecord(
                index: index,
                type: T6AssetType(rawValue: entry.typeId),
                pointer: entry.pointer
            )
        }
    }

    static func typeCounts(_ entries: [T6ZoneAssetEntry]) -> [String: Int] {
        var result: [String: Int] = [:]
        for record in decode(entries) {
            result[record.type.name, default: 0] += 1
        }
        return result
    }
}

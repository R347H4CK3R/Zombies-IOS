import Foundation

enum T6AssetType: Int, Sendable {
    case material = 6
    case gfxImage = 8
    case gfxWorld = 17
}

struct T6AssetRecord: Sendable, Equatable {
    let type: T6AssetType
    let tableOffset: Int
    let rawPointer: UInt32
}

struct T6ResolvedAssetIndex: Sendable {
    let records: [T6AssetRecord]
    let tableOffset: Int
    let tableEntryCount: Int

    func first(_ type: T6AssetType) -> T6AssetRecord? { records.first { $0.type == type } }
    func all(_ type: T6AssetType) -> [T6AssetRecord] { records.filter { $0.type == type } }
}

enum T6AssetResolver {
    private static let maxTypeID = 59

    static func resolveIndex(in payload: Data) -> T6ResolvedAssetIndex? {
        guard payload.count >= 64 else { return nil }

        if let declared = findDeclaredTable(in: payload) {
            return makeIndex(payload: payload, tableOffset: declared.offset, count: declared.count)
        }
        guard let scanned = scanBestTable(in: payload) else { return nil }
        return makeIndex(payload: payload, tableOffset: scanned.offset, count: scanned.count)
    }

    /// Resolves a serialized pointer only when it is an actual payload-relative offset.
    /// T6 sentinel pointers (0xffffffff/0xfffffffe) deliberately remain unresolved;
    /// the caller can use deterministic stream-order parsing or the diagnostic fallback.
    static func payloadOffset(for record: T6AssetRecord, payloadCount: Int) -> Int? {
        let p = Int(record.rawPointer)
        guard record.rawPointer != 0xffffffff,
              record.rawPointer != 0xfffffffe,
              p >= 0,
              p < payloadCount else { return nil }
        return p
    }

    private static func findDeclaredTable(in data: Data) -> (offset: Int, count: Int)? {
        var contentOffsets = [0x28, 0x20, 0x24, 0x2c, 0x30, 0]
        for value in stride(from: 4, through: min(0x400, max(4, data.count - 24)), by: 4) where !contentOffsets.contains(value) {
            contentOffsets.append(value)
        }
        for contentOffset in contentOffsets {
            guard contentOffset + 24 <= data.count else { continue }
            let count = Int(be32(data, contentOffset + 16))
            guard count >= 8, count <= 250_000 else { continue }
            let start = contentOffset + 24
            let end = min(data.count, start + 2 * 1024 * 1024)
            let sample = min(count, 16)
            var offset = (start + 3) & ~3
            while offset + sample * 8 <= end {
                var ok = true
                for i in 0..<sample {
                    let type = Int(be32(data, offset + i * 8))
                    if type < 0 || type > maxTypeID { ok = false; break }
                }
                if ok, offset + count * 8 <= data.count {
                    var allOK = true
                    for i in 0..<count {
                        let type = Int(be32(data, offset + i * 8))
                        if type < 0 || type > maxTypeID { allOK = false; break }
                    }
                    if allOK { return (offset, count) }
                }
                offset += 4
            }
        }
        return nil
    }

    private static func scanBestTable(in data: Data) -> (offset: Int, count: Int)? {
        let end = min(data.count, 4 * 1024 * 1024)
        guard end >= 24 * 8 else { return nil }
        var best: (Int, Int)?
        var offset = 0
        while offset + 24 * 8 <= end {
            let first = Int(be32(data, offset))
            guard first >= 0, first <= maxTypeID else { offset += 4; continue }
            var count = 0
            var cursor = offset
            while cursor + 8 <= end, count < 250_000 {
                let type = Int(be32(data, cursor))
                guard type >= 0, type <= maxTypeID else { break }
                count += 1
                cursor += 8
            }
            if count >= 24, best == nil || count > best!.1 { best = (offset, count) }
            offset += max(4, count * 8)
        }
        return best.map { ($0.0, $0.1) }
    }

    private static func makeIndex(payload: Data, tableOffset: Int, count: Int) -> T6ResolvedAssetIndex? {
        guard tableOffset >= 0, count > 0, tableOffset + count * 8 <= payload.count else { return nil }
        var records: [T6AssetRecord] = []
        records.reserveCapacity(count / 4)
        for i in 0..<count {
            let entry = tableOffset + i * 8
            let rawType = Int(be32(payload, entry))
            guard rawType >= 0, rawType <= maxTypeID else { return nil }
            guard let type = T6AssetType(rawValue: rawType) else { continue }
            records.append(T6AssetRecord(type: type, tableOffset: entry, rawPointer: be32(payload, entry + 4)))
        }
        return T6ResolvedAssetIndex(records: records, tableOffset: tableOffset, tableEntryCount: count)
    }

    private static func be32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return .max }
        return (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
    }
}

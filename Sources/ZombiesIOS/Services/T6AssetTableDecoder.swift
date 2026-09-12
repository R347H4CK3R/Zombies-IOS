import Foundation

struct T6AssetTableDecoder {
    enum DecodeError: LocalizedError {
        case payloadTooSmall
        case assetTableNotFound
        case invalidAssetType(UInt32, Int)

        var errorDescription: String? {
            switch self {
            case .payloadTooSmall:
                return "The decoded T6 payload is too small to contain an asset table."
            case .assetTableNotFound:
                return "A deterministic T6 top-level asset table could not be located."
            case .invalidAssetType(let typeID, let index):
                return "T6 asset entry \(index) contains invalid type id \(typeID)."
            }
        }
    }

    private static let maximumKnownAssetTypeID: UInt32 = 59

    func decode(zoneName: String, payload: Data) throws -> T6DecodedZone {
        guard payload.count >= 24 else { throw DecodeError.payloadTooSmall }

        if let declared = findDeclaredTable(in: payload) {
            return try buildZone(zoneName: zoneName, payload: payload, tableOffset: declared.offset, count: declared.count)
        }

        if let scanned = scanBestTable(in: payload) {
            return try buildZone(zoneName: zoneName, payload: payload, tableOffset: scanned.offset, count: scanned.count)
        }

        throw DecodeError.assetTableNotFound
    }

    private func findDeclaredTable(in payload: Data) -> (offset: Int, count: Int)? {
        var headerOffsets = [0x28, 0x20, 0x24, 0x2C, 0x30, 0]
        let upperHeaderOffset = min(0x400, max(0, payload.count - 24))
        if upperHeaderOffset >= 4 {
            for offset in stride(from: 4, through: upperHeaderOffset, by: 4) where !headerOffsets.contains(offset) {
                headerOffsets.append(offset)
            }
        }

        for contentOffset in headerOffsets where contentOffset >= 0 && payload.count >= contentOffset + 24 {
            let scriptCount = Int(Self.be32(payload, contentOffset))
            let dependencyCount = Int(Self.be32(payload, contentOffset + 8))
            let assetCount = Int(Self.be32(payload, contentOffset + 16))

            guard scriptCount >= 0, scriptCount <= 1_000_000,
                  dependencyCount >= 0, dependencyCount <= 1_000_000,
                  assetCount > 0, assetCount <= 250_000 else {
                continue
            }

            let searchStart = contentOffset + 24
            let searchEnd = min(payload.count, searchStart + 2 * 1024 * 1024)
            if let offset = findTable(payload, expectedCount: assetCount, start: searchStart, end: searchEnd) {
                return (offset, assetCount)
            }
        }

        return nil
    }

    private func findTable(_ payload: Data, expectedCount: Int, start: Int, end: Int) -> Int? {
        guard expectedCount > 0, start < end else { return nil }
        let sampleCount = min(expectedCount, 16)
        var offset = Self.align4(start)
        let bytesNeeded = expectedCount * 8
        let upper = min(end, payload.count - sampleCount * 8)

        while offset <= upper {
            var sampleValid = true
            for index in 0..<sampleCount {
                let typeID = Self.be32(payload, offset + index * 8)
                if typeID > Self.maximumKnownAssetTypeID {
                    sampleValid = false
                    break
                }
            }

            if sampleValid, offset <= payload.count, bytesNeeded <= payload.count - offset {
                var allValid = true
                for index in 0..<expectedCount {
                    let typeID = Self.be32(payload, offset + index * 8)
                    if typeID > Self.maximumKnownAssetTypeID {
                        allValid = false
                        break
                    }
                }
                if allValid { return offset }
            }
            offset += 4
        }
        return nil
    }

    private func scanBestTable(in payload: Data) -> (offset: Int, count: Int)? {
        let scanEnd = min(payload.count, 4 * 1024 * 1024)
        guard scanEnd >= 32 else { return nil }

        var best: (offset: Int, count: Int)?
        var offset = 0
        while offset + 8 <= scanEnd {
            let firstType = Self.be32(payload, offset)
            if firstType <= Self.maximumKnownAssetTypeID {
                var count = 0
                var cursor = offset
                while cursor + 8 <= scanEnd, count < 250_000 {
                    let typeID = Self.be32(payload, cursor)
                    guard typeID <= Self.maximumKnownAssetTypeID else { break }
                    count += 1
                    cursor += 8
                }

                if count >= 4, count > (best?.count ?? 0) {
                    best = (offset, count)
                }
                if count > 0 {
                    offset += max(4, count * 8)
                    continue
                }
            }
            offset += 4
        }
        return best
    }

    private func buildZone(zoneName: String, payload: Data, tableOffset: Int, count: Int) throws -> T6DecodedZone {
        var records: [T6AssetRecord] = []
        records.reserveCapacity(count)

        for index in 0..<count {
            let entryOffset = tableOffset + index * 8
            let typeID = Self.be32(payload, entryOffset)
            guard typeID <= Self.maximumKnownAssetTypeID else {
                throw DecodeError.invalidAssetType(typeID, index)
            }
            let rawPointer = Self.be32(payload, entryOffset + 4)
            let id = T6AssetID(zoneName: zoneName, typeID: typeID, assetIndex: index, tableOffset: tableOffset)
            records.append(
                T6AssetRecord(
                    id: id,
                    kind: T6AssetKind.from(typeID: typeID),
                    rawPointer: rawPointer,
                    tableEntryOffset: entryOffset
                )
            )
        }

        return T6DecodedZone(zoneName: zoneName, payload: payload, assetTableOffset: tableOffset, records: records)
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
}

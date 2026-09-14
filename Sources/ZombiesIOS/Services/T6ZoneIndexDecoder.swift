import Foundation

struct T6ZoneAssetEntry: Equatable, Sendable {
    let typeId: UInt32
    let pointer: T6ZonePointer
}

struct T6ZoneIndex: Sendable {
    let xfileSize: UInt32
    let externalSize: UInt32
    let blockSizes: [UInt32]
    let scriptStrings: [String]
    let dependencies: [String]
    let assets: [T6ZoneAssetEntry]
    let assetTableSerializedOffset: Int?
    let assetPayloadSerializedOffset: Int
}

enum T6ZoneIndexDecoder {
    enum DecodeError: LocalizedError, Equatable {
        case truncatedHeader
        case invalidCount(String, UInt32)
        case unexpectedPointer(String, T6ZonePointer)
        case invalidAssetType(UInt32)

        var errorDescription: String? {
            switch self {
            case .truncatedHeader:
                return "T6 decoded zone is shorter than the XFile/XAssetList headers."
            case .invalidCount(let name, let count):
                return "T6 \(name) count \(count) is outside the supported range."
            case .unexpectedPointer(let name, let pointer):
                return "T6 \(name) uses unsupported pointer \(pointer)."
            case .invalidAssetType(let type):
                return "T6 XAsset type \(type) is outside the retail asset table."
            }
        }
    }

    private static let xfileHeaderSize = 0x28
    private static let xassetListSize = 24
    private static let virtualBlock = 5
    private static let maximumListCount: UInt32 = 1_000_000
    private static let maximumAssetType: UInt32 = 62

    static func decode(_ data: Data) throws -> T6ZoneIndex {
        guard data.count >= xfileHeaderSize + xassetListSize else { throw DecodeError.truncatedHeader }

        let xfileSize = be32(data, 0)
        let externalSize = be32(data, 4)
        let blockSizes = (0..<8).map { be32(data, 8 + $0 * 4) }
        let listOffset = xfileHeaderSize

        let scriptCount = be32(data, listOffset)
        let scriptPointer = T6ZonePointer.decode(be32(data, listOffset + 4))
        let dependencyCount = be32(data, listOffset + 8)
        let dependencyPointer = T6ZonePointer.decode(be32(data, listOffset + 12))
        let assetCount = be32(data, listOffset + 16)
        let assetPointer = T6ZonePointer.decode(be32(data, listOffset + 20))

        try validateCount("script string", scriptCount)
        try validateCount("dependency", dependencyCount)
        try validateCount("asset", assetCount)

        var cursor = try T6ZoneStreamCursor(
            serializedData: data,
            blockSizes: blockSizes,
            serializedOffset: xfileHeaderSize + xassetListSize
        )
        try cursor.pushBlock(virtualBlock)
        defer { try? cursor.popBlock() }

        let scriptStrings = try decodeStrings(
            count: Int(scriptCount),
            pointer: scriptPointer,
            name: "script string list",
            cursor: &cursor
        )
        let dependencies = try decodeStrings(
            count: Int(dependencyCount),
            pointer: dependencyPointer,
            name: "dependency list",
            cursor: &cursor
        )

        let tableStart = cursor.currentSerializedOffset
        let assets = try decodeAssets(
            count: Int(assetCount),
            pointer: assetPointer,
            cursor: &cursor
        )
        let hasInlineAssetTable = assetCount > 0 && assetPointer == .following

        return T6ZoneIndex(
            xfileSize: xfileSize,
            externalSize: externalSize,
            blockSizes: blockSizes,
            scriptStrings: scriptStrings,
            dependencies: dependencies,
            assets: assets,
            assetTableSerializedOffset: hasInlineAssetTable ? tableStart : nil,
            assetPayloadSerializedOffset: cursor.currentSerializedOffset
        )
    }

    private static func decodeStrings(
        count: Int,
        pointer: T6ZonePointer,
        name: String,
        cursor: inout T6ZoneStreamCursor
    ) throws -> [String] {
        if count == 0 { return [] }
        guard pointer == .following else { throw DecodeError.unexpectedPointer(name, pointer) }

        let pointersData = try cursor.resolveFollowing(alignment: 4, length: count * 4)
        var result: [String] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let itemPointer = T6ZonePointer.decode(be32(pointersData, index * 4))
            switch itemPointer {
            case .null:
                result.append("")
            case .following:
                result.append(try cursor.resolveNullTerminatedString())
            default:
                // Offset strings refer to existing normal-block storage. Keep the
                // index deterministic without guessing a serialized location.
                result.append("")
            }
        }
        return result
    }

    private static func decodeAssets(
        count: Int,
        pointer: T6ZonePointer,
        cursor: inout T6ZoneStreamCursor
    ) throws -> [T6ZoneAssetEntry] {
        if count == 0 { return [] }
        guard pointer == .following else { throw DecodeError.unexpectedPointer("asset list", pointer) }
        let table = try cursor.resolveFollowing(alignment: 4, length: count * 8)
        var entries: [T6ZoneAssetEntry] = []
        entries.reserveCapacity(count)
        for index in 0..<count {
            let offset = index * 8
            let typeId = be32(table, offset)
            guard typeId <= maximumAssetType else { throw DecodeError.invalidAssetType(typeId) }
            entries.append(T6ZoneAssetEntry(
                typeId: typeId,
                pointer: T6ZonePointer.decode(be32(table, offset + 4))
            ))
        }
        return entries
    }

    private static func validateCount(_ name: String, _ value: UInt32) throws {
        guard value <= maximumListCount else { throw DecodeError.invalidCount(name, value) }
    }

    private static func be32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, data.count >= offset + 4 else { return UInt32.max }
        return (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }
}

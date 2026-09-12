import Foundation

struct T6AssetID: Hashable, Sendable, Codable {
    let zoneName: String
    let typeID: UInt32
    let assetIndex: Int
    let tableOffset: Int
}

enum T6AssetKind: Hashable, Sendable {
    case gfxWorld
    case material
    case image
    case xModel
    case weapon
    case unknown(typeID: UInt32)

    static func from(typeID: UInt32) -> T6AssetKind {
        switch typeID {
        case 17: return .gfxWorld
        case 6: return .material
        case 8: return .image
        case 5: return .xModel
        case 25, 26, 27, 28, 29, 30, 31: return .weapon
        default: return .unknown(typeID: typeID)
        }
    }
}

struct T6AssetRecord: Hashable, Sendable {
    let id: T6AssetID
    let kind: T6AssetKind
    let rawPointer: UInt32
    let tableEntryOffset: Int
}

struct T6GfxWorldAsset: Hashable, Sendable {
    let record: T6AssetRecord
}

struct T6MaterialAsset: Hashable, Sendable {
    let record: T6AssetRecord
}

struct T6ImageAsset: Hashable, Sendable {
    let record: T6AssetRecord
}

struct T6XModelAsset: Hashable, Sendable {
    let record: T6AssetRecord
}

struct T6WeaponAsset: Hashable, Sendable {
    let record: T6AssetRecord
}

struct T6DecodedZone: Sendable {
    let zoneName: String
    let payload: Data
    let assetTableOffset: Int
    let records: [T6AssetRecord]

    var gfxWorlds: [T6GfxWorldAsset] {
        records.compactMap { record in
            if case .gfxWorld = record.kind { return T6GfxWorldAsset(record: record) }
            return nil
        }
    }

    var materials: [T6MaterialAsset] {
        records.compactMap { record in
            if case .material = record.kind { return T6MaterialAsset(record: record) }
            return nil
        }
    }

    var images: [T6ImageAsset] {
        records.compactMap { record in
            if case .image = record.kind { return T6ImageAsset(record: record) }
            return nil
        }
    }

    var xModels: [T6XModelAsset] {
        records.compactMap { record in
            if case .xModel = record.kind { return T6XModelAsset(record: record) }
            return nil
        }
    }

    var weapons: [T6WeaponAsset] {
        records.compactMap { record in
            if case .weapon = record.kind { return T6WeaponAsset(record: record) }
            return nil
        }
    }
}

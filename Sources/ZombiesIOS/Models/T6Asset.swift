import Foundation

struct T6AssetType: Codable, Hashable, Sendable {
    let rawValue: UInt32

    var knownName: String? {
        guard Int(rawValue) < Self.names.count else { return nil }
        return Self.names[Int(rawValue)]
    }

    var name: String {
        knownName ?? "Unknown(\(rawValue))"
    }

    private static let names: [String] = [
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
}

struct T6AssetRecord: Equatable, Sendable {
    let index: Int
    let type: T6AssetType
    let pointer: T6ZonePointer
}

import Foundation

struct RuntimeAssetLoader {
    let gameData: LoadedGameData

    func asset(id: String, kind: String? = nil) throws -> GameDataAsset {
        guard let asset = gameData.assetsByID[id] else {
            throw RuntimeAssetLoaderError.missingAsset(id)
        }
        if let kind, asset.kind != kind {
            throw RuntimeAssetLoaderError.kindMismatch(id: id, expected: kind, actual: asset.kind)
        }
        return asset
    }

    func payloadURL(asset: GameDataAsset, named name: String) throws -> URL {
        guard let payload = asset.payloads.first(where: { $0.name == name }) else {
            throw RuntimeAssetLoaderError.missingPayload(assetID: asset.id, name: name)
        }
        let url = gameData.root.appendingPathComponent(payload.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RuntimeAssetLoaderError.missingPayload(assetID: asset.id, name: name)
        }
        return url
    }

    func loadJSON<T: Decodable>(_ type: T.Type, assetID: String, kind: String, payload: String) throws -> T {
        let record = try asset(id: assetID, kind: kind)
        let url = try payloadURL(asset: record, named: payload)
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    func loadWeapon(id: String) throws -> WeaponDefinition {
        try loadJSON(WeaponDefinition.self, assetID: id, kind: "weapon", payload: "weapon.json")
    }

    func firstWeapon() throws -> WeaponDefinition {
        guard let asset = gameData.manifest.assets.first(where: { $0.kind == "weapon" }) else {
            throw RuntimeAssetLoaderError.missingAssetKind("weapon")
        }
        return try loadWeapon(id: asset.id)
    }

    func firstWorld() throws -> WorldRuntimeAsset {
        guard let asset = gameData.manifest.assets.first(where: { $0.kind == "world" }) else {
            throw RuntimeAssetLoaderError.missingAssetKind("world")
        }
        return try WorldRuntimeAsset.load(gameData: gameData, asset: asset)
    }
}

enum RuntimeAssetLoaderError: LocalizedError {
    case missingAsset(String)
    case missingAssetKind(String)
    case kindMismatch(id: String, expected: String, actual: String)
    case missingPayload(assetID: String, name: String)

    var errorDescription: String? {
        switch self {
        case .missingAsset(let id): return "Missing runtime asset: \(id)"
        case .missingAssetKind(let kind): return "Missing runtime asset kind: \(kind)"
        case .kindMismatch(let id, let expected, let actual):
            return "Runtime asset \(id) is \(actual), expected \(expected)."
        case .missingPayload(let id, let name): return "Runtime asset \(id) is missing payload \(name)."
        }
    }
}

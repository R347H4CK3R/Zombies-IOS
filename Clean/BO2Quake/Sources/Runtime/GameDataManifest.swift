import Foundation

struct GameDataManifest: Codable, Equatable {
    let formatVersion: Int
    let assets: [GameDataAsset]
    let completion: [String: GameDataCompletion]
    let failures: [String]
    let complete: Bool
}

struct GameDataAsset: Codable, Equatable, Identifiable {
    let id: String
    let kind: String
    let version: Int
    let sourceHash: String
    let dependencies: [String]
    let payloads: [GameDataPayload]
    let validation: String
}

struct GameDataPayload: Codable, Equatable {
    let name: String
    let path: String
    let size: Int
    let sha256: String
}

struct GameDataCompletion: Codable, Equatable {
    let required: Bool
    let assetCount: Int
    let complete: Bool
}

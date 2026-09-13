import Foundation
import CryptoKit

enum GameDataLoaderError: LocalizedError {
    case missingManifest
    case unsupportedVersion(Int)
    case incomplete([String])
    case missingPayload(String)
    case payloadSizeMismatch(String)
    case payloadHashMismatch(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest: return "GameData manifest is missing."
        case .unsupportedVersion(let version): return "Unsupported GameData format version \(version)."
        case .incomplete(let failures): return "GameData is incomplete: \(failures.joined(separator: "; "))"
        case .missingPayload(let path): return "Missing GameData payload: \(path)"
        case .payloadSizeMismatch(let path): return "GameData payload size mismatch: \(path)"
        case .payloadHashMismatch(let path): return "GameData payload hash mismatch: \(path)"
        }
    }
}

struct LoadedGameData {
    let root: URL
    let manifest: GameDataManifest
    let assetsByID: [String: GameDataAsset]
}

struct GameDataLoader {
    static let supportedFormatVersion = 1

    func load(root: URL) throws -> LoadedGameData {
        let manifestURL = root.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw GameDataLoaderError.missingManifest
        }
        let manifest = try JSONDecoder().decode(GameDataManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.formatVersion == Self.supportedFormatVersion else {
            throw GameDataLoaderError.unsupportedVersion(manifest.formatVersion)
        }
        guard manifest.complete, manifest.failures.isEmpty else {
            throw GameDataLoaderError.incomplete(manifest.failures)
        }

        let assetsByID = Dictionary(uniqueKeysWithValues: manifest.assets.map { ($0.id, $0) })
        for asset in manifest.assets {
            for dependency in asset.dependencies where assetsByID[dependency] == nil {
                throw GameDataLoaderError.incomplete(["\(asset.id): missing dependency \(dependency)"])
            }
            for payload in asset.payloads {
                let url = root.appendingPathComponent(payload.path)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw GameDataLoaderError.missingPayload(payload.path)
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard data.count == payload.size else {
                    throw GameDataLoaderError.payloadSizeMismatch(payload.path)
                }
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard digest == payload.sha256 else {
                    throw GameDataLoaderError.payloadHashMismatch(payload.path)
                }
            }
        }
        return LoadedGameData(root: root, manifest: manifest, assetsByID: assetsByID)
    }

    func loadBundled() throws -> LoadedGameData {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("GameData", isDirectory: true) else {
            throw GameDataLoaderError.missingManifest
        }
        return try load(root: root)
    }
}

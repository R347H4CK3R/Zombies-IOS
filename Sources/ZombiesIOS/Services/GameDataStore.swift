import Foundation

struct GameDataStore: Sendable {
    enum StoreError: LocalizedError {
        case incompatibleManifestSchema(Int)
        case incompatibleConverterVersion(String)
        case invalidOutputPath

        var errorDescription: String? {
            switch self {
            case .incompatibleManifestSchema(let value):
                return "Unsupported GameData manifest schema \(value)."
            case .incompatibleConverterVersion(let value):
                return "GameData manifest was produced by converter \(value)."
            case .invalidOutputPath:
                return "GameData output path is invalid."
            }
        }
    }

    let rootURL: URL
    let converterVersion: String
    let manifestURL: URL
    let manifestPartURL: URL

    init(rootURL: URL, converterVersion: String) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.converterVersion = converterVersion
        self.manifestURL = self.rootURL.appendingPathComponent("manifest.json", isDirectory: false)
        self.manifestPartURL = self.rootURL.appendingPathComponent("manifest.json.part", isDirectory: false)
        try FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }

    func loadManifest() throws -> GameDataManifest {
        try recoverInterruptedManifestWriteIfNeeded()
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return GameDataManifest(converterVersion: converterVersion)
        }

        let data = try Data(contentsOf: manifestURL)
        let manifest = try Self.decoder.decode(GameDataManifest.self, from: data)
        guard manifest.schemaVersion == GameDataManifest.schemaVersion else {
            throw StoreError.incompatibleManifestSchema(manifest.schemaVersion)
        }
        guard manifest.converterVersion == converterVersion else {
            return GameDataManifest(converterVersion: converterVersion)
        }
        return manifest
    }

    func saveManifest(_ manifest: GameDataManifest) throws {
        let data = try Self.encoder.encode(manifest)
        try data.write(to: manifestPartURL, options: [.atomic])

        if FileManager.default.fileExists(atPath: manifestURL.path) {
            _ = try FileManager.default.replaceItemAt(
                manifestURL,
                withItemAt: manifestPartURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try FileManager.default.moveItem(at: manifestPartURL, to: manifestURL)
        }
    }

    func writeOutput(_ data: Data, relativePath: String) throws -> URL {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/"),
              !normalized.split(separator: "/").contains("..") else {
            throw StoreError.invalidOutputPath
        }

        let finalURL = rootURL.appendingPathComponent(normalized, isDirectory: false)
        let partURL = finalURL.appendingPathExtension("part")
        try FileManager.default.createDirectory(
            at: finalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: partURL, options: [.atomic])
        if FileManager.default.fileExists(atPath: finalURL.path) {
            _ = try FileManager.default.replaceItemAt(finalURL, withItemAt: partURL)
        } else {
            try FileManager.default.moveItem(at: partURL, to: finalURL)
        }
        return finalURL
    }

    func outputExists(relativePath: String, expectedSize: UInt64?) -> Bool {
        let url = rootURL.appendingPathComponent(relativePath)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = attributes[.size] as? NSNumber else { return false }
        guard let expectedSize else { return true }
        return number.uint64Value == expectedSize
    }

    private func recoverInterruptedManifestWriteIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: manifestPartURL.path) else { return }

        // A valid completed manifest always wins. A `.part` file is only promoted
        // when no completed manifest exists and the partial JSON is itself valid.
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            try? FileManager.default.removeItem(at: manifestPartURL)
            return
        }

        let data = try Data(contentsOf: manifestPartURL)
        let candidate = try Self.decoder.decode(GameDataManifest.self, from: data)
        guard candidate.schemaVersion == GameDataManifest.schemaVersion else {
            try? FileManager.default.removeItem(at: manifestPartURL)
            return
        }
        try FileManager.default.moveItem(at: manifestPartURL, to: manifestURL)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

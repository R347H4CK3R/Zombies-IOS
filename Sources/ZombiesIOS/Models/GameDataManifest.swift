import Foundation

enum GameDataStage: String, Codable, CaseIterable, Sendable {
    case container
    case zone
    case images
    case materials
    case models
    case animations
    case audio
    case video
    case weapons
    case entities
    case scripts
    case collision
    case ui
}

enum GameDataRecordStatus: String, Codable, Sendable {
    case inProgress
    case completed
    case failed
}

struct GameDataRecord: Codable, Hashable, Sendable {
    let sourcePath: String
    let sourceHash: String
    let stage: GameDataStage
    var status: GameDataRecordStatus
    var outputRelativePath: String?
    var outputSize: UInt64?
    var error: String?
    var updatedAt: Date
}

struct GameDataManifest: Codable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    var converterVersion: String
    var records: [String: GameDataRecord]
    var updatedAt: Date

    init(converterVersion: String) {
        self.schemaVersion = Self.schemaVersion
        self.converterVersion = converterVersion
        self.records = [:]
        self.updatedAt = Date()
    }

    mutating func markInProgress(
        sourcePath: String,
        sourceHash: String,
        stage: GameDataStage
    ) {
        let key = Self.key(sourcePath: sourcePath, stage: stage)
        records[key] = GameDataRecord(
            sourcePath: Self.normalize(sourcePath),
            sourceHash: sourceHash,
            stage: stage,
            status: .inProgress,
            outputRelativePath: nil,
            outputSize: nil,
            error: nil,
            updatedAt: Date()
        )
        updatedAt = Date()
    }

    mutating func markCompleted(
        sourcePath: String,
        sourceHash: String,
        stage: GameDataStage,
        outputRelativePath: String,
        outputSize: UInt64
    ) {
        let key = Self.key(sourcePath: sourcePath, stage: stage)
        records[key] = GameDataRecord(
            sourcePath: Self.normalize(sourcePath),
            sourceHash: sourceHash,
            stage: stage,
            status: .completed,
            outputRelativePath: outputRelativePath,
            outputSize: outputSize,
            error: nil,
            updatedAt: Date()
        )
        updatedAt = Date()
    }

    mutating func markFailed(
        sourcePath: String,
        sourceHash: String,
        stage: GameDataStage,
        error: String
    ) {
        let key = Self.key(sourcePath: sourcePath, stage: stage)
        records[key] = GameDataRecord(
            sourcePath: Self.normalize(sourcePath),
            sourceHash: sourceHash,
            stage: stage,
            status: .failed,
            outputRelativePath: nil,
            outputSize: nil,
            error: error,
            updatedAt: Date()
        )
        updatedAt = Date()
    }

    func needsConversion(
        sourcePath: String,
        sourceHash: String,
        stage: GameDataStage,
        converterVersion requestedVersion: String
    ) -> Bool {
        guard requestedVersion == converterVersion else { return true }
        guard let record = records[Self.key(sourcePath: sourcePath, stage: stage)] else { return true }
        guard record.status == .completed else { return true }
        guard record.sourceHash == sourceHash else { return true }
        guard let path = record.outputRelativePath, !path.isEmpty, record.outputSize != nil else { return true }
        return false
    }

    static func key(sourcePath: String, stage: GameDataStage) -> String {
        "\(normalize(sourcePath))|\(stage.rawValue)"
    }

    static func normalize(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}

import Foundation
import CryptoKit

struct BO2ConversionUnit: Hashable, Sendable {
    let sourcePath: String
    let mode: BO2ContentMode
    let stage: GameDataStage
}

struct BO2FullGameConversionReport: Sendable {
    let totalUnits: Int
    let completedUnits: Int
    let resumedUnits: Int
    let pendingUnits: [BO2ConversionUnit]
    let failures: [String]

    var isComplete: Bool {
        completedUnits + resumedUnits == totalUnits && pendingUnits.isEmpty && failures.isEmpty
    }
}

actor BO2FullGameConverter {
    enum ConversionError: LocalizedError {
        case sourceMissing(String)
        case invalidDecodedZone(String)
        case outputMissing(String)

        var errorDescription: String? {
            switch self {
            case .sourceMissing(let path): return "BO2 source file is unavailable: \(path)"
            case .invalidDecodedZone(let path): return "BO2 FastFile did not decode to a complete T6 zone: \(path)"
            case .outputMissing(let path): return "Completed GameData output is missing or changed: \(path)"
            }
        }
    }

    static let converterVersion = "bo2-full-gamedata-v1"
    private let decoder = T6PS3PayloadDecoder()

    static func plan(report: ScanReport) -> [BO2ConversionUnit] {
        report.files.compactMap { file in
            guard BO2ContentClassifier.isConvertibleResource(path: file.relativePath) else { return nil }
            let ext = file.fileExtension.lowercased()
            let stage: GameDataStage
            switch ext {
            case "ff": stage = .zone
            case "ipak", "iwi", "dds", "png", "jpg", "jpeg", "tga": stage = .images
            case "sabs", "sabl", "wav", "mp3", "at3", "at9", "wem", "xma": stage = .audio
            case "xmodel", "xmodel_bin": stage = .models
            case "xanim", "xanim_bin": stage = .animations
            case "material": stage = .materials
            case "gsc", "csc", "cfg", "csv", "str": stage = .scripts
            case "menu", "vision": stage = .ui
            default: stage = .container
            }
            return BO2ConversionUnit(
                sourcePath: file.relativePath,
                mode: BO2ContentClassifier.classify(path: file.relativePath),
                stage: stage
            )
        }
        .sorted { $0.sourcePath.localizedCaseInsensitiveCompare($1.sourcePath) == .orderedAscending }
    }

    func convert(report: ScanReport, rootURL: URL, gameDataRoot: URL? = nil) async throws -> BO2FullGameConversionReport {
        let outputRoot = try gameDataRoot ?? RuntimeCachePolicy.gameDataDirectory()
        let store = try GameDataStore(rootURL: outputRoot, converterVersion: Self.converterVersion)
        var manifest = try store.loadManifest()
        let units = Self.plan(report: report)
        let filesByPath = Dictionary(uniqueKeysWithValues: report.files.map { ($0.relativePath.lowercased(), $0) })

        var completed = 0
        var resumed = 0
        var pending: [BO2ConversionUnit] = []
        var failures: [String] = []

        for unit in units {
            let key = unit.sourcePath.lowercased()
            guard let file = filesByPath[key] else { continue }
            let sourceURL = rootURL.appendingPathComponent(file.relativePath)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                failures.append(ConversionError.sourceMissing(file.relativePath).localizedDescription)
                continue
            }

            let hash = try sourceSHA256(sourceURL)
            let output = outputRelativePath(for: unit)
            if !manifest.needsConversion(
                sourcePath: unit.sourcePath,
                sourceHash: hash,
                stage: unit.stage,
                converterVersion: Self.converterVersion
            ), let record = manifest.records[GameDataManifest.key(sourcePath: unit.sourcePath, stage: unit.stage)],
               let relative = record.outputRelativePath,
               store.outputExists(relativePath: relative, expectedSize: record.outputSize) {
                resumed += 1
                continue
            }

            do {
                switch unit.stage {
                case .zone:
                    manifest.markInProgress(sourcePath: unit.sourcePath, sourceHash: hash, stage: .zone)
                    try store.saveManifest(manifest)
                    let resource = try loadResource(file: file, rootURL: rootURL)
                    let decoded = try await decoder.decodePrefix(
                        rootURL: rootURL,
                        resource: resource,
                        maxDecodedBytes: Int.max / 8,
                        maxChunks: 1_000_000
                    )
                    guard decoded.isUsable,
                          UInt64(decoded.payloadPrefix.count) == decoded.decodedBytes else {
                        throw ConversionError.invalidDecodedZone(unit.sourcePath)
                    }

                    _ = try T6ZoneIndexDecoder.decode(decoded.payloadPrefix)
                    let finalURL = try store.writeOutput(decoded.payloadPrefix, relativePath: output)
                    let size = try fileSize(finalURL)
                    manifest.markCompleted(
                        sourcePath: unit.sourcePath,
                        sourceHash: hash,
                        stage: .zone,
                        outputRelativePath: output,
                        outputSize: size
                    )
                    try store.saveManifest(manifest)
                    completed += 1

                default:
                    // These stages intentionally remain pending until their typed
                    // decoders emit native GameData. Never mark an indexed/raw file
                    // as converted; the release gate depends on this distinction.
                    pending.append(unit)
                }
            } catch {
                manifest.markFailed(
                    sourcePath: unit.sourcePath,
                    sourceHash: hash,
                    stage: unit.stage,
                    error: error.localizedDescription
                )
                try? store.saveManifest(manifest)
                failures.append("\(unit.sourcePath): \(error.localizedDescription)")
            }
        }

        return BO2FullGameConversionReport(
            totalUnits: units.count,
            completedUnits: completed,
            resumedUnits: resumed,
            pendingUnits: pending,
            failures: failures
        )
    }

    private func loadResource(file: ScannedFile, rootURL: URL) throws -> TranzitLoadedResource {
        let url = rootURL.appendingPathComponent(file.relativePath)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? file.size
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 256) ?? Data()
        guard size > 0, !header.isEmpty else { throw ConversionError.sourceMissing(file.relativePath) }
        return TranzitLoadedResource(relativePath: file.relativePath, byteCount: size, header: header)
    }

    private func sourceSHA256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func outputRelativePath(for unit: BO2ConversionUnit) -> String {
        let safe = unit.sourcePath
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map { component in
                component.map { character in
                    character.isLetter || character.isNumber || character == "." || character == "_" || character == "-" ? character : "_"
                }.reduce(into: "") { $0.append($1) }
            }
            .joined(separator: "__")
        return "zones/\(unit.mode.rawValue)/\(safe).zone.bin"
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let number = attrs[.size] as? NSNumber else { throw ConversionError.outputMissing(url.path) }
        return number.uint64Value
    }
}

import Foundation

enum FullGameValidationExporter {
    static func write(_ report: FullGameValidationReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let part = url.appendingPathExtension("part")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: part, options: [.atomic])
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: part)
        } else {
            try FileManager.default.moveItem(at: part, to: url)
        }
    }

    static func read(from url: URL) throws -> FullGameValidationReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FullGameValidationReport.self, from: Data(contentsOf: url))
    }
}

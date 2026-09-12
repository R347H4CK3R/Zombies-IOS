import Foundation

struct ConvertedSourceFingerprint: Codable, Equatable {
    struct FileRecord: Codable, Equatable {
        let relativePath: String
        let fileSize: Int64
        let modificationDate: TimeInterval
    }

    let files: [FileRecord]

    static func make(for files: [URL], relativeTo rootURL: URL? = nil) throws -> ConvertedSourceFingerprint {
        let fm = FileManager.default
        let rootPath = rootURL?.standardizedFileURL.path

        let records = try files.map { url -> FileRecord in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let fileSize = Int64(values.fileSize ?? 0)
            let modificationDate = (values.contentModificationDate ?? .distantPast).timeIntervalSince1970

            let standardized = url.standardizedFileURL.path
            let relativePath: String
            if let rootPath, standardized.hasPrefix(rootPath) {
                let suffix = standardized.dropFirst(rootPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                relativePath = suffix.lowercased()
            } else {
                relativePath = url.lastPathComponent.lowercased()
            }

            guard fm.fileExists(atPath: url.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            return FileRecord(relativePath: relativePath, fileSize: fileSize, modificationDate: modificationDate)
        }
        .sorted { lhs, rhs in
            if lhs.relativePath != rhs.relativePath { return lhs.relativePath < rhs.relativePath }
            if lhs.fileSize != rhs.fileSize { return lhs.fileSize < rhs.fileSize }
            return lhs.modificationDate < rhs.modificationDate
        }

        return ConvertedSourceFingerprint(files: records)
    }
}

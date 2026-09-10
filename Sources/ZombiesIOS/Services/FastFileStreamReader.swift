import Foundation

actor FastFileStreamReader {
    enum StreamError: LocalizedError {
        case invalidOffset
        case emptyRead

        var errorDescription: String? {
            switch self {
            case .invalidOffset:
                return "The requested FastFile offset is outside the file."
            case .emptyRead:
                return "The FastFile returned no data at the requested offset."
            }
        }
    }

    struct Chunk: Sendable {
        let offset: UInt64
        let data: Data
        let fileSize: UInt64

        var nextOffset: UInt64 {
            min(fileSize, offset + UInt64(data.count))
        }

        var progress: Double {
            guard fileSize > 0 else { return 0 }
            return min(1, Double(nextOffset) / Double(fileSize))
        }
    }

    private let fileURL: URL
    private let fileSize: UInt64

    init(rootURL: URL, resource: TranzitLoadedResource) {
        self.fileURL = rootURL.appendingPathComponent(resource.relativePath)
        self.fileSize = UInt64(max(0, resource.byteCount))
    }

    func read(offset: UInt64, length: Int = 64 * 1024) throws -> Chunk {
        guard offset < fileSize || (offset == 0 && fileSize > 0) else {
            throw StreamError.invalidOffset
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)

        let remaining = fileSize - offset
        let requested = min(UInt64(max(1, length)), remaining)
        let data = try handle.read(upToCount: Int(requested)) ?? Data()
        guard !data.isEmpty else { throw StreamError.emptyRead }

        return Chunk(offset: offset, data: data, fileSize: fileSize)
    }

    func sampleAnchors(length: Int = 16 * 1024) throws -> [Chunk] {
        guard fileSize > 0 else { throw StreamError.emptyRead }
        let sampleLength = UInt64(max(1, length))
        let maxStart = fileSize > sampleLength ? fileSize - sampleLength : 0
        let offsets = Array(Set([UInt64(0), maxStart / 2, maxStart])).sorted()
        return try offsets.map { try read(offset: $0, length: length) }
    }
}

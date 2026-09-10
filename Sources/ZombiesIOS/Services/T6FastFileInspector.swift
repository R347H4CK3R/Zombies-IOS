import Foundation

struct T6FastFileContainerReport: Sendable {
    let magic: String
    let version: UInt32
    let isT6PS3: Bool
    let chunkSizes: [UInt32]
    let invalidChunkSize: UInt32?

    var validChunkCount: Int { chunkSizes.count }

    var status: String {
        guard isT6PS3 else { return "NON-T6-PS3 HEADER" }
        if invalidChunkSize != nil { return "T6 PS3 CHUNK ERROR" }
        return chunkSizes.isEmpty ? "T6 PS3 HEADER" : "T6 PS3 XCHUNKS OK"
    }
}

enum T6FastFileInspector {
    static let ps3Magic = "TAsvu100"
    static let ps3Version: UInt32 = 146
    static let maxXChunkSize: UInt32 = 0x8000

    static func inspect(rootURL: URL, resource: TranzitLoadedResource, maxChunks: Int = 24) throws -> T6FastFileContainerReport {
        let url = rootURL.appendingPathComponent(resource.relativePath)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: 0)
        let header = try handle.read(upToCount: 12) ?? Data()
        guard header.count == 12 else {
            return T6FastFileContainerReport(magic: "", version: 0, isT6PS3: false, chunkSizes: [], invalidChunkSize: nil)
        }

        let magic = String(bytes: header.prefix(8), encoding: .ascii) ?? ""
        let version = littleEndianUInt32(header, offset: 8)
        let isT6PS3 = magic == ps3Magic && version == ps3Version
        guard isT6PS3 else {
            return T6FastFileContainerReport(magic: magic, version: version, isT6PS3: false, chunkSizes: [], invalidChunkSize: nil)
        }

        var offset: UInt64 = 12
        var sizes: [UInt32] = []
        var invalid: UInt32?
        let fileSize = UInt64(max(0, resource.byteCount))

        for _ in 0..<max(1, maxChunks) {
            guard offset + 4 <= fileSize else { break }
            try handle.seek(toOffset: offset)
            let sizeData = try handle.read(upToCount: 4) ?? Data()
            guard sizeData.count == 4 else { break }
            let size = littleEndianUInt32(sizeData, offset: 0)
            if size == 0 { break }
            if size > maxXChunkSize {
                invalid = size
                break
            }
            guard offset + 4 + UInt64(size) <= fileSize else {
                invalid = size
                break
            }
            sizes.append(size)
            offset += 4 + UInt64(size)
        }

        return T6FastFileContainerReport(
            magic: magic,
            version: version,
            isT6PS3: true,
            chunkSizes: sizes,
            invalidChunkSize: invalid
        )
    }

    private static func littleEndianUInt32(_ data: Data, offset: Int) -> UInt32 {
        guard data.count >= offset + 4 else { return 0 }
        return UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }
}

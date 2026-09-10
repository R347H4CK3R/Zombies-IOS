import Foundation

struct T6FastFileContainerReport: Sendable {
    let magic: String
    let version: UInt32
    let isT6PS3: Bool
    let isSigned: Bool
    let isEncrypted: Bool
    let authMagic: String?
    let embeddedName: String?
    let payloadOffset: UInt64
    let chunkSizes: [UInt32]
    let invalidChunkSize: UInt32?

    var validChunkCount: Int { chunkSizes.count }
    var supportsRawXChunks: Bool { isT6PS3 && !isEncrypted }

    var status: String {
        guard isT6PS3 else { return "NON-T6-PS3 HEADER" }
        if isEncrypted { return "T6 PS3 SIGNED/ENCRYPTED FF" }
        if invalidChunkSize != nil { return "T6 PS3 CHUNK ERROR" }
        return chunkSizes.isEmpty ? "T6 PS3 HEADER" : "T6 PS3 XCHUNKS OK"
    }
}

enum T6FastFileInspector {
    static let unsignedServerMagic = "TAsvu100"
    static let signedMagic = "TAff0100"
    static let authHeaderMagic = "PHEEBs71"
    static let ps3Version: UInt32 = 146
    static let maxXChunkSize: UInt32 = 0x8000

    // T6 signed header: ZoneHeader (12) + auth magic (8) + flags (4)
    // + filename (32) + RSA signature (256). The encrypted XChunk stream follows.
    static let unsignedPayloadOffset: UInt64 = 12
    static let signedPayloadOffset: UInt64 = 0x138

    static func inspect(
        rootURL: URL,
        resource: TranzitLoadedResource,
        maxChunks: Int = 24
    ) throws -> T6FastFileContainerReport {
        let url = rootURL.appendingPathComponent(resource.relativePath)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: 0)
        let header = try handle.read(upToCount: Int(signedPayloadOffset)) ?? Data()
        guard header.count >= 12 else {
            return emptyReport()
        }

        let magic = ascii(header, offset: 0, length: 8)
        let littleVersion = littleEndianUInt32(header, offset: 8)
        let bigVersion = bigEndianUInt32(header, offset: 8)

        if magic == unsignedServerMagic && littleVersion == ps3Version {
            return try inspectUnsignedChunks(
                handle: handle,
                resource: resource,
                magic: magic,
                version: littleVersion,
                maxChunks: maxChunks
            )
        }

        // Retail BO2 PS3 FastFiles identify themselves by the signed Treyarch
        // container magic, big-endian T6 version 146, and PHEEBs71 auth header.
        // Do not require "PS3_GAME/" in the relative path: iOS lets the user pick
        // PS3_GAME, USRDIR, or a deeper subfolder as the persisted import root, so
        // the exact same PS3 FastFile can legitimately have a shorter relative path.
        let authMagic = header.count >= 20 ? ascii(header, offset: 12, length: 8) : ""
        let signedPS3 = magic == signedMagic &&
            bigVersion == ps3Version &&
            authMagic == authHeaderMagic

        if signedPS3 {
            let embeddedName = header.count >= 56 ? asciiCString(header, offset: 24, length: 32) : nil
            return T6FastFileContainerReport(
                magic: magic,
                version: bigVersion,
                isT6PS3: true,
                isSigned: true,
                isEncrypted: true,
                authMagic: authMagic,
                embeddedName: embeddedName,
                payloadOffset: signedPayloadOffset,
                chunkSizes: [],
                invalidChunkSize: nil
            )
        }

        return T6FastFileContainerReport(
            magic: magic,
            version: littleVersion,
            isT6PS3: false,
            isSigned: false,
            isEncrypted: false,
            authMagic: authMagic.isEmpty ? nil : authMagic,
            embeddedName: nil,
            payloadOffset: unsignedPayloadOffset,
            chunkSizes: [],
            invalidChunkSize: nil
        )
    }

    private static func inspectUnsignedChunks(
        handle: FileHandle,
        resource: TranzitLoadedResource,
        magic: String,
        version: UInt32,
        maxChunks: Int
    ) throws -> T6FastFileContainerReport {
        var offset = unsignedPayloadOffset
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
            if size > maxXChunkSize || offset + 4 + UInt64(size) > fileSize {
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
            isSigned: false,
            isEncrypted: false,
            authMagic: nil,
            embeddedName: nil,
            payloadOffset: unsignedPayloadOffset,
            chunkSizes: sizes,
            invalidChunkSize: invalid
        )
    }

    private static func emptyReport() -> T6FastFileContainerReport {
        T6FastFileContainerReport(
            magic: "",
            version: 0,
            isT6PS3: false,
            isSigned: false,
            isEncrypted: false,
            authMagic: nil,
            embeddedName: nil,
            payloadOffset: unsignedPayloadOffset,
            chunkSizes: [],
            invalidChunkSize: nil
        )
    }

    private static func ascii(_ data: Data, offset: Int, length: Int) -> String {
        guard offset >= 0, length >= 0, data.count >= offset + length else { return "" }
        return String(bytes: data[offset..<(offset + length)], encoding: .ascii) ?? ""
    }

    private static func asciiCString(_ data: Data, offset: Int, length: Int) -> String? {
        guard offset >= 0, length > 0, data.count >= offset + length else { return nil }
        let bytes = Array(data[offset..<(offset + length)])
        let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
        guard end > 0 else { return nil }
        return String(bytes: bytes[..<end], encoding: .ascii)
    }

    private static func littleEndianUInt32(_ data: Data, offset: Int) -> UInt32 {
        guard data.count >= offset + 4 else { return 0 }
        return UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    private static func bigEndianUInt32(_ data: Data, offset: Int) -> UInt32 {
        guard data.count >= offset + 4 else { return 0 }
        return (UInt32(data[offset]) << 24) |
            (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) |
            UInt32(data[offset + 3])
    }
}

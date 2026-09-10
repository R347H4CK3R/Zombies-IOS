import Foundation

struct T6DecodedPayloadReport: Sendable {
    let compressedBytesRead: UInt64
    let decodedBytes: UInt64
    let decodedChunkCount: Int
    let firstChunkOffset: UInt64
    let stoppedAtOffset: UInt64
    let payloadPrefix: Data
    let zoneSize: UInt32?
    let externalZoneSize: UInt32?
    let firstError: String?

    var isUsable: Bool {
        decodedChunkCount > 0 && !payloadPrefix.isEmpty && firstError == nil
    }

    var status: String {
        if let firstError { return "T6 DECODE ERROR: \(firstError)" }
        return decodedChunkCount > 0 ? "T6 PAYLOAD DECODED" : "T6 PAYLOAD EMPTY"
    }
}

actor T6PS3PayloadDecoder {
    enum DecodeError: LocalizedError {
        case invalidContainer
        case invalidChunkSize(UInt32, Int)
        case truncatedChunk(Int)
        case inflateFailed(Int, Int32)

        var errorDescription: String? {
            switch self {
            case .invalidContainer:
                return "The selected FastFile is not a supported T6 PS3 server FastFile."
            case .invalidChunkSize(let size, let index):
                return "XChunk \(index) has invalid compressed size \(size)."
            case .truncatedChunk(let index):
                return "XChunk \(index) is truncated."
            case .inflateFailed(let index, let code):
                return "XChunk \(index) raw-DEFLATE decode failed with zlib code \(code)."
            }
        }
    }

    private let xChunkOutputCapacity = Int(T6FastFileInspector.maxXChunkSize)

    /// Decodes a bounded prefix of the T6 zone payload directly from the external
    /// security-scoped BO2 folder. Nothing is persisted to the app container.
    func decodePrefix(
        rootURL: URL,
        resource: TranzitLoadedResource,
        maxDecodedBytes: Int = 4 * 1024 * 1024,
        maxChunks: Int = 256
    ) throws -> T6DecodedPayloadReport {
        let container = try T6FastFileInspector.inspect(rootURL: rootURL, resource: resource, maxChunks: 1)
        guard container.isT6PS3 else { throw DecodeError.invalidContainer }

        let url = rootURL.appendingPathComponent(resource.relativePath)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = UInt64(max(0, resource.byteCount))
        var offset: UInt64 = 12
        var chunkIndex = 0
        var compressedRead: UInt64 = 0
        var decodedTotal: UInt64 = 0
        var prefix = Data()
        prefix.reserveCapacity(min(maxDecodedBytes, 1024 * 1024))

        while chunkIndex < max(1, maxChunks), prefix.count < maxDecodedBytes {
            guard offset + 4 <= fileSize else { break }
            try handle.seek(toOffset: offset)
            let sizeData = try handle.read(upToCount: 4) ?? Data()
            guard sizeData.count == 4 else { break }

            let compressedSize = Self.littleEndianUInt32(sizeData)
            if compressedSize == 0 { break }
            guard compressedSize <= T6FastFileInspector.maxXChunkSize else {
                throw DecodeError.invalidChunkSize(compressedSize, chunkIndex)
            }

            let chunkDataOffset = offset + 4
            let chunkEnd = chunkDataOffset + UInt64(compressedSize)
            guard chunkEnd <= fileSize else { throw DecodeError.truncatedChunk(chunkIndex) }

            try handle.seek(toOffset: chunkDataOffset)
            let compressed = try handle.read(upToCount: Int(compressedSize)) ?? Data()
            guard compressed.count == Int(compressedSize) else { throw DecodeError.truncatedChunk(chunkIndex) }

            let outputCapacity = xChunkOutputCapacity
            var output = Data(count: outputCapacity)
            var outputSize: Int = 0
            let inputCount = compressed.count
            let result: Int32 = compressed.withUnsafeBytes { inputRaw in
                output.withUnsafeMutableBytes { outputRaw in
                    guard let input = inputRaw.bindMemory(to: UInt8.self).baseAddress,
                          let out = outputRaw.bindMemory(to: UInt8.self).baseAddress else {
                        return -2
                    }
                    return Int32(zombies_t6_inflate_raw(
                        input,
                        inputCount,
                        out,
                        outputCapacity,
                        &outputSize
                    ))
                }
            }

            guard result == 0 else { throw DecodeError.inflateFailed(chunkIndex, result) }
            guard outputSize > 0 && outputSize <= outputCapacity else {
                throw DecodeError.inflateFailed(chunkIndex, -5)
            }

            if outputSize < output.count {
                output.removeSubrange(outputSize..<output.count)
            }
            let remaining = maxDecodedBytes - prefix.count
            if output.count <= remaining {
                prefix.append(output)
            } else {
                prefix.append(output.prefix(remaining))
            }

            compressedRead += UInt64(compressed.count)
            decodedTotal += UInt64(outputSize)
            chunkIndex += 1
            offset = chunkEnd
        }

        let zoneSize = prefix.count >= 4 ? Self.littleEndianUInt32(prefix, offset: 0) : nil
        let externalSize = prefix.count >= 8 ? Self.littleEndianUInt32(prefix, offset: 4) : nil

        return T6DecodedPayloadReport(
            compressedBytesRead: compressedRead,
            decodedBytes: decodedTotal,
            decodedChunkCount: chunkIndex,
            firstChunkOffset: 12,
            stoppedAtOffset: offset,
            payloadPrefix: prefix,
            zoneSize: zoneSize,
            externalZoneSize: externalSize,
            firstError: nil
        )
    }

    private static func littleEndianUInt32(_ data: Data, offset: Int = 0) -> UInt32 {
        guard data.count >= offset + 4 else { return 0 }
        return UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }
}

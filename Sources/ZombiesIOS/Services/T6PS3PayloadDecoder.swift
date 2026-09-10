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
    let xBlockSizes: [UInt32]
    let firstError: String?

    var xBlockTotalBytes: UInt64 {
        xBlockSizes.reduce(0) { $0 + UInt64($1) }
    }

    var hasSaneXBlocks: Bool {
        xBlockSizes.count == 8 && xBlockTotalBytes <= 0x3C000000
    }

    var isUsable: Bool {
        decodedChunkCount > 0 && !payloadPrefix.isEmpty && firstError == nil && hasSaneXBlocks
    }

    var status: String {
        if let firstError { return "T6 DECODE ERROR: \(firstError)" }
        if decodedChunkCount == 0 { return "T6 PAYLOAD EMPTY" }
        return hasSaneXBlocks ? "T6 XFILE STRUCTURE OK" : "T6 XFILE BLOCK ERROR"
    }
}

actor T6PS3PayloadDecoder {
    enum DecodeError: LocalizedError {
        case invalidContainer
        case missingEmbeddedName
        case invalidChunkSize(UInt32, Int)
        case truncatedChunk(Int)
        case inflateFailed(Int, Int32)
        case salsaFailed(Int)
        case noWorkingSignedKey(String)

        var errorDescription: String? {
            switch self {
            case .invalidContainer:
                return "The selected FastFile is not a recognized T6 PS3 FastFile."
            case .missingEmbeddedName:
                return "The signed T6 FastFile has no usable embedded zone name for its IV hash chain."
            case .invalidChunkSize(let size, let index):
                return "XChunk \(index) has invalid compressed size \(size)."
            case .truncatedChunk(let index):
                return "XChunk \(index) is truncated."
            case .inflateFailed(let index, let code):
                return "XChunk \(index) raw-DEFLATE decode failed with zlib code \(code)."
            case .salsaFailed(let index):
                return "XChunk \(index) Salsa20 decryption failed."
            case .noWorkingSignedKey(let name):
                return "\(name) is a signed T6 PS3 FastFile, but no configured Salsa20 key produced a valid first XChunk."
            }
        }
    }

    private struct KeyCandidate {
        let name: String
        let bytes: Data
    }

    private let xChunkOutputCapacity = Int(T6FastFileInspector.maxXChunkSize)
    private let vanillaBufferSize: UInt64 = 0x80000

    func decodePrefix(
        rootURL: URL,
        resource: TranzitLoadedResource,
        maxDecodedBytes: Int = 4 * 1024 * 1024,
        maxChunks: Int = 256
    ) throws -> T6DecodedPayloadReport {
        let container = try T6FastFileInspector.inspect(rootURL: rootURL, resource: resource, maxChunks: 1)
        guard container.isT6PS3 else { throw DecodeError.invalidContainer }

        if container.isEncrypted {
            return try decodeSignedPrefix(
                rootURL: rootURL,
                resource: resource,
                container: container,
                maxDecodedBytes: maxDecodedBytes,
                maxChunks: maxChunks
            )
        }

        return try decodeUnsignedPrefix(
            rootURL: rootURL,
            resource: resource,
            container: container,
            maxDecodedBytes: maxDecodedBytes,
            maxChunks: maxChunks
        )
    }

    private func decodeUnsignedPrefix(
        rootURL: URL,
        resource: TranzitLoadedResource,
        container: T6FastFileContainerReport,
        maxDecodedBytes: Int,
        maxChunks: Int
    ) throws -> T6DecodedPayloadReport {
        let url = rootURL.appendingPathComponent(resource.relativePath)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = UInt64(max(0, resource.byteCount))
        var offset = container.payloadOffset
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

            let output = try inflate(compressed, chunkIndex: chunkIndex)
            appendDecoded(output, to: &prefix, maxDecodedBytes: maxDecodedBytes)

            compressedRead += UInt64(compressed.count)
            decodedTotal += UInt64(output.count)
            chunkIndex += 1
            offset = chunkEnd
        }

        return makeReport(
            compressedRead: compressedRead,
            decodedTotal: decodedTotal,
            chunkIndex: chunkIndex,
            firstChunkOffset: container.payloadOffset,
            stoppedAtOffset: offset,
            prefix: prefix
        )
    }

    private func decodeSignedPrefix(
        rootURL: URL,
        resource: TranzitLoadedResource,
        container: T6FastFileContainerReport,
        maxDecodedBytes: Int,
        maxChunks: Int
    ) throws -> T6DecodedPayloadReport {
        guard let zoneName = container.embeddedName, !zoneName.isEmpty else {
            throw DecodeError.missingEmbeddedName
        }

        let url = rootURL.appendingPathComponent(resource.relativePath)
        var candidates = loadExternalKeyCandidates(rootURL: rootURL)
        candidates.append(KeyCandidate(name: "BO2 PS3", bytes: T6Salsa20.ps3Key))
        candidates.append(KeyCandidate(name: "BO2 Xenon", bytes: T6Salsa20.xenonKey))
        candidates.append(KeyCandidate(name: "BO2 PC", bytes: T6Salsa20.pcKey))

        var lastFailure: Error?
        for candidate in candidates {
            do {
                return try decodeSignedPrefix(
                    url: url,
                    resource: resource,
                    container: container,
                    zoneName: zoneName,
                    key: candidate,
                    maxDecodedBytes: maxDecodedBytes,
                    maxChunks: maxChunks
                )
            } catch {
                lastFailure = error
            }
        }

        if let decodeError = lastFailure as? DecodeError {
            switch decodeError {
            case .invalidChunkSize, .truncatedChunk:
                throw decodeError
            default:
                break
            }
        }
        throw DecodeError.noWorkingSignedKey(zoneName)
    }

    private func decodeSignedPrefix(
        url: URL,
        resource: TranzitLoadedResource,
        container: T6FastFileContainerReport,
        zoneName: String,
        key: KeyCandidate,
        maxDecodedBytes: Int,
        maxChunks: Int
    ) throws -> T6DecodedPayloadReport {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard var chain = T6FastFileHashChain(zoneName: zoneName) else {
            throw DecodeError.missingEmbeddedName
        }

        let fileSize = UInt64(max(0, resource.byteCount))
        var offset = container.payloadOffset
        var virtualOffset = container.payloadOffset % vanillaBufferSize
        var chunkIndex = 0
        var compressedRead: UInt64 = 0
        var decodedTotal: UInt64 = 0
        var prefix = Data()
        prefix.reserveCapacity(min(maxDecodedBytes, 1024 * 1024))

        while chunkIndex < max(1, maxChunks), prefix.count < maxDecodedBytes {
            if virtualOffset + 4 > vanillaBufferSize {
                let skip = vanillaBufferSize - virtualOffset
                offset += skip
                virtualOffset = 0
            }

            guard offset + 4 <= fileSize else { break }
            try handle.seek(toOffset: offset)
            let sizeData = try handle.read(upToCount: 4) ?? Data()
            guard sizeData.count == 4 else { break }

            let encryptedSize = Self.bigEndianUInt32(sizeData)
            offset += 4
            virtualOffset = (virtualOffset + 4) % vanillaBufferSize
            if encryptedSize == 0 { break }
            guard encryptedSize <= T6FastFileInspector.maxXChunkSize else {
                throw DecodeError.invalidChunkSize(encryptedSize, chunkIndex)
            }

            let chunkEnd = offset + UInt64(encryptedSize)
            guard chunkEnd <= fileSize else { throw DecodeError.truncatedChunk(chunkIndex) }
            try handle.seek(toOffset: offset)
            let encrypted = try handle.read(upToCount: Int(encryptedSize)) ?? Data()
            guard encrypted.count == Int(encryptedSize) else { throw DecodeError.truncatedChunk(chunkIndex) }

            let stream = chunkIndex % 4
            let iv = chain.iv(for: stream)
            guard let decrypted = T6Salsa20.crypt(encrypted, key: key.bytes, iv: iv) else {
                throw DecodeError.salsaFailed(chunkIndex)
            }
            chain.advance(stream: stream, decryptedChunk: decrypted)

            let output = try inflate(decrypted, chunkIndex: chunkIndex)
            appendDecoded(output, to: &prefix, maxDecodedBytes: maxDecodedBytes)

            compressedRead += UInt64(encrypted.count)
            decodedTotal += UInt64(output.count)
            chunkIndex += 1
            offset = chunkEnd
            virtualOffset = (virtualOffset + UInt64(encryptedSize)) % vanillaBufferSize
        }

        guard chunkIndex > 0 else {
            throw DecodeError.noWorkingSignedKey(zoneName)
        }

        return makeReport(
            compressedRead: compressedRead,
            decodedTotal: decodedTotal,
            chunkIndex: chunkIndex,
            firstChunkOffset: container.payloadOffset,
            stoppedAtOffset: offset,
            prefix: prefix
        )
    }

    private func inflate(_ compressed: Data, chunkIndex: Int) throws -> Data {
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
        return output
    }

    private func appendDecoded(_ output: Data, to prefix: inout Data, maxDecodedBytes: Int) {
        let remaining = maxDecodedBytes - prefix.count
        if output.count <= remaining {
            prefix.append(output)
        } else if remaining > 0 {
            prefix.append(output.prefix(remaining))
        }
    }

    private func makeReport(
        compressedRead: UInt64,
        decodedTotal: UInt64,
        chunkIndex: Int,
        firstChunkOffset: UInt64,
        stoppedAtOffset: UInt64,
        prefix: Data
    ) -> T6DecodedPayloadReport {
        let zoneSize = prefix.count >= 4 ? Self.bigEndianUInt32(prefix, offset: 0) : nil
        let externalSize = prefix.count >= 8 ? Self.bigEndianUInt32(prefix, offset: 4) : nil
        var blockSizes: [UInt32] = []
        if prefix.count >= 40 {
            blockSizes.reserveCapacity(8)
            for index in 0..<8 {
                blockSizes.append(Self.bigEndianUInt32(prefix, offset: 8 + index * 4))
            }
        }

        return T6DecodedPayloadReport(
            compressedBytesRead: compressedRead,
            decodedBytes: decodedTotal,
            decodedChunkCount: chunkIndex,
            firstChunkOffset: firstChunkOffset,
            stoppedAtOffset: stoppedAtOffset,
            payloadPrefix: prefix,
            zoneSize: zoneSize,
            externalZoneSize: externalSize,
            xBlockSizes: blockSizes,
            firstError: nil
        )
    }

    private func loadExternalKeyCandidates(rootURL: URL) -> [KeyCandidate] {
        let names = ["t6_ps3_salsa20.key", "T6_PS3_SALSA20_KEY.bin", "t6_ps3_salsa20.txt"]
        var result: [KeyCandidate] = []

        for name in names {
            let url = rootURL.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }

            if data.count == 32 {
                result.append(KeyCandidate(name: name, bytes: data))
                continue
            }

            if let text = String(data: data, encoding: .utf8) {
                let hex = text.filter { $0.isHexDigit }
                if hex.count == 64 {
                    var bytes = [UInt8]()
                    bytes.reserveCapacity(32)
                    var index = hex.startIndex
                    var valid = true
                    for _ in 0..<32 {
                        let next = hex.index(index, offsetBy: 2)
                        guard let value = UInt8(hex[index..<next], radix: 16) else {
                            valid = false
                            break
                        }
                        bytes.append(value)
                        index = next
                    }
                    if valid && bytes.count == 32 {
                        result.append(KeyCandidate(name: name, bytes: Data(bytes)))
                    }
                }
            }
        }
        return result
    }

    private static func littleEndianUInt32(_ data: Data, offset: Int = 0) -> UInt32 {
        guard data.count >= offset + 4 else { return 0 }
        return UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    private static func bigEndianUInt32(_ data: Data, offset: Int = 0) -> UInt32 {
        guard data.count >= offset + 4 else { return 0 }
        return (UInt32(data[offset]) << 24) |
            (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) |
            UInt32(data[offset + 3])
    }
}

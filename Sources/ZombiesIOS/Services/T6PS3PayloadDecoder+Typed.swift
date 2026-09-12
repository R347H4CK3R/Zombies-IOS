import Foundation

extension T6PS3PayloadDecoder {
    func decodeZone(
        rootURL: URL,
        resource: TranzitLoadedResource,
        maxDecodedBytes: Int = 128 * 1024 * 1024,
        maxChunks: Int = 4096
    ) throws -> T6DecodedZone {
        let report = try decodePrefix(
            rootURL: rootURL,
            resource: resource,
            maxDecodedBytes: maxDecodedBytes,
            maxChunks: maxChunks
        )
        guard report.isUsable else {
            throw DecodeError.invalidContainer
        }

        let zoneName = URL(fileURLWithPath: resource.fileName)
            .deletingPathExtension()
            .lastPathComponent
        return try T6AssetTableDecoder().decode(zoneName: zoneName, payload: report.payloadPrefix)
    }
}

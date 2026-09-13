import Foundation

struct BO2MapRuntimeSession {
    let target: BO2MapTarget
    let packageURL: URL
    let package: BO2RuntimePackage
    let ipakIndex: T6IPAKIndex
}

actor BO2MapRuntimeLoader {
    enum LoaderError: LocalizedError {
        case missingFastFile(String)
        case missingIPAK(String)
        case unreadableFastFile(String)
        case decodeFailed(String)
        case ipakFailed(String)
        case geometryMissing(String)

        var errorDescription: String? {
            switch self {
            case .missingFastFile(let name): return "Missing BO2 FastFile: \(name)"
            case .missingIPAK(let name): return "Missing BO2 IPAK: \(name)"
            case .unreadableFastFile(let name): return "Cannot read BO2 FastFile: \(name)"
            case .decodeFailed(let name): return "BO2 FastFile decode failed: \(name)"
            case .ipakFailed(let name): return "BO2 IPAK index failed: \(name)"
            case .geometryMissing(let name): return "No validated GfxWorld geometry was found in \(name)."
            }
        }
    }

    private let decoder = T6PS3PayloadDecoder()
    private let writer = BO2RuntimePackageWriter()

    func load(target: BO2MapTarget, report: ScanReport, rootURL: URL) async throws -> BO2MapRuntimeSession {
        guard let file = report.files.first(where: { $0.name.lowercased() == target.fastFileName.lowercased() }) else {
            throw LoaderError.missingFastFile(target.fastFileName)
        }
        guard let ipakFile = report.files.first(where: { $0.name.lowercased() == target.ipakName.lowercased() }) else {
            throw LoaderError.missingIPAK(target.ipakName)
        }

        let ipakURL = rootURL.appendingPathComponent(ipakFile.relativePath)
        let ipakIndex: T6IPAKIndex
        do {
            ipakIndex = try T6IPAKArchive.open(ipakURL)
        } catch {
            throw LoaderError.ipakFailed("\(target.ipakName): \(error.localizedDescription)")
        }

        let resource = try makeResource(file: file, rootURL: rootURL)
        let decoded: T6DecodedPayloadReport
        do {
            decoded = try await decoder.decodePrefix(
                rootURL: rootURL,
                resource: resource,
                maxDecodedBytes: 64 * 1024 * 1024,
                maxChunks: 4096
            )
        } catch {
            throw LoaderError.decodeFailed("\(target.fastFileName): \(error.localizedDescription)")
        }
        guard decoded.isUsable else {
            throw LoaderError.decodeFailed("\(target.fastFileName): \(decoded.status)")
        }
        guard let mesh = T6GfxSurfaceMeshExtractor.extract(from: decoded.payloadPrefix, scanLimit: decoded.payloadPrefix.count) else {
            throw LoaderError.geometryMissing(target.fastFileName)
        }

        let mapped: BO2EntityParser.Result
        if let lump = BO2EntityParser.extractEntityLump(from: decoded.payloadPrefix) {
            mapped = BO2EntityParser.parse(lump)
        } else {
            mapped = BO2EntityParser.Result(entities: [], spawns: [])
        }

        let url = try writer.write(
            mesh: mesh,
            entities: mapped.entities,
            spawns: mapped.spawns,
            sourceName: target.rawValue
        )
        let package = try writer.read(from: url)
        return BO2MapRuntimeSession(
            target: target,
            packageURL: url,
            package: package,
            ipakIndex: ipakIndex
        )
    }

    private func makeResource(file: ScannedFile, rootURL: URL) throws -> TranzitLoadedResource {
        let url = rootURL.appendingPathComponent(file.relativePath)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw LoaderError.unreadableFastFile(file.relativePath)
        }
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 256) ?? Data()
        guard !header.isEmpty else { throw LoaderError.unreadableFastFile(file.relativePath) }
        return TranzitLoadedResource(relativePath: file.relativePath, byteCount: file.size, header: header)
    }
}

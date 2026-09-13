import Foundation
import CryptoKit

struct BO2MapRuntimeSession: Sendable {
    let target: BO2MapTarget
    let rootURL: URL
    let fastFile: TranzitLoadedResource
    let ipak: TranzitLoadedResource
    let audioBank: TranzitLoadedResource
    let decodedReport: T6DecodedPayloadReport
    let packageURL: URL
    let package: BO2RuntimePackage
}

actor BO2MapRuntimeLoader {
    enum LoaderError: LocalizedError {
        case incompleteTarget(String)
        case unreadableResource(String)
        case noWorldGeometry(String)

        var errorDescription: String? {
            switch self {
            case .incompleteTarget(let target):
                return "The selected BO2 folder is missing one or more required \(target) resources."
            case .unreadableResource(let path):
                return "The BO2 resource could not be opened in place: \(path)"
            case .noWorldGeometry(let name):
                return "Decoded \(name), but no validated T6 GfxWorld triangle stream was found."
            }
        }
    }

    func load(
        target: BO2MapTarget,
        report: ScanReport,
        rootURL: URL
    ) async throws -> BO2MapRuntimeSession {
        guard target.isComplete(in: report) else {
            throw LoaderError.incompleteTarget(target.displayName)
        }

        let resources = target.resources(in: report)
        guard let ffFile = resources.first(where: { $0.name.lowercased() == target.fastFileName }),
              let ipakFile = resources.first(where: { $0.name.lowercased() == target.ipakName }),
              let audioFile = resources.first(where: { $0.name.lowercased() == target.audioBankName }) else {
            throw LoaderError.incompleteTarget(target.displayName)
        }

        let fastFile = try loadResource(ffFile, rootURL: rootURL)
        let ipak = try loadResource(ipakFile, rootURL: rootURL)
        let audio = try loadResource(audioFile, rootURL: rootURL)

        let decoder = T6PS3PayloadDecoder()
        let decoded = try await decoder.decodePrefix(
            rootURL: rootURL,
            resource: fastFile,
            maxDecodedBytes: 128 * 1024 * 1024,
            maxChunks: 8192
        )

        let payload = decoded.payloadPrefix
        guard let mesh = await Task.detached(priority: .userInitiated, operation: {
            T6GfxSurfaceMeshExtractor.extract(from: payload, scanLimit: payload.count)
        }).value else {
            throw LoaderError.noWorldGeometry(fastFile.fileName)
        }

        let sourceURL = rootURL.appendingPathComponent(fastFile.relativePath)
        let sourceHash = try sha256(url: sourceURL)
        let entityText = T6MapEntsExtractor.extract(from: payload) ?? ""
        let entities = BO2EntityParser.parse(entityText)
        let packageURL = try BO2RuntimePackageWriter.write(
            mesh: mesh,
            entities: entities,
            sourceName: fastFile.fileName,
            sourceSHA256: sourceHash
        )
        let package = try BO2RuntimePackageWriter.read(from: packageURL)

        return BO2MapRuntimeSession(
            target: target,
            rootURL: rootURL,
            fastFile: fastFile,
            ipak: ipak,
            audioBank: audio,
            decodedReport: decoded,
            packageURL: packageURL,
            package: package
        )
    }

    private func loadResource(_ file: ScannedFile, rootURL: URL) throws -> TranzitLoadedResource {
        let url = rootURL.appendingPathComponent(file.relativePath)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw LoaderError.unreadableResource(file.relativePath)
        }
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 256) ?? Data()
        guard !header.isEmpty else { throw LoaderError.unreadableResource(file.relativePath) }
        return TranzitLoadedResource(relativePath: file.relativePath, byteCount: file.size, header: header)
    }

    private func sha256(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

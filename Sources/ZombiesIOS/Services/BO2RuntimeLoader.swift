import Foundation

struct BO2RuntimeSession: Sendable {
    let rootURL: URL
    let descriptor: BO2LaunchDescriptor
    let resources: [TranzitLoadedResource]

    var totalBytes: Int64 { resources.reduce(0) { $0 + $1.byteCount } }
}

actor BO2RuntimeLoader {
    enum LoaderError: LocalizedError {
        case missingRoot
        case missingResource(String)
        case invalidFastFile(String)

        var errorDescription: String? {
            switch self {
            case .missingRoot: return "The selected BO2 folder is unavailable."
            case .missingResource(let path): return "Required BO2 resource is unavailable: \(path)"
            case .invalidFastFile(let path): return "Required BO2 FastFile is not a valid T6 PS3 container: \(path)"
            }
        }
    }

    func load(
        descriptor: BO2LaunchDescriptor,
        report: ScanReport,
        rootURL: URL,
        validateFastFiles: Bool = true
    ) throws -> BO2RuntimeSession {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { throw LoaderError.missingRoot }
        let byPath = Dictionary(uniqueKeysWithValues: report.files.map { (normalize($0.relativePath), $0) })
        var loaded: [TranzitLoadedResource] = []
        loaded.reserveCapacity(descriptor.resources.count)

        for relativePath in descriptor.resources {
            guard let file = byPath[normalize(relativePath)] else { throw LoaderError.missingResource(relativePath) }
            let resource = try load(file: file, rootURL: rootURL)
            if validateFastFiles && file.fileExtension.lowercased() == "ff" && file.size > 1024 {
                let fingerprint = try T6FastFileInspector.inspect(rootURL: rootURL, resource: resource, maxChunks: 1)
                guard fingerprint.isT6PS3 else { throw LoaderError.invalidFastFile(relativePath) }
            }
            loaded.append(resource)
        }

        return BO2RuntimeSession(rootURL: rootURL, descriptor: descriptor, resources: loaded)
    }

    private func load(file: ScannedFile, rootURL: URL) throws -> TranzitLoadedResource {
        let url = rootURL.appendingPathComponent(file.relativePath)
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw LoaderError.missingResource(file.relativePath) }
        defer { try? handle.close() }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw LoaderError.missingResource(file.relativePath) }
        let header = try handle.read(upToCount: 256) ?? Data()
        guard !header.isEmpty else { throw LoaderError.missingResource(file.relativePath) }
        return TranzitLoadedResource(relativePath: file.relativePath, byteCount: size, header: header)
    }

    private func normalize(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}

import Foundation

struct TranzitLoadedResource: Identifiable, Hashable {
    let relativePath: String
    let byteCount: Int64
    let header: Data

    var id: String { relativePath }
    var fileName: String { (relativePath as NSString).lastPathComponent }
}

struct TranzitLoadedArea: Identifiable, Hashable {
    let area: TranzitArea
    let fastFile: TranzitLoadedResource

    var id: String { area.id }
}

struct TranzitRuntimeSession {
    let rootURL: URL
    let areas: [TranzitLoadedArea]
    let sharedContainers: [TranzitLoadedResource]
    let audioBanks: [TranzitLoadedResource]

    var totalLoadedBytes: Int64 {
        (areas.map(\.fastFile) + sharedContainers + audioBanks)
            .reduce(0) { $0 + $1.byteCount }
    }
}

actor TranzitRuntimeLoader {
    enum LoaderError: LocalizedError {
        case missingImport
        case unreadableResource(String)
        case noAreas

        var errorDescription: String? {
            switch self {
            case .missingImport:
                return "The selected BO2 folder is no longer available."
            case .unreadableResource(let path):
                return "The BO2 resource could not be opened in place: \(path)"
            case .noAreas:
                return "No usable Tranzit area FastFiles were available in the selected folder."
            }
        }
    }

    /// Opens only the smallest usable Tranzit area on the initial runtime pass.
    /// Other area FastFiles stay closed so an iPhone does not pay their memory/I/O
    /// cost before the native gameplay path for one area has been proven.
    func loadCurrent(report: ScanReport, rootURL: URL) throws -> TranzitRuntimeSession {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootURL.path) else {
            throw LoaderError.missingImport
        }

        let index = TranzitRuntimeIndex(report: report)
        guard let firstArea = index.firstPlayableArea,
              let firstFile = index.firstPlayableFastFile else {
            throw LoaderError.noAreas
        }

        let firstResource = try load(file: firstFile, under: rootURL)
        let loadedAreas = [TranzitLoadedArea(area: firstArea, fastFile: firstResource)]

        // Never treat another Tranzit area FastFile as a shared dependency.
        // Shared containers are FF/IPAK resources that are not one of the known
        // area payloads. This avoids silently reopening every map on launch.
        let allAreaNames = Set(
            TranzitArea.allCases.map { ($0.fastFileStem + ".ff").lowercased() }
        )
        let sharedFiles = index.containerFiles.filter {
            !allAreaNames.contains($0.name.lowercased())
        }
        let shared = try sharedFiles.map { try load(file: $0, under: rootURL) }

        // Audio remains indexed separately so the runtime can resolve BO2 banks
        // without copying them. These are opened only for validation/header reads.
        let audio = try index.audioBanks.map { try load(file: $0, under: rootURL) }

        return TranzitRuntimeSession(
            rootURL: rootURL,
            areas: loadedAreas,
            sharedContainers: shared,
            audioBanks: audio
        )
    }

    private func load(file: ScannedFile, under root: URL) throws -> TranzitLoadedResource {
        let url = root.appendingPathComponent(file.relativePath)
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else {
            throw LoaderError.unreadableResource(file.relativePath)
        }
        defer { try? handle.close() }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            throw LoaderError.unreadableResource(file.relativePath)
        }

        // Read only enough bytes to prove the resource is reachable. Keep the BO2
        // data in place instead of materializing complete FastFiles in app memory.
        let header = try handle.read(upToCount: 64) ?? Data()
        guard !header.isEmpty else {
            throw LoaderError.unreadableResource(file.relativePath)
        }

        return TranzitLoadedResource(
            relativePath: file.relativePath,
            byteCount: size,
            header: header
        )
    }
}

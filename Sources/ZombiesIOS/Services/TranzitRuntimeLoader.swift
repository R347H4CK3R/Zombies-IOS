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
                return "No Tranzit area FastFiles were available in the selected folder."
            }
        }
    }

    func loadCurrent(report: ScanReport, rootURL: URL) throws -> TranzitRuntimeSession {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootURL.path) else {
            throw LoaderError.missingImport
        }

        let index = TranzitRuntimeIndex(report: report)
        let filesByName = Dictionary(
            uniqueKeysWithValues: report.files.map { ($0.name.lowercased(), $0) }
        )

        var loadedAreas: [TranzitLoadedArea] = []
        for area in index.availableAreas {
            let name = area.fastFileStem + ".ff"
            guard let file = filesByName[name] else { continue }
            let resource = try load(file: file, under: rootURL)
            loadedAreas.append(TranzitLoadedArea(area: area, fastFile: resource))
        }

        guard !loadedAreas.isEmpty else {
            throw LoaderError.noAreas
        }

        let areaNames = Set(loadedAreas.map { $0.fastFile.fileName.lowercased() })
        let shared = try index.containerFiles
            .filter { !areaNames.contains($0.name.lowercased()) }
            .map { try load(file: $0, under: rootURL) }

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

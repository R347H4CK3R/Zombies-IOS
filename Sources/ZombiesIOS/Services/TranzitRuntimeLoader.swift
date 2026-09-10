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
    let t6ContainerReport: T6FastFileContainerReport?

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

    private struct Candidate {
        let area: TranzitArea
        let resource: TranzitLoadedResource
        let report: T6FastFileContainerReport
    }

    func loadCurrent(report: ScanReport, rootURL: URL) throws -> TranzitRuntimeSession {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootURL.path) else {
            throw LoaderError.missingImport
        }

        let index = TranzitRuntimeIndex(report: report)

        // Fingerprint every real Tranzit area candidate instead of assuming that
        // the smallest filename match is automatically the correct T6 container.
        // Prefer a recognized PS3 FastFile. If an unencrypted server FastFile is
        // present it wins because its XChunks can be consumed immediately; retail
        // signed/encrypted PS3 FastFiles remain valid candidates and are identified
        // explicitly rather than being mislabeled as unsupported.
        var candidates: [Candidate] = []
        for area in TranzitArea.allCases {
            guard let file = report.files.first(where: {
                $0.name.lowercased() == area.fastFileStem + ".ff" && $0.size > 4_096
            }) else { continue }

            guard let resource = try? load(file: file, under: rootURL),
                  let fingerprint = try? T6FastFileInspector.inspect(
                    rootURL: rootURL,
                    resource: resource,
                    maxChunks: 2
                  ),
                  fingerprint.isT6PS3 else {
                continue
            }
            candidates.append(Candidate(area: area, resource: resource, report: fingerprint))
        }

        candidates.sort { lhs, rhs in
            if lhs.report.supportsRawXChunks != rhs.report.supportsRawXChunks {
                return lhs.report.supportsRawXChunks && !rhs.report.supportsRawXChunks
            }
            return lhs.resource.byteCount < rhs.resource.byteCount
        }

        let selectedArea: TranzitArea
        let selectedResource: TranzitLoadedResource
        let containerReport: T6FastFileContainerReport?

        if let selected = candidates.first {
            selectedArea = selected.area
            selectedResource = selected.resource
            containerReport = selected.report
        } else {
            guard let fallbackArea = index.firstPlayableArea,
                  let fallbackFile = index.firstPlayableFastFile else {
                throw LoaderError.noAreas
            }
            selectedArea = fallbackArea
            selectedResource = try load(file: fallbackFile, under: rootURL)
            containerReport = try? T6FastFileInspector.inspect(
                rootURL: rootURL,
                resource: selectedResource
            )
        }

        let loadedAreas = [TranzitLoadedArea(area: selectedArea, fastFile: selectedResource)]

        let allAreaNames = Set(
            TranzitArea.allCases.map { ($0.fastFileStem + ".ff").lowercased() }
        )
        let sharedFiles = index.containerFiles.filter {
            !allAreaNames.contains($0.name.lowercased())
        }
        let shared = try sharedFiles.map { try load(file: $0, under: rootURL) }
        let audio = try index.audioBanks.map { try load(file: $0, under: rootURL) }

        return TranzitRuntimeSession(
            rootURL: rootURL,
            areas: loadedAreas,
            sharedContainers: shared,
            audioBanks: audio,
            t6ContainerReport: containerReport
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

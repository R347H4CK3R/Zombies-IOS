import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

struct ContentView: View {
    @State private var scanning = false
    @State private var report: ScanReport?
    @State private var exportedReportURL: URL?
    @State private var runtimeIndex: TranzitRuntimeIndex?
    @State private var runtimeSession: TranzitRuntimeSession?
    @State private var errorMessage: String?
    @State private var showingFolderPicker = false
    @State private var statusMessage = "Choose your extracted BO2 game folder. The app will read the required Zombies files directly; no ZIP is required."

    private let scanner = PS3DumpScanner()
    private let directFolderImporter = DirectFolderImporter()
    private let runtimeLoader = TranzitRuntimeLoader()
    private let expectedCount = BO2ZombiesManifest.relativePaths.count

    var body: some View {
        NavigationStack {
            List {
                Section("Import BO2 Zombies Data") {
                    Text(statusMessage)
                        .font(.callout)

                    Button {
                        showingFolderPicker = true
                    } label: {
                        Label("Choose BO2 Game Folder", systemImage: "folder")
                    }
                    .disabled(scanning)

                    Text("Select the extracted BO2 folder directly. You can choose PS3_GAME, USRDIR, english, or a parent folder containing those paths. No ZIP is required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if scanning {
                    Section { ProgressView("Importing BO2 runtime files…") }
                }

                if let report {
                    Section("Import Inventory") {
                        LabeledContent("Found", value: "\(report.totalFiles) / \(expectedCount)")
                        LabeledContent("Known size", value: ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file))
                        LabeledContent("Zero-byte files", value: "\(report.zeroByteFiles.count)")
                        LabeledContent("Legacy manifest complete", value: report.isBuildReady ? "Yes" : "No")

                        if report.missingManifestCount > 0 {
                            Text("\(report.missingManifestCount) manifest file(s) were not present.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        if !report.zeroByteFiles.isEmpty {
                            Text("This import is incomplete. Zero-byte BO2 files are missing payload data and must be re-copied before an IPA build.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        if let exportedReportURL {
                            ShareLink(item: exportedReportURL) {
                                Label("Export Filtered JSON Report", systemImage: "square.and.arrow.up")
                            }
                        }
                    }

                    if !report.zeroByteFiles.isEmpty {
                        Section("Files Needing Re-copy") {
                            ForEach(report.zeroByteFiles) { file in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.name)
                                    Text(file.relativePath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section("Matched Zombies Files") {
                        ForEach(report.files) { file in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.name)
                                Text(file.relativePath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Text(file.category.rawValue)
                                    if file.size == 0 {
                                        Text("0 bytes — incomplete")
                                            .foregroundStyle(.red)
                                    } else {
                                        Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                    }
                                }
                                .font(.caption2)
                            }
                        }
                    }
                }

                if let runtimeIndex {
                    Section("Tranzit Runtime") {
                        LabeledContent("Areas available", value: "\(runtimeIndex.availableAreas.count)")
                        LabeledContent("Containers", value: "\(runtimeIndex.containerFiles.count)")
                        LabeledContent("Audio banks", value: "\(runtimeIndex.audioBanks.count)")
                        LabeledContent("Asset references", value: "\(runtimeIndex.embeddedReferences.count)")
                        LabeledContent("Runtime ready", value: runtimeIndex.canEnterRuntime ? "Yes" : "No")

                        ForEach(runtimeIndex.availableAreas) { area in
                            Label(area.displayName, systemImage: "map")
                        }

                        if let runtimeSession {
                            LabeledContent("Loaded areas", value: "\(runtimeSession.areas.count)")
                            LabeledContent("Loaded bytes", value: ByteCountFormatter.string(fromByteCount: runtimeSession.totalLoadedBytes, countStyle: .file))
                        }

                        Button {
                            prepareRuntime()
                        } label: {
                            Label(runtimeSession == nil ? "Load Tranzit Runtime" : "Reload Tranzit Runtime", systemImage: "play.circle")
                        }
                    }
                }

                if let errorMessage {
                    Section("Error") { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Zombies Importer")
            .sheet(isPresented: $showingFolderPicker) {
                FolderPicker(
                    onPick: { url in
                        showingFolderPicker = false
                        beginFolderImport(url)
                    },
                    onCancel: {
                        showingFolderPicker = false
                    }
                )
            }
        }
    }

    private func beginFolderImport(_ folderURL: URL) {
        scanning = true
        errorMessage = nil
        report = nil
        runtimeIndex = nil
        runtimeSession = nil
        exportedReportURL = nil
        statusMessage = "Importing verified BO2 Zombies files for the native Tranzit runtime…"

        Task {
            do {
                let result = try await directFolderImporter.importFolder(folderURL)
                let reportURL = try ReportExporter.makeJSONFile(from: result.report)

                await MainActor.run {
                    report = result.report
                    runtimeIndex = TranzitRuntimeIndex(report: result.report)
                    exportedReportURL = reportURL
                    scanning = false

                    if let importedURL = result.importedAssetsURL {
                        let index = TranzitRuntimeIndex(report: result.report)
                        statusMessage = "Imported \(result.report.totalFiles) verified BO2 files into \(importedURL.lastPathComponent). Tranzit runtime index found \(index.availableAreas.count) area resource groups. Loading runtime resources now."
                    } else {
                        statusMessage = "No usable BO2 payload was persisted."
                    }
                }

                if result.importedAssetsURL != nil {
                    do {
                        let session = try await runtimeLoader.loadCurrent(report: result.report)
                        await MainActor.run {
                            runtimeSession = session
                            statusMessage = "Import complete. Tranzit runtime opened \(session.areas.count) area groups, \(session.sharedContainers.count) shared containers, and \(session.audioBanks.count) audio banks."
                        }
                    } catch {
                        await MainActor.run {
                            errorMessage = "Runtime load failed: \(error.localizedDescription)"
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    let nsError = error as NSError
                    errorMessage = """
                    Direct folder import failed: \(error.localizedDescription)
                    Domain: \(nsError.domain)
                    Code: \(nsError.code)
                    Folder: \(folderURL.lastPathComponent)
                    """
                    scanning = false
                    statusMessage = "Direct import failed."
                }
            }
        }
    }

    private func prepareRuntime() {
        guard let report else { return }
        scanning = true
        errorMessage = nil
        statusMessage = "Opening imported Tranzit containers and area resources…"

        Task {
            do {
                let session = try await runtimeLoader.loadCurrent(report: report)
                await MainActor.run {
                    runtimeSession = session
                    scanning = false
                    statusMessage = "Tranzit runtime loaded \(session.areas.count) area resource groups, \(session.sharedContainers.count) shared containers, and \(session.audioBanks.count) audio banks."
                }
            } catch {
                await MainActor.run {
                    runtimeSession = nil
                    scanning = false
                    errorMessage = "Runtime load failed: \(error.localizedDescription)"
                    statusMessage = "Imported files were kept, but the runtime loader found a resource problem."
                }
            }
        }
    }

    private func beginZipImport(_ zipURL: URL) {
        scanning = true
        errorMessage = nil
        report = nil
        exportedReportURL = nil
        statusMessage = "Received \(zipURL.lastPathComponent). Copying into ZombiesIOS…"

        Task {
            do {
                let localZip = try makeVerifiedLocalCopy(of: zipURL)

                let fm = FileManager.default
                let attrs = try fm.attributesOfItem(atPath: localZip.path)
                let byteSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                guard byteSize >= 4 else {
                    throw ImportError.invalidZip("The received file is empty or too small to be a ZIP archive.")
                }

                let handle = try FileHandle(forReadingFrom: localZip)
                defer { try? handle.close() }
                let header = try handle.read(upToCount: 4) ?? Data()
                let validSignatures: [[UInt8]] = [
                    [0x50, 0x4B, 0x03, 0x04],
                    [0x50, 0x4B, 0x05, 0x06],
                    [0x50, 0x4B, 0x07, 0x08]
                ]
                guard validSignatures.contains(Array(header)) else {
                    throw ImportError.invalidZip("The shared file has a .zip name but does not contain a valid ZIP header.")
                }

                await MainActor.run {
                    statusMessage = "Reading ZIP index (\(ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file))) and matching Zombies files…"
                }

                let newReport = try await scanner.scan(zipURL: localZip)
                let reportURL = try ReportExporter.makeJSONFile(from: newReport)
                let importedAssetsURL: URL?

                if newReport.isBuildReady {
                    importedAssetsURL = try extractVerifiedManifest(from: localZip, report: newReport)
                } else {
                    importedAssetsURL = nil
                }

                await MainActor.run {
                    report = newReport
                    exportedReportURL = reportURL
                    scanning = false

                    if newReport.isBuildReady {
                        if let importedAssetsURL {
                            statusMessage = "Import verified. All manifest files are present, non-empty, and copied locally to \(importedAssetsURL.lastPathComponent)."
                        } else {
                            statusMessage = "Import verified. All manifest files are present and non-empty."
                        }
                    } else if !newReport.zeroByteFiles.isEmpty {
                        statusMessage = "Import scanned, but \(newReport.zeroByteFiles.count) manifest file(s) contain 0 bytes. Re-copy those source files before building."
                    } else {
                        statusMessage = "Import scanned, but \(newReport.missingManifestCount) manifest file(s) are missing."
                    }
                }
            } catch {
                await MainActor.run {
                    let nsError = error as NSError
                    errorMessage = """
                    ZIP import failed: \(error.localizedDescription)
                    Domain: \(nsError.domain)
                    Code: \(nsError.code)
                    File: \(zipURL.lastPathComponent)
                    Source: \(zipURL.path)
                    """
                    scanning = false
                    statusMessage = "Import failed."
                }
            }
        }
    }

    private func makeVerifiedLocalCopy(of sourceURL: URL) throws -> URL {
        let fm = FileManager.default

        let imports = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Imports", isDirectory: true)

        try fm.createDirectory(at: imports, withIntermediateDirectories: true)
        try removeStaleImports(in: imports)

        let id = UUID().uuidString
        let partial = imports.appendingPathComponent("BO2-Zombies-\(id).partial")
        let destination = imports.appendingPathComponent("BO2-Zombies-\(id).zip")

        var coordinationError: NSError?
        var copyError: Error?
        var coordinatedSourceSize: Int64?

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: [.withoutChanges],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                if let attributes = try? fm.attributesOfItem(atPath: coordinatedURL.path),
                   let number = attributes[.size] as? NSNumber,
                   number.int64Value > 0 {
                    coordinatedSourceSize = number.int64Value
                }

                if fm.fileExists(atPath: partial.path) {
                    try fm.removeItem(at: partial)
                }

                try fm.copyItem(at: coordinatedURL, to: partial)

                let copiedAttributes = try fm.attributesOfItem(atPath: partial.path)
                let copiedSize = (copiedAttributes[.size] as? NSNumber)?.int64Value ?? 0

                guard copiedSize >= 4 else {
                    throw ImportError.copyFailed("The copied ZIP is empty or truncated.")
                }

                if let sourceSize = coordinatedSourceSize, sourceSize != copiedSize {
                    throw ImportError.copyFailed(
                        "The ZIP copy was incomplete (source \(sourceSize) bytes, local copy \(copiedSize) bytes)."
                    )
                }

                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.moveItem(at: partial, to: destination)
            } catch {
                copyError = error
            }
        }

        if fm.fileExists(atPath: partial.path) {
            try? fm.removeItem(at: partial)
        }

        if let copyError {
            throw copyError
        }
        if let coordinationError {
            throw coordinationError
        }

        guard fm.fileExists(atPath: destination.path) else {
            throw ImportError.copyFailed("iOS did not provide a readable local copy of the ZIP.")
        }

        // Opening with ZIPFoundation verifies that the central directory can
        // actually be parsed before the scanner spends time on the manifest.
        do {
            _ = try Archive(url: destination, accessMode: .read)
        } catch {
            try? fm.removeItem(at: destination)
            throw ImportError.invalidZip("The local ZIP copy is corrupt or its central directory is unreadable.")
        }

        return destination
    }

    private func extractVerifiedManifest(from zipURL: URL, report: ScanReport) throws -> URL {
        guard report.isBuildReady else {
            throw ImportError.copyFailed("BO2 Zombies payload extraction was blocked because the scan is incomplete.")
        }

        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = appSupport.appendingPathComponent("ImportedAssets", isDirectory: true)
        let staging = root.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        let current = root.appendingPathComponent("current", isDirectory: true)

        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            var extractedPaths = Set<String>()

            for entry in archive where entry.type == .file {
                guard BO2ZombiesManifest.contains(entry.path) else { continue }
                guard entry.uncompressedSize > 0 else {
                    throw ImportError.copyFailed("Refusing to extract zero-byte BO2 payload: \(entry.path)")
                }

                let normalized = entry.path.replacingOccurrences(of: "\\", with: "/")
                guard !normalized.hasPrefix("/"),
                      !normalized.split(separator: "/").contains("..") else {
                    throw ImportError.copyFailed("Unsafe ZIP path rejected: \(entry.path)")
                }

                let destination = staging.appendingPathComponent(normalized)
                try fm.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                _ = try archive.extract(entry, to: destination)

                let attributes = try fm.attributesOfItem(atPath: destination.path)
                let copiedSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                guard copiedSize == Int64(entry.uncompressedSize), copiedSize > 0 else {
                    throw ImportError.copyFailed(
                        "Extracted BO2 payload failed size verification: \(entry.path)"
                    )
                }
                extractedPaths.insert(normalized.lowercased())
            }

            let expectedPaths = Set(report.files.map {
                $0.relativePath.replacingOccurrences(of: "\\", with: "/").lowercased()
            })
            guard extractedPaths == expectedPaths else {
                throw ImportError.copyFailed(
                    "Extracted BO2 payload set does not match the verified scan report."
                )
            }

            if fm.fileExists(atPath: current.path) {
                try fm.removeItem(at: current)
            }
            try fm.moveItem(at: staging, to: current)
            return current
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    private func removeStaleImports(in imports: URL) throws {
        let fm = FileManager.default
        let oldFiles = try fm.contentsOfDirectory(
            at: imports,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for url in oldFiles where url.lastPathComponent.hasPrefix("BO2-Zombies-") {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate, modified < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    private enum ImportError: LocalizedError {
        case invalidZip(String)
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidZip(let message), .copyFailed(let message):
                return message
            }
        }
    }
}

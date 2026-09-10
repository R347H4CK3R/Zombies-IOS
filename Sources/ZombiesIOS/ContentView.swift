import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

struct ContentView: View {
    @State private var scanning = false
    @State private var report: ScanReport?
    @State private var exportedReportURL: URL?
    @State private var errorMessage: String?
    @State private var statusMessage = "Share a ZIP containing the BO2 Zombies files listed in the built-in manifest. The full PS3 dump is no longer required."

    private let scanner = PS3DumpScanner()
    private let expectedCount = BO2ZombiesManifest.relativePaths.count

    var body: some View {
        NavigationStack {
            List {
                Section("Import BO2 Zombies Data") {
                    Text(statusMessage)
                        .font(.callout)
                    Text("Keep the original PS3_GAME/USRDIR/english paths inside the ZIP. Extra files are ignored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if scanning {
                    Section { ProgressView("Scanning Zombies manifest files…") }
                }

                if let report {
                    Section("Manifest Match") {
                        LabeledContent("Found", value: "\(report.totalFiles) / \(expectedCount)")
                        LabeledContent("Known size", value: ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file))
                        LabeledContent("Zero-byte files", value: "\(report.zeroByteFiles.count)")
                        LabeledContent("Build ready", value: report.isBuildReady ? "Yes" : "No")

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

                if let errorMessage {
                    Section("Error") { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Zombies Importer")
            .onOpenURL { url in
                guard url.pathExtension.lowercased() == "zip" else {
                    errorMessage = "ZombiesIOS received an unsupported file. Share a ZIP containing the BO2 Zombies manifest files."
                    return
                }
                beginZipImport(url)
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

                await MainActor.run {
                    report = newReport
                    exportedReportURL = reportURL
                    scanning = false

                    if newReport.isBuildReady {
                        statusMessage = "Import verified. All manifest files are present and non-empty."
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

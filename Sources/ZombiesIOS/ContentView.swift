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

                        if report.totalFiles < expectedCount {
                            Text("\(expectedCount - report.totalFiles) manifest file(s) were not present in this ZIP.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let exportedReportURL {
                            ShareLink(item: exportedReportURL) {
                                Label("Export Filtered JSON Report", systemImage: "square.and.arrow.up")
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
                                        Text("size unknown")
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
                let localZip = try makeLocalCopy(of: zipURL)

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
                    statusMessage = "Import complete. Only files from the BO2 Zombies manifest were retained."
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

    private func makeLocalCopy(of sourceURL: URL) throws -> URL {
        let fm = FileManager.default

        let imports = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Imports", isDirectory: true)

        try fm.createDirectory(at: imports, withIntermediateDirectories: true)

        let destination = imports.appendingPathComponent("BO2-Zombies-\(UUID().uuidString).zip")
        var coordinationError: NSError?
        var copyError: Error?

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
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: coordinatedURL, to: destination)
            } catch {
                copyError = error
            }
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

        return destination
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

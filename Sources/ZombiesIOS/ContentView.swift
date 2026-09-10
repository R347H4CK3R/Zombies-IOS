import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

struct ContentView: View {
    @State private var scanning = false
    @State private var report: ScanReport?
    @State private var exportedReportURL: URL?
    @State private var errorMessage: String?
    @State private var statusMessage = "In Files, long-press PS3_GAME.zip → Share → ZombiesIOS, or tap the ZIP and choose ZombiesIOS."

    private let scanner = PS3DumpScanner()

    var body: some View {
        NavigationStack {
            List {
                Section("Import BO2 Data") {
                    Text(statusMessage)
                        .font(.callout)
                    Text("This build receives ZIP files directly from iOS and does not use the blue Open picker button.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if scanning {
                    Section { ProgressView("Importing and scanning…") }
                }

                if let report {
                    Section("Scan Summary") {
                        LabeledContent("Files", value: report.totalFiles.formatted())
                        LabeledContent("Zombies candidates", value: report.zombiesCandidates.count.formatted())
                        LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file))
                        if let exportedReportURL {
                            ShareLink(item: exportedReportURL) {
                                Label("Export JSON Report", systemImage: "square.and.arrow.up")
                            }
                        }
                    }

                    Section("Likely Zombies Content") {
                        ForEach(report.zombiesCandidates.prefix(200)) { file in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.name)
                                Text(file.relativePath).font(.caption).foregroundStyle(.secondary)
                                Text(file.category.rawValue).font(.caption2)
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
                    errorMessage = "ZombiesIOS received an unsupported file. Share PS3_GAME.zip."
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
        statusMessage = "Received \(zipURL.lastPathComponent). Preparing import…"

        Task {
            let accessed = zipURL.startAccessingSecurityScopedResource()
            defer { if accessed { zipURL.stopAccessingSecurityScopedResource() } }

            do {
                let fm = FileManager.default
                let base = fm.temporaryDirectory.appendingPathComponent("PS3Import-\(UUID().uuidString)", isDirectory: true)
                try fm.createDirectory(at: base, withIntermediateDirectories: true)
                let localZip = base.appendingPathComponent("PS3_GAME.zip")
                try fm.copyItem(at: zipURL, to: localZip)
                let attrs = try fm.attributesOfItem(atPath: localZip.path)
                let byteSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                guard byteSize >= 4 else {
                    throw ImportError.invalidZip("The received file is empty or too small to be a ZIP archive.")
                }

                let header = try Data(contentsOf: localZip, options: [.mappedIfSafe]).prefix(4)
                let validSignatures: [[UInt8]] = [
                    [0x50, 0x4B, 0x03, 0x04],
                    [0x50, 0x4B, 0x05, 0x06],
                    [0x50, 0x4B, 0x07, 0x08]
                ]
                guard validSignatures.contains(Array(header)) else {
                    throw ImportError.invalidZip("The shared file has a .zip name but does not contain a valid ZIP header.")
                }

                statusMessage = "Reading ZIP index (\(ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)))…"
                let newReport = try await scanner.scan(zipURL: localZip)
                let reportURL = try ReportExporter.makeJSONFile(from: newReport)
                await MainActor.run {
                    report = newReport
                    exportedReportURL = reportURL
                    scanning = false
                    statusMessage = "Import complete. Scanned ZIP contents without decompressing the archive."
                }
            } catch {
                await MainActor.run {
                    let nsError = error as NSError
                    errorMessage = """
                    ZIP import failed: \(error.localizedDescription)
                    Domain: \(nsError.domain)
                    Code: \(nsError.code)
                    File: \(zipURL.lastPathComponent)
                    """

                    scanning = false
                    statusMessage = "Import failed."
                }
            }
        }
    }

    private enum ImportError: LocalizedError {
        case invalidZip(String)

        var errorDescription: String? {
            switch self {
            case .invalidZip(let message): return message
            }
        }
    }

    private func findPS3GameRoot(in extracted: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: extracted.appendingPathComponent("PARAM.SFO").path),
           fm.fileExists(atPath: extracted.appendingPathComponent("USRDIR").path) { return extracted }

        if let e = fm.enumerator(at: extracted, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in e {
                if url.lastPathComponent.uppercased() == "PS3_GAME" { return url }
                if fm.fileExists(atPath: url.appendingPathComponent("PARAM.SFO").path),
                   fm.fileExists(atPath: url.appendingPathComponent("USRDIR").path) { return url }
            }
        }
        return nil
    }
}

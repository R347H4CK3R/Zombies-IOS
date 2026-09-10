import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

struct ContentView: View {
    @State private var showingFolderImporter = false
    @State private var showingZipImporter = false
    @State private var scanning = false
    @State private var report: ScanReport?
    @State private var exportedReportURL: URL?
    @State private var errorMessage: String?

    private let scanner = PS3DumpScanner()

    var body: some View {
        NavigationStack {
            List {
                Section("Choose BO2 Data") {
                    Button("Select PS3_GAME / USRDIR Folder") {
                        showingFolderImporter = true
                    }
                    .disabled(scanning)

                    Button("Import PS3_GAME ZIP (recommended)") {
                        showingZipImporter = true
                    }
                    .disabled(scanning)

                    Text("If the blue Open button does nothing on iOS, compress PS3_GAME in Files and import the ZIP instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if scanning {
                    Section {
                        ProgressView("Preparing and scanning…")
                    }
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
                                Text(file.relativePath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(file.category.rawValue)
                                    .font(.caption2)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Zombies Importer")
            .fileImporter(
                isPresented: $showingFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        errorMessage = "No folder was returned by the Files picker."
                        return
                    }
                    beginScan(url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showingZipImporter,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        errorMessage = "No ZIP file was selected."
                        return
                    }
                    beginZipImport(url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func beginZipImport(_ zipURL: URL) {
        scanning = true
        errorMessage = nil
        exportedReportURL = nil
        report = nil

        Task {
            let accessed = zipURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { zipURL.stopAccessingSecurityScopedResource() }
            }

            do {
                let fm = FileManager.default
                let base = fm.temporaryDirectory.appendingPathComponent("PS3Import-\(UUID().uuidString)", isDirectory: true)
                try fm.createDirectory(at: base, withIntermediateDirectories: true)

                let localZip = base.appendingPathComponent("PS3_GAME.zip")
                try fm.copyItem(at: zipURL, to: localZip)

                let extracted = base.appendingPathComponent("Extracted", isDirectory: true)
                try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
                try fm.unzipItem(at: localZip, to: extracted)

                let scanRoot = findPS3GameRoot(in: extracted) ?? extracted
                let newReport = try await scanner.scan(folderURL: scanRoot)
                let reportURL = try ReportExporter.makeJSONFile(from: newReport)

                await MainActor.run {
                    report = newReport
                    exportedReportURL = reportURL
                    scanning = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "ZIP import failed: \(error.localizedDescription)"
                    scanning = false
                }
            }
        }
    }

    private func findPS3GameRoot(in extracted: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: extracted.appendingPathComponent("PARAM.SFO").path),
           fm.fileExists(atPath: extracted.appendingPathComponent("USRDIR").path) {
            return extracted
        }

        if let e = fm.enumerator(at: extracted, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in e {
                if url.lastPathComponent.uppercased() == "PS3_GAME" {
                    return url
                }
                if fm.fileExists(atPath: url.appendingPathComponent("PARAM.SFO").path),
                   fm.fileExists(atPath: url.appendingPathComponent("USRDIR").path) {
                    return url
                }
            }
        }
        return nil
    }

    private func beginScan(_ folder: URL) {
        scanning = true
        errorMessage = nil
        exportedReportURL = nil
        report = nil

        Task {
            do {
                let newReport = try await scanner.scan(folderURL: folder)
                let reportURL = try ReportExporter.makeJSONFile(from: newReport)
                await MainActor.run {
                    report = newReport
                    exportedReportURL = reportURL
                    scanning = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Scan failed: \(error.localizedDescription)"
                    scanning = false
                }
            }
        }
    }
}

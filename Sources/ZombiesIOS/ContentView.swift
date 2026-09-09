import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var showingFolderPicker = false
    @State private var showingFileImporter = false
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
                        showingFolderPicker = true
                    }
                    .disabled(scanning)

                    Button("Select a File (diagnostic fallback)") {
                        showingFileImporter = true
                    }
                    .disabled(scanning)

                    Text("The folder button now uses Apple's native UIDocumentPicker directly instead of SwiftUI's folder importer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if scanning {
                    Section {
                        ProgressView("Scanning selected folder…")
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
            .sheet(isPresented: $showingFolderPicker) {
                FolderPicker(
                    onPick: { url in
                        showingFolderPicker = false
                        beginScan(url)
                    },
                    onCancel: {
                        showingFolderPicker = false
                    }
                )
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.data, .item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    errorMessage = "Selected file: \(url.lastPathComponent). Folder access is required for a full recursive scan."
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func beginScan(_ folder: URL) {
        scanning = true
        errorMessage = nil
        exportedReportURL = nil

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
                    errorMessage = String(describing: error)
                    scanning = false
                }
            }
        }
    }
}

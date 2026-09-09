import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum PickerMode {
        case folder
        case file
    }

    @State private var showingFolderImporter = false
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
                    Button("Select PS3_GAME or USRDIR Folder") {
                        showingFolderImporter = true
                    }
                    .disabled(scanning)

                    Button("Select Any File Inside USRDIR") {
                        showingFileImporter = true
                    }
                    .disabled(scanning)

                    Text("If iOS only lets you open the folder instead of selecting it, use the second button and choose any file inside USRDIR. The scanner will scan that file's parent folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if scanning {
                    Section {
                        ProgressView("Scanning On My iPhone / Files folder…")
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
                handleSelection(result, mode: .folder)
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.data, .item],
                allowsMultipleSelection: false
            ) { result in
                handleSelection(result, mode: .file)
            }
        }
    }

    private func handleSelection(_ result: Result<[URL], Error>, mode: PickerMode) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }

            let folderURL: URL
            switch mode {
            case .folder:
                folderURL = selectedURL
            case .file:
                folderURL = selectedURL.deletingLastPathComponent()
            }

            beginScan(folderURL)
        case .failure(let error):
            errorMessage = error.localizedDescription
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

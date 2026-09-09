import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var showingImporter = false
    @State private var scanning = false
    @State private var report: ScanReport?
    @State private var exportedReportURL: URL?
    @State private var errorMessage: String?

    private let scanner = PS3DumpScanner()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Select PS3_GAME or USRDIR Folder") {
                        showingImporter = true
                    }
                    .disabled(scanning)
                }

                if scanning {
                    Section {
                        ProgressView("Scanning USB / Files folder…")
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
                isPresented: $showingImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let folder = urls.first else { return }
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
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

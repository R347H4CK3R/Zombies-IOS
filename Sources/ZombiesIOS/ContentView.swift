import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var scanning = false
    @State private var report: ScanReport?
    @State private var runtimeIndex: TranzitRuntimeIndex?
    @State private var runtimeSession: TranzitRuntimeSession?
    @State private var errorMessage: String?
    @State private var showingFolderPicker = false
    @State private var rememberedFolderName: String?
    @State private var statusMessage = "Choose your BO2 game folder once. ZombiesIOS will remember it for future launches."

    private let directFolderImporter = DirectFolderImporter()
    private let runtimeLoader = TranzitRuntimeLoader()
    private let bookmarkKey = "BO2GameFolderBookmark"

    var body: some View {
        NavigationStack {
            List {
                Section("BO2 Game Folder") {
                    Text(statusMessage).font(.callout)
                    if let rememberedFolderName {
                        LabeledContent("Remembered", value: rememberedFolderName)
                    }
                    Button {
                        if !openRememberedFolder() { showingFolderPicker = true }
                    } label: {
                        Label(rememberedFolderName == nil ? "Choose BO2 Game Folder" : "Use Remembered Game Folder", systemImage: "folder.fill")
                    }
                    .disabled(scanning)

                    Button("Change Remembered Folder") { showingFolderPicker = true }
                        .disabled(scanning)
                }

                if scanning { Section { ProgressView("Loading BO2 runtime files…") } }

                if let report {
                    Section("Import Inventory") {
                        LabeledContent("Found", value: "\(report.totalFiles)")
                        LabeledContent("Known size", value: ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file))
                    }
                }

                if let runtimeIndex {
                    Section("Tranzit Runtime") {
                        LabeledContent("Areas available", value: "\(runtimeIndex.availableAreas.count)")
                        LabeledContent("Containers", value: "\(runtimeIndex.containerFiles.count)")
                        LabeledContent("Audio banks", value: "\(runtimeIndex.audioBanks.count)")
                        if let runtimeSession {
                            LabeledContent("Loaded areas", value: "\(runtimeSession.areas.count)")
                            LabeledContent("Loaded bytes", value: ByteCountFormatter.string(fromByteCount: runtimeSession.totalLoadedBytes, countStyle: .file))
                        }
                    }
                }

                if let errorMessage { Section("Error") { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("ZombiesIOS")
            .sheet(isPresented: $showingFolderPicker) {
                FolderPicker(onPick: { url in
                    showingFolderPicker = false
                    remember(folder: url)
                    beginFolderImport(url)
                }, onCancel: { showingFolderPicker = false })
            }
            .task { restoreRememberedFolderName() }
        }
    }

    private func remember(folder url: URL) {
        do {
            let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            rememberedFolderName = url.lastPathComponent
        } catch {
            errorMessage = "Could not remember the game folder: \(error.localizedDescription)"
        }
    }

    private func restoreRememberedFolderName() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
            rememberedFolderName = url.lastPathComponent
            if stale { remember(folder: url) }
        }
    }

    @discardableResult
    private func openRememberedFolder() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return false }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale { remember(folder: url) }
            rememberedFolderName = url.lastPathComponent
            beginFolderImport(url)
            return true
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            rememberedFolderName = nil
            statusMessage = "The saved folder permission expired. Choose the BO2 folder again once."
            return false
        }
    }

    private func beginFolderImport(_ folderURL: URL) {
        scanning = true
        errorMessage = nil
        report = nil
        runtimeIndex = nil
        runtimeSession = nil
        statusMessage = "Loading from remembered BO2 game folder…"

        Task {
            do {
                let result = try await directFolderImporter.importFolder(folderURL)
                let index = TranzitRuntimeIndex(report: result.report)
                let session = try await runtimeLoader.loadCurrent(report: result.report)
                await MainActor.run {
                    report = result.report
                    runtimeIndex = index
                    runtimeSession = session
                    scanning = false
                    statusMessage = "Game folder remembered. Tranzit runtime loaded \(session.areas.count) area groups."
                }
            } catch {
                await MainActor.run {
                    scanning = false
                    errorMessage = "BO2 load failed: \(error.localizedDescription)"
                    statusMessage = "The remembered folder is still saved; fix the source files or choose a different folder."
                }
            }
        }
    }
}

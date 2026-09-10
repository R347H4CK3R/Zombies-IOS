import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum ImportDialogKind { case loading, success, failure }

    @State private var scanning = false
    @State private var report: ScanReport?
    @State private var runtimeIndex: TranzitRuntimeIndex?
    @State private var runtimeSession: TranzitRuntimeSession?
    @State private var errorMessage: String?
    @State private var showingFolderPicker = false
    @State private var showingFilePicker = false
    @State private var rememberedFolderName: String?
    @State private var statusMessage = "Choose your BO2 game folder once. ZombiesIOS will remember it and read it in place without copying it into app storage."
    @State private var showingImportDialog = false
    @State private var importDialogTitle = ""
    @State private var importDialogMessage = ""
    @State private var importDialogKind: ImportDialogKind = .loading

    private let directFolderImporter = DirectFolderImporter()
    private let runtimeLoader = TranzitRuntimeLoader()
    private let bookmarkKey = "BO2GameFolderBookmark"

    var body: some View {
        NavigationStack {
            List {
                Section("BO2 Game Folder") {
                    Text(statusMessage).font(.callout)
                    if let rememberedFolderName { LabeledContent("Remembered", value: rememberedFolderName) }
                    Button {
                        if !openRememberedFolder() { showingFolderPicker = true }
                    } label: {
                        Label(rememberedFolderName == nil ? "Choose BO2 Game Folder" : "Use Remembered Game Folder", systemImage: "folder.fill")
                    }.disabled(scanning)
                    Button { showingFilePicker = true } label: { Label("Choose BO2 File Instead", systemImage: "doc.fill") }.disabled(scanning)
                    Text("The selected BO2 folder stays where it is. ZombiesIOS stores only the bookmark and small scan metadata; it does not copy the game folder into the app container. If iOS will not let you select a folder, choose a BO2 file such as EBOOT.BIN or common_zm.ff and ZombiesIOS will use that file's containing folder.")
                        .font(.caption).foregroundStyle(.secondary)
                    if rememberedFolderName != nil { Button("Change Remembered Folder") { showingFolderPicker = true }.disabled(scanning) }
                }

                if scanning { Section { ProgressView("Reading BO2 runtime files in place…") } }

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
                        if let area = runtimeIndex.firstPlayableArea, let file = runtimeIndex.firstPlayableFastFile {
                            LabeledContent("First playable target", value: area.displayName)
                            LabeledContent("Target payload", value: ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                            NavigationLink("Open Touch Gameplay Test") {
                                TranzitTouchGameplayView(area: area)
                            }
                        }
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
                    showingFolderPicker = false; remember(folder: url); beginFolderImport(url)
                }, onCancel: {
                    showingFolderPicker = false
                    showImportDialog(kind: .failure, title: "Folder Selection Cancelled", message: "No BO2 folder was selected.")
                })
            }
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let fileURL = urls.first else { showImportDialog(kind: .failure, title: "No File Selected", message: "Choose a BO2 file such as EBOOT.BIN or common_zm.ff."); return }
                    let folderURL = fileURL.deletingLastPathComponent(); remember(folder: folderURL); beginFolderImport(folderURL)
                case .failure(let error):
                    errorMessage = "BO2 file selection failed: \(error.localizedDescription)"
                    showImportDialog(kind: .failure, title: "File Selection Failed", message: error.localizedDescription)
                }
            }
            .alert(importDialogTitle, isPresented: $showingImportDialog) { Button("OK", role: .cancel) { } } message: { Text(importDialogMessage) }
            .task { restoreRememberedFolderName() }
        }
    }

    private func showImportDialog(kind: ImportDialogKind, title: String, message: String) {
        importDialogKind = kind; importDialogTitle = title; importDialogMessage = message; showingImportDialog = true
    }

    private func remember(folder url: URL) {
        let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey); rememberedFolderName = url.lastPathComponent; errorMessage = nil
        } catch { errorMessage = "The folder can be used now, but iOS could not save it for the next launch: \(error.localizedDescription)" }
    }

    private func restoreRememberedFolderName() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { rememberedFolderName = nil; return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            rememberedFolderName = url.lastPathComponent
            if stale {
                let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                UserDefaults.standard.set(try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: bookmarkKey)
            }
        } catch { clearRememberedFolder(message: "The saved folder could not be reopened. Choose the BO2 folder again once.") }
    }

    @discardableResult private func openRememberedFolder() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return false }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale {
                let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                UserDefaults.standard.set(try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: bookmarkKey)
            }
            rememberedFolderName = url.lastPathComponent; beginFolderImport(url); return true
        } catch {
            clearRememberedFolder(message: "The saved folder could not be reopened. Choose the BO2 folder again once.")
            showImportDialog(kind: .failure, title: "Saved Folder Unavailable", message: "The saved BO2 folder could not be reopened. Choose it again once."); return false
        }
    }

    private func clearRememberedFolder(message: String) { UserDefaults.standard.removeObject(forKey: bookmarkKey); rememberedFolderName = nil; statusMessage = message }

    private func beginFolderImport(_ folderURL: URL) {
        scanning = true; errorMessage = nil; report = nil; runtimeIndex = nil; runtimeSession = nil; statusMessage = "Reading BO2 runtime files directly from the selected folder…"
        showImportDialog(kind: .loading, title: "Loading BO2 Files", message: "Reading \(folderURL.lastPathComponent) in place. The game folder will not be copied into ZombiesIOS app storage.")
        Task {
            let accessed = folderURL.startAccessingSecurityScopedResource(); defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }
            do {
                guard FileManager.default.fileExists(atPath: folderURL.path) else { throw DirectFolderImporter.ImportError.cannotAccessFolder }
                let result = try await directFolderImporter.importFolder(folderURL)
                guard let sourceRoot = result.importedAssetsURL else { throw DirectFolderImporter.ImportError.cannotAccessFolder }
                let index = TranzitRuntimeIndex(report: result.report)
                let session = try await runtimeLoader.loadCurrent(report: result.report, rootURL: sourceRoot)
                await MainActor.run {
                    report = result.report; runtimeIndex = index; runtimeSession = session; scanning = false
                    let target = index.firstPlayableArea?.displayName ?? "none"
                    statusMessage = "Tranzit runtime loaded directly from the remembered folder. First playable target: \(target)."
                    showImportDialog(kind: .success, title: "BO2 Load Complete", message: "Found \(result.report.totalFiles) BO2 files and loaded \(session.areas.count) Tranzit area group(s) directly from the selected folder. No game files were copied into app storage. First playable target: \(target).")
                }
            } catch {
                await MainActor.run {
                    scanning = false; errorMessage = "BO2 load failed: \(error.localizedDescription)"; statusMessage = "Folder access failed. Choose PS3_GAME, USRDIR, english, or use Choose BO2 File Instead."
                    showImportDialog(kind: .failure, title: "BO2 Load Failed", message: "\(error.localizedDescription)\n\nTry selecting PS3_GAME, USRDIR, english, or choose a BO2 file instead.")
                }
            }
        }
    }
}

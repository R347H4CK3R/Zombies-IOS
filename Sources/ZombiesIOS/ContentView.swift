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
    @State private var activeScopedURL: URL?
    @State private var activeScopedAccess = false
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
                    Text("The selected BO2 folder stays where it is. ZombiesIOS stores only the bookmark and small scan metadata; it does not copy the game folder into the app container. You can also share/open a BO2 file from Files into ZombiesIOS and the app will use that file's containing folder.")
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
                        }
                        if let runtimeSession, let loadedArea = runtimeSession.areas.first {
                            LabeledContent("Loaded areas", value: "\(runtimeSession.areas.count)")
                            LabeledContent("Validated bytes", value: ByteCountFormatter.string(fromByteCount: runtimeSession.totalLoadedBytes, countStyle: .file))
                            LabeledContent("Folder stream", value: activeScopedAccess ? "Active" : "Unavailable")
                            NavigationLink("Open Native Touch Runtime") {
                                TranzitNativeGameplayView(
                                    loadedArea: loadedArea,
                                    rootURL: runtimeSession.rootURL,
                                    sharedContainers: runtimeSession.sharedContainers,
                                    audioBankCount: runtimeSession.audioBanks.count
                                )
                            }
                            .disabled(!activeScopedAccess)
                        }
                    }
                }

                if let errorMessage { Section("Error") { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("ZombiesIOS")
            .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let folderURL = urls.first else {
                        showImportDialog(kind: .failure, title: "No Folder Selected", message: "No BO2 folder was selected.")
                        return
                    }
                    handleSelectedFolder(folderURL)
                case .failure(let error):
                    errorMessage = "BO2 folder selection failed: \(error.localizedDescription)"
                    showImportDialog(kind: .failure, title: "Folder Selection Failed", message: error.localizedDescription)
                }
            }
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let fileURL = urls.first else {
                        showImportDialog(kind: .failure, title: "No File Selected", message: "Choose a BO2 file such as EBOOT.BIN or common_zm.ff.")
                        return
                    }
                    handleIncomingURL(fileURL)
                case .failure(let error):
                    errorMessage = "BO2 file selection failed: \(error.localizedDescription)"
                    showImportDialog(kind: .failure, title: "File Selection Failed", message: error.localizedDescription)
                }
            }
            .onOpenURL { url in handleIncomingURL(url) }
            .alert(importDialogTitle, isPresented: $showingImportDialog) { Button("OK", role: .cancel) { } } message: { Text(importDialogMessage) }
            .task { restoreRememberedFolderName() }
        }
    }

    private func showImportDialog(kind: ImportDialogKind, title: String, message: String) {
        importDialogKind = kind; importDialogTitle = title; importDialogMessage = message; showingImportDialog = true
    }

    private func handleSelectedFolder(_ url: URL) { remember(folder: url); beginFolderImport(url) }

    private func handleIncomingURL(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else {
            showImportDialog(kind: .failure, title: "Shared Item Unavailable", message: "ZombiesIOS received the item, but iOS did not provide a readable file or folder URL.")
            return
        }
        let folderURL = isDirectory.boolValue ? url : url.deletingLastPathComponent()
        remember(folder: folderURL); beginFolderImport(folderURL)
    }

    private func remember(folder url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey); rememberedFolderName = url.lastPathComponent; errorMessage = nil
        } catch {
            errorMessage = "The folder can be used now, but iOS could not save it for the next launch: \(error.localizedDescription)"
        }
    }

    private func restoreRememberedFolderName() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { rememberedFolderName = nil; return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            rememberedFolderName = url.lastPathComponent
            if stale {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
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
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                UserDefaults.standard.set(try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: bookmarkKey)
            }
            rememberedFolderName = url.lastPathComponent; beginFolderImport(url); return true
        } catch {
            clearRememberedFolder(message: "The saved folder could not be reopened. Choose it again once.")
            showImportDialog(kind: .failure, title: "Saved Folder Unavailable", message: "The saved BO2 folder could not be reopened. Choose it again once.")
            return false
        }
    }

    private func clearRememberedFolder(message: String) {
        releaseActiveFolderAccess(); UserDefaults.standard.removeObject(forKey: bookmarkKey); rememberedFolderName = nil; statusMessage = message
    }

    private func releaseActiveFolderAccess() {
        if activeScopedAccess, let activeScopedURL { activeScopedURL.stopAccessingSecurityScopedResource() }
        activeScopedURL = nil; activeScopedAccess = false
    }

    private func beginFolderImport(_ folderURL: URL) {
        releaseActiveFolderAccess(); scanning = true; errorMessage = nil; report = nil; runtimeIndex = nil; runtimeSession = nil
        statusMessage = "Reading BO2 runtime files directly from the selected folder…"
        showImportDialog(kind: .loading, title: "Loading BO2 Files", message: "Reading \(folderURL.lastPathComponent) in place. The game folder will not be copied into ZombiesIOS app storage.")

        let accessed = folderURL.startAccessingSecurityScopedResource(); activeScopedURL = accessed ? folderURL : nil; activeScopedAccess = accessed
        Task {
            do {
                guard FileManager.default.fileExists(atPath: folderURL.path) else { throw DirectFolderImporter.ImportError.cannotAccessFolder }
                let result = try await directFolderImporter.importFolder(folderURL)
                guard let sourceRoot = result.importedAssetsURL else { throw DirectFolderImporter.ImportError.cannotAccessFolder }
                let index = TranzitRuntimeIndex(report: result.report)
                let session = try await runtimeLoader.loadCurrent(report: result.report, rootURL: sourceRoot)
                await MainActor.run {
                    report = result.report; runtimeIndex = index; runtimeSession = session; scanning = false
                    let target = index.firstPlayableArea?.displayName ?? "none"
                    statusMessage = "Tranzit runtime is attached to the remembered folder. Native cache conversion will run automatically when needed. Spawn target: \(target)."
                    showImportDialog(kind: .success, title: "BO2 Load Complete", message: "Found \(result.report.totalFiles) BO2 files. Native Tranzit conversion will use the selected folder in place and store only converted cache data inside ZombiesIOS. No game files were copied into app storage.")
                }
            } catch {
                await MainActor.run {
                    releaseActiveFolderAccess(); scanning = false; errorMessage = "BO2 load failed: \(error.localizedDescription)"
                    statusMessage = "Folder access failed. Choose PS3_GAME, USRDIR, english, or use Choose BO2 File Instead."
                    showImportDialog(kind: .failure, title: "BO2 Load Failed", message: "\(error.localizedDescription)\n\nTry selecting PS3_GAME, USRDIR, english, or choose a BO2 file instead.")
                }
            }
        }
    }
}

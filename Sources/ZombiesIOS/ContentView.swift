import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
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
    @State private var statusMessage = "Choose your BO2 game folder once. The original dump stays external; converted gameplay assets are stored in Application Support."

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

                    Button { showingFilePicker = true } label: {
                        Label("Choose BO2 File Instead", systemImage: "doc.fill")
                    }
                    .disabled(scanning)

                    if rememberedFolderName != nil {
                        Button("Change Remembered Folder") { showingFolderPicker = true }
                            .disabled(scanning)
                    }

                    Text("The selected BO2 dump is read in place and is not copied into the app. Only converted Tranzit runtime assets are written to the app's Application Support directory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if scanning {
                    Section {
                        ProgressView("Reading BO2 source inventory…")
                    }
                }

                if let report {
                    Section("Source Inventory") {
                        LabeledContent("Files", value: "\(report.totalFiles)")
                        LabeledContent("Known size", value: ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file))
                    }
                }

                if let runtimeIndex, let runtimeSession, let loadedArea = runtimeSession.areas.first {
                    Section("Converted Tranzit") {
                        LabeledContent("Source areas", value: "\(runtimeIndex.availableAreas.count)")
                        LabeledContent("Source containers", value: "\(runtimeIndex.containerFiles.count)")
                        LabeledContent("Folder access", value: activeScopedAccess ? "Active" : "Unavailable")

                        NavigationLink("Convert / Open Tranzit") {
                            ConvertedTranzitImportView(
                                rootURL: runtimeSession.rootURL,
                                resources: conversionResources(area: loadedArea, session: runtimeSession)
                            )
                        }
                        .disabled(!activeScopedAccess)

                        Text("Gameplay opens only after the converted package is current and valid. A changed BO2 source fingerprint forces reconversion before gameplay.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("ZombiesIOS")
            .fileImporter(
                isPresented: $showingFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    remember(folder: url)
                    beginFolderImport(url)
                case .failure(let error):
                    errorMessage = "Folder selection failed: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    handleIncomingURL(url)
                case .failure(let error):
                    errorMessage = "File selection failed: \(error.localizedDescription)"
                }
            }
            .onOpenURL(perform: handleIncomingURL)
            .task { restoreRememberedFolderName() }
        }
    }

    private func conversionResources(
        area: TranzitLoadedArea,
        session: TranzitRuntimeSession
    ) -> [TranzitLoadedResource] {
        var resources = [area.fastFile]
        var seen = Set([area.fastFile.relativePath.lowercased()])
        for resource in session.sharedContainers where seen.insert(resource.relativePath.lowercased()).inserted {
            resources.append(resource)
        }
        return resources
    }

    private func handleIncomingURL(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            errorMessage = "The shared BO2 item is unavailable."
            return
        }
        let folder = isDirectory.boolValue ? url : url.deletingLastPathComponent()
        remember(folder: folder)
        beginFolderImport(folder)
    }

    private func remember(folder url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            rememberedFolderName = url.lastPathComponent
        } catch {
            errorMessage = "The folder works now, but iOS could not save it: \(error.localizedDescription)"
        }
    }

    private func restoreRememberedFolderName() {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            rememberedFolderName = url.lastPathComponent
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            rememberedFolderName = nil
        }
    }

    @discardableResult
    private func openRememberedFolder() -> Bool {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return false }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            rememberedFolderName = url.lastPathComponent
            beginFolderImport(url)
            return true
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            rememberedFolderName = nil
            errorMessage = "The remembered BO2 folder must be selected again."
            return false
        }
    }

    private func releaseActiveFolderAccess() {
        if activeScopedAccess, let activeScopedURL {
            activeScopedURL.stopAccessingSecurityScopedResource()
        }
        activeScopedURL = nil
        activeScopedAccess = false
    }

    private func beginFolderImport(_ folderURL: URL) {
        releaseActiveFolderAccess()
        scanning = true
        report = nil
        runtimeIndex = nil
        runtimeSession = nil
        errorMessage = nil
        statusMessage = "Reading BO2 source files in place…"

        let accessed = folderURL.startAccessingSecurityScopedResource()
        activeScopedURL = accessed ? folderURL : nil
        activeScopedAccess = accessed

        Task {
            do {
                guard FileManager.default.fileExists(atPath: folderURL.path) else {
                    throw DirectFolderImporter.ImportError.cannotAccessFolder
                }
                let result = try await directFolderImporter.importFolder(folderURL)
                guard let sourceRoot = result.importedAssetsURL else {
                    throw DirectFolderImporter.ImportError.cannotAccessFolder
                }
                let index = TranzitRuntimeIndex(report: result.report)
                let session = try await runtimeLoader.loadCurrent(report: result.report, rootURL: sourceRoot)

                await MainActor.run {
                    report = result.report
                    runtimeIndex = index
                    runtimeSession = session
                    scanning = false
                    statusMessage = "BO2 source attached. Open Tranzit to validate or build the converted Application Support package."
                }
            } catch {
                await MainActor.run {
                    releaseActiveFolderAccess()
                    scanning = false
                    errorMessage = "BO2 source load failed: \(error.localizedDescription)"
                    statusMessage = "Choose PS3_GAME, USRDIR, english, or a BO2 file again."
                }
            }
        }
    }
}

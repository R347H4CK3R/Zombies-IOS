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
                    Text(statusMessage)
                        .font(.callout)

                    if let rememberedFolderName {
                        LabeledContent("Remembered", value: rememberedFolderName)
                    }

                    Button {
                        if !openRememberedFolder() {
                            showingFolderPicker = true
                        }
                    } label: {
                        Label(
                            rememberedFolderName == nil ? "Choose BO2 Game Folder" : "Use Remembered Game Folder",
                            systemImage: "folder.fill"
                        )
                    }
                    .disabled(scanning)

                    if rememberedFolderName != nil {
                        Button("Change Remembered Folder") {
                            showingFolderPicker = true
                        }
                        .disabled(scanning)
                    }
                }

                if scanning {
                    Section {
                        ProgressView("Loading BO2 runtime files…")
                    }
                }

                if let report {
                    Section("Import Inventory") {
                        LabeledContent("Found", value: "\(report.totalFiles)")
                        LabeledContent(
                            "Known size",
                            value: ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file)
                        )
                    }
                }

                if let runtimeIndex {
                    Section("Tranzit Runtime") {
                        LabeledContent("Areas available", value: "\(runtimeIndex.availableAreas.count)")
                        LabeledContent("Containers", value: "\(runtimeIndex.containerFiles.count)")
                        LabeledContent("Audio banks", value: "\(runtimeIndex.audioBanks.count)")

                        if let runtimeSession {
                            LabeledContent("Loaded areas", value: "\(runtimeSession.areas.count)")
                            LabeledContent(
                                "Loaded bytes",
                                value: ByteCountFormatter.string(fromByteCount: runtimeSession.totalLoadedBytes, countStyle: .file)
                            )
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
            .navigationTitle("ZombiesIOS")
            .sheet(isPresented: $showingFolderPicker) {
                FolderPicker(
                    onPick: { url in
                        showingFolderPicker = false
                        remember(folder: url)
                        beginFolderImport(url)
                    },
                    onCancel: {
                        showingFolderPicker = false
                    }
                )
            }
            .task {
                restoreRememberedFolderName()
            }
        }
    }

    private func remember(folder url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            rememberedFolderName = url.lastPathComponent
            errorMessage = nil
        } catch {
            // A bookmark failure must not block the current import. The user can
            // still use the selected directory for this launch and choose it
            // again later if the provider does not support persistent bookmarks.
            errorMessage = "The folder can be used now, but iOS could not save it for the next launch: \(error.localizedDescription)"
        }
    }

    private func restoreRememberedFolderName() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            rememberedFolderName = nil
            return
        }

        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )

            rememberedFolderName = url.lastPathComponent

            if stale {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let refreshed = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
            }
        } catch {
            clearRememberedFolder(
                message: "The saved folder could not be reopened. Choose the BO2 folder again once."
            )
        }
    }

    @discardableResult
    private func openRememberedFolder() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return false
        }

        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )

            if stale {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let refreshed = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
            }

            rememberedFolderName = url.lastPathComponent
            beginFolderImport(url)
            return true
        } catch {
            clearRememberedFolder(
                message: "The saved folder could not be reopened. Choose the BO2 folder again once."
            )
            return false
        }
    }

    private func clearRememberedFolder(message: String) {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        rememberedFolderName = nil
        statusMessage = message
    }

    private func beginFolderImport(_ folderURL: URL) {
        scanning = true
        errorMessage = nil
        report = nil
        runtimeIndex = nil
        runtimeSession = nil
        statusMessage = "Loading BO2 runtime files…"

        Task {
            // Keep the picker/bookmark URL's security scope alive for the full
            // asynchronous scan and copy. startAccessing... returning false is
            // not itself a failure: sandbox/local URLs may not require a scope.
            let accessed = folderURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    folderURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                guard FileManager.default.fileExists(atPath: folderURL.path) else {
                    throw DirectFolderImporter.ImportError.cannotAccessFolder
                }

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
                    statusMessage = "Folder access failed. Choose PS3_GAME, USRDIR, english, or a parent folder that contains the BO2 dump."
                }
            }
        }
    }
}

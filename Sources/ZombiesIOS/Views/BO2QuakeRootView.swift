import SwiftUI
import UniformTypeIdentifiers

struct BO2QuakeRootView: View {
    @State private var showingFolderPicker = false
    @State private var loading = false
    @State private var status = "Select your BO2 PS3 game folder. Hijacked will be decoded locally and loaded into the native Quake runtime."
    @State private var session: BO2MapRuntimeSession?
    @State private var scopedURL: URL?
    @State private var scopedAccess = false

    private let importer = DirectFolderImporter()
    private let loader = BO2MapRuntimeLoader()

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("BO2 Quake iOS")
                    .font(.largeTitle.bold())
                Text("Native iOS runtime • no PS3 emulator")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(status).multilineTextAlignment(.center).padding(.horizontal)

                if loading { ProgressView("Decoding Hijacked…") }

                Button {
                    showingFolderPicker = true
                } label: {
                    Label("Choose BO2 PS3 Folder", systemImage: "folder.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(loading)

                if let session {
                    VStack(spacing: 8) {
                        LabeledContent("Map", value: session.target.displayName)
                        LabeledContent("Vertices", value: "\(session.package.vertices.count)")
                        LabeledContent("Triangles", value: "\(session.package.indices.count / 3)")
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

                    NavigationLink("Play Hijacked") {
                        QuakeGameplayView(package: session.package)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!scopedAccess)
                }

                Spacer()
                Text("Retail BO2 assets are read from your selected folder and converted into the app cache. The original game folder is not copied into the app container.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("BO2 Quake")
            .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { loadHijacked(from: url) }
                case .failure(let error):
                    status = "Folder selection failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadHijacked(from folderURL: URL) {
        releaseAccess()
        loading = true
        session = nil
        status = "Scanning BO2 files and decoding mp_hijacked.ff…"
        let accessed = folderURL.startAccessingSecurityScopedResource()
        scopedURL = accessed ? folderURL : nil
        scopedAccess = accessed

        Task {
            do {
                let imported = try await importer.importFolder(folderURL)
                guard let root = imported.importedAssetsURL else {
                    throw BO2MapRuntimeLoader.LoaderError.unreadableFastFile(folderURL.lastPathComponent)
                }
                let loaded = try await loader.load(target: .hijacked, report: imported.report, rootURL: root)
                await MainActor.run {
                    session = loaded
                    loading = false
                    status = "Hijacked converted successfully. Launching uses the native Quake/Metal runtime."
                }
            } catch {
                await MainActor.run {
                    loading = false
                    status = "Hijacked conversion failed: \(error.localizedDescription)"
                    releaseAccess()
                }
            }
        }
    }

    private func releaseAccess() {
        if scopedAccess, let scopedURL { scopedURL.stopAccessingSecurityScopedResource() }
        scopedURL = nil
        scopedAccess = false
    }
}

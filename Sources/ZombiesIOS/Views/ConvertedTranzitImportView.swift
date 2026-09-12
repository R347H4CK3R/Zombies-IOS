import SwiftUI

struct ConvertedTranzitImportView: View {
    let rootURL: URL
    let resources: [TranzitLoadedResource]

    @State private var stage: ConvertedImportStage = .scanning
    @State private var message = "Checking converted Tranzit package…"
    @State private var lastError: String?
    @State private var package: ConvertedRuntimePackage?
    @State private var sourceFingerprint: ConvertedSourceFingerprint?
    @State private var running = false

    private let importer = ConvertedTranzitImporter()
    private let loader = ConvertedTranzitLoader()

    var body: some View {
        Group {
            if let package {
                TranzitTouchGameplayView(package: package)
            } else {
                VStack(spacing: 18) {
                    Spacer()
                    ProgressView()
                        .controlSize(.large)
                    Text(stageTitle)
                        .font(.headline.monospaced())
                    Text(message)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    if let lastError {
                        Text(lastError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                        Button("Retry Conversion") {
                            Task { await preparePackage(forceRetry: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(running)
                    }
                    Spacer()
                }
            }
        }
        .navigationTitle(package == nil ? "Preparing Tranzit" : "Tranzit")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if package == nil { await preparePackage(forceRetry: false) }
        }
    }

    private var stageTitle: String {
        switch stage {
        case .scanning: return "SCANNING SOURCE"
        case .decodingWorld: return "DECODING WORLD"
        case .convertingGeometry: return "CONVERTING GEOMETRY"
        case .convertingTextures: return "CONVERTING MATERIALS"
        case .buildingCollision: return "BUILDING COLLISION"
        case .convertingWeapon: return "CONVERTING WEAPON"
        case .validating: return "VALIDATING PACKAGE"
        case .ready: return "READY"
        }
    }

    @MainActor
    private func preparePackage(forceRetry: Bool) async {
        guard !running else { return }
        running = true
        lastError = nil
        stage = .scanning
        message = forceRetry ? "Retrying conversion…" : "Checking source fingerprint and converted package…"

        do {
            let sourceURLs = resources.map { rootURL.appendingPathComponent($0.relativePath, isDirectory: false) }
            sourceFingerprint = try ConvertedSourceFingerprint.make(for: sourceURLs, relativeTo: rootURL)

            let manifest = try await importer.run(rootURL: rootURL, resources: resources) { newStage, newMessage in
                Task { @MainActor in
                    stage = newStage
                    message = newMessage
                }
            }
            guard sourceFingerprint == manifest.sourceFingerprint else {
                throw ConversionRouteError.staleSourceFingerprint
            }

            let loaded = try loader.load()
            guard loaded.sourceFingerprint == sourceFingerprint else {
                throw ConversionRouteError.staleSourceFingerprint
            }
            stage = .ready
            message = "Converted Tranzit package loaded from Application Support."
            package = loaded
        } catch {
            lastError = "\(stageTitle): \(error.localizedDescription)"
            message = "Conversion stopped. The previous valid package, if any, was left untouched."
        }
        running = false
    }

    private enum ConversionRouteError: LocalizedError {
        case staleSourceFingerprint

        var errorDescription: String? {
            "The BO2 source files changed after conversion. Tranzit must be reconverted before gameplay."
        }
    }
}

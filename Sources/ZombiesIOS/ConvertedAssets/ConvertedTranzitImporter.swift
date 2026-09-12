import Foundation

actor ConvertedTranzitImporter {
    typealias Progress = @Sendable (ConvertedImportStage, String) -> Void

    enum ImportError: LocalizedError {
        case missingSourceFiles
        case weaponResolutionFailed
        case activePackageMissingAfterPromotion

        var errorDescription: String? {
            switch self {
            case .missingSourceFiles:
                return "No source FastFiles were available for Tranzit conversion."
            case .weaponResolutionFailed:
                return "A BO2 weapon asset could not be resolved from the decoded Tranzit source; no placeholder weapon was substituted."
            case .activePackageMissingAfterPromotion:
                return "Converted package promotion completed without a valid active manifest."
            }
        }
    }

    private let store: ConvertedPackageStore

    init(store: ConvertedPackageStore = .init()) {
        self.store = store
    }

    func run(
        rootURL: URL,
        resources: [TranzitLoadedResource],
        progress: @escaping Progress = { _, _ in }
    ) async throws -> ConvertedTranzitManifest {
        guard !resources.isEmpty else { throw ImportError.missingSourceFiles }

        progress(.scanning, "Scanning selected BO2 source files")
        let sourceURLs = resources.map { rootURL.appendingPathComponent($0.relativePath, isDirectory: false) }
        let fingerprint = try ConvertedSourceFingerprint.make(for: sourceURLs, relativeTo: rootURL)

        if let active = store.activeManifest(), active.sourceFingerprint == fingerprint {
            progress(.ready, "Converted Tranzit package is current")
            return active
        }

        let stagingURL = try prepareStaging(for: fingerprint)
        var state = loadStagingState(at: stagingURL, fingerprint: fingerprint)
            ?? ConvertedStagingState(sourceFingerprint: fingerprint, completedStages: [])
        var report = ConvertedImportReport(
            sourceFingerprint: fingerprint,
            completedStages: state.completedStages,
            stageMessages: [:],
            worldSourceFile: nil,
            worldVertexCount: nil,
            worldIndexCount: nil,
            convertedTextureCount: 0,
            materialFullFidelity: false,
            weaponSourceName: nil,
            lastError: nil,
            updatedAt: Date()
        )

        do {
            mark(.scanning, message: "Source fingerprint captured", state: &state, report: &report, stagingURL: stagingURL, progress: progress)

            progress(.decodingWorld, "Decoding Tranzit world containers")
            let worldResult = try await ConvertedWorldImporter().convert(
                rootURL: rootURL,
                resources: resources,
                stagingURL: stagingURL
            ) { message in
                progress(.decodingWorld, message)
            }
            report.worldSourceFile = worldResult.selectedSourceFile
            report.worldVertexCount = worldResult.vertexCount
            report.worldIndexCount = worldResult.indexCount
            report.stageMessages[ConvertedImportStage.decodingWorld.rawValue] = "\(worldResult.decodedChunkCount) chunks / \(worldResult.decodedBytes) bytes from \(worldResult.selectedSourceFile)"
            mark(.decodingWorld, message: "World payload decoded", state: &state, report: &report, stagingURL: stagingURL, progress: progress)
            mark(.convertingGeometry, message: "Native world mesh written", state: &state, report: &report, stagingURL: stagingURL, progress: progress)

            progress(.convertingTextures, "Converting phase-one material textures")
            let materialSources = try discoverMaterialSources(rootURL: rootURL)
            let materialInput: [ConvertedMaterialSource]
            if materialSources.isEmpty {
                materialInput = [ConvertedMaterialSource(
                    id: 0,
                    name: "tranzit_world_unresolved",
                    encodedImageData: nil,
                    doubleSided: true
                )]
            } else {
                materialInput = materialSources
            }
            let materialResult = try ConvertedMaterialImporter().convert(
                sources: materialInput,
                stagingURL: stagingURL
            )
            report.convertedTextureCount = materialResult.manifest.convertedTextureCount
            report.materialFullFidelity = materialResult.manifest.fullFidelity
            mark(
                .convertingTextures,
                message: materialResult.manifest.fullFidelity
                    ? "Material textures converted"
                    : "Material conversion completed with explicit fallback diagnostics",
                state: &state,
                report: &report,
                stagingURL: stagingURL,
                progress: progress
            )

            progress(.buildingCollision, "Building converted collision mesh")
            let worldURL = stagingURL.appendingPathComponent(worldResult.meshPath, isDirectory: false)
            let collisionResult = try ConvertedCollisionImporter().convert(
                worldMeshURL: worldURL,
                stagingURL: stagingURL
            )
            mark(.buildingCollision, message: "Collision \(collisionResult.indexCount / 3) triangles", state: &state, report: &report, stagingURL: stagingURL, progress: progress)

            progress(.convertingWeapon, "Resolving one real BO2 weapon model")
            guard let weaponSource = try await resolveWeaponSource(rootURL: rootURL, resources: resources) else {
                throw ImportError.weaponResolutionFailed
            }
            let weaponResult = try ConvertedWeaponImporter().convert(
                sourceMesh: weaponSource.mesh,
                sourceName: weaponSource.name,
                material: materialResult.manifest.materials.first,
                stagingURL: stagingURL
            )
            report.weaponSourceName = weaponSource.name
            mark(.convertingWeapon, message: "Weapon \(weaponResult.vertexCount)V / \(weaponResult.indexCount / 3)T", state: &state, report: &report, stagingURL: stagingURL, progress: progress)

            progress(.validating, "Validating converted package")
            let manifest = ConvertedTranzitManifest(
                formatVersion: ConvertedTranzitManifest.packageFormatVersion,
                sourceFingerprint: fingerprint,
                sourceAreaName: "Tranzit",
                createdAt: Date(),
                converterBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development",
                worldMeshPath: worldResult.meshPath,
                collisionMeshPath: collisionResult.meshPath,
                materialManifestPath: materialResult.manifestPath,
                weaponMeshPath: weaponResult.meshPath,
                convertedTextureCount: materialResult.manifest.convertedTextureCount,
                vertexCount: worldResult.vertexCount,
                indexCount: worldResult.indexCount,
                worldBoundsMin: ConvertedFloat3(worldResult.boundsMin),
                worldBoundsMax: ConvertedFloat3(worldResult.boundsMax),
                complete: true,
                stageDiagnostics: [
                    "worldSource": worldResult.selectedSourceFile,
                    "worldByteOrder": worldResult.byteOrder,
                    "boundsFallbackUsed": String(worldResult.boundsFallbackUsed),
                    "materialFullFidelity": String(materialResult.manifest.fullFidelity),
                    "weaponSource": weaponSource.name
                ]
            )

            try writeManifestLast(manifest, at: stagingURL)
            _ = try ConvertedPackageValidator.validate(at: stagingURL)
            mark(.validating, message: "Converted package validated", state: &state, report: &report, stagingURL: stagingURL, progress: progress)
            try writeImportReport(report, at: stagingURL)
            try store.promoteStaging()

            guard let active = store.activeManifest() else {
                throw ImportError.activePackageMissingAfterPromotion
            }
            progress(.ready, "Converted Tranzit package ready")
            return active
        } catch {
            report.lastError = error.localizedDescription
            report.updatedAt = Date()
            try? writeImportReport(report, at: stagingURL)
            throw error
        }
    }

    private struct WeaponSource {
        let name: String
        let mesh: T6RuntimeMesh
    }

    private func resolveWeaponSource(
        rootURL: URL,
        resources: [TranzitLoadedResource]
    ) async throws -> WeaponSource? {
        let decoder = T6PS3PayloadDecoder()
        let preferred = resources.filter { $0.fileName.lowercased().hasSuffix(".ff") }.sorted {
            weaponPriority($0.fileName) < weaponPriority($1.fileName)
        }

        for resource in preferred.prefix(8) {
            guard let report = try? await decoder.decodePrefix(
                rootURL: rootURL,
                resource: resource,
                maxDecodedBytes: 32 * 1024 * 1024,
                maxChunks: 1024
            ) else { continue }

            let probe = T6ZoneAssetProbe.analyze(report.payloadPrefix, maxSamples: 32)
            guard let weaponName = probe.sampleNames.first(where: { looksLikeWeaponName($0) }) else {
                continue
            }
            guard let mesh = T6MeshPreviewExtractor.extract(
                from: report.payloadPrefix,
                scanLimit: report.payloadPrefix.count
            ) else { continue }
            return WeaponSource(name: weaponName, mesh: mesh)
        }
        return nil
    }

    private func looksLikeWeaponName(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("weapon") || lower.contains("viewmodel") || lower.contains("gun") || lower.contains("pistol")
    }

    private func weaponPriority(_ name: String) -> Int {
        let lower = name.lowercased()
        if lower == "common_zm.ff" { return 0 }
        if lower == "zm_transit.ff" { return 1 }
        if lower.contains("zm_transit") { return 2 }
        return 3
    }

    private func discoverMaterialSources(rootURL: URL) throws -> [ConvertedMaterialSource] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [ConvertedMaterialSource] = []
        var nextID = 0
        for case let url as URL in enumerator {
            if result.count >= 64 { break }
            let ext = url.pathExtension.lowercased()
            guard ["png", "jpg", "jpeg"].contains(ext) else { continue }
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            result.append(.init(
                id: nextID,
                name: url.deletingPathExtension().lastPathComponent,
                encodedImageData: data,
                doubleSided: false
            ))
            nextID += 1
        }
        return result
    }

    private func prepareStaging(for fingerprint: ConvertedSourceFingerprint) throws -> URL {
        let staging = ConvertedTranzitPaths.stagingRoot
        if let existing = loadStagingState(at: staging, fingerprint: fingerprint),
           existing.sourceFingerprint == fingerprint {
            return staging
        }
        return try store.beginStaging()
    }

    private func loadStagingState(
        at stagingURL: URL,
        fingerprint: ConvertedSourceFingerprint
    ) -> ConvertedStagingState? {
        let url = stagingURL.appendingPathComponent(ConvertedStagingState.fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(ConvertedStagingState.self, from: data),
              state.sourceFingerprint == fingerprint else { return nil }
        return state
    }

    private func mark(
        _ stage: ConvertedImportStage,
        message: String,
        state: inout ConvertedStagingState,
        report: inout ConvertedImportReport,
        stagingURL: URL,
        progress: Progress
    ) {
        if !state.completedStages.contains(stage) { state.completedStages.append(stage) }
        if !report.completedStages.contains(stage) { report.completedStages.append(stage) }
        report.stageMessages[stage.rawValue] = message
        report.updatedAt = Date()
        progress(stage, message)
        try? persistState(state, at: stagingURL)
        try? writeImportReport(report, at: stagingURL)
    }

    private func persistState(_ state: ConvertedStagingState, at stagingURL: URL) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(
            to: stagingURL.appendingPathComponent(ConvertedStagingState.fileName, isDirectory: false),
            options: .atomic
        )
    }

    private func writeManifestLast(_ manifest: ConvertedTranzitManifest, at stagingURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(
            to: stagingURL.appendingPathComponent("manifest.json", isDirectory: false),
            options: .atomic
        )
    }

    private func writeImportReport(_ report: ConvertedImportReport, at root: URL) throws {
        let target = root.appendingPathComponent(ConvertedImportReport.relativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: target, options: .atomic)
    }
}

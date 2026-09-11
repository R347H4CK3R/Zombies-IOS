import Foundation

enum TranzitImportStage: String, Sendable {
    case sourceCheck
    case decodingFastFile
    case resolvingXAssets
    case convertingWorld
    case convertingMaterials
    case convertingTextures
    case validatingCache
    case cacheReady
}

struct TranzitImportProgress: Sendable {
    let stage: TranzitImportStage
    let detail: String
}

actor TranzitNativeImporter {
    enum ImportError: LocalizedError {
        case noFastFile
        case noAssetIndex
        case validationFailed([String])

        var errorDescription: String? {
            switch self {
            case .noFastFile: return "No usable Tranzit FastFile is available for native conversion."
            case .noAssetIndex: return "Decoded T6 payload did not contain a valid XAsset index."
            case .validationFailed(let errors): return "Native cache validation failed: " + errors.joined(separator: "; ")
            }
        }
    }

    private let cache: TranzitCacheManager

    init(applicationSupportRoot: URL? = nil) throws {
        cache = try TranzitCacheManager(applicationSupportRoot: applicationSupportRoot)
    }

    func loadOrRebuild(
        rootURL: URL,
        resources: [TranzitLoadedResource],
        progress: @Sendable (TranzitImportProgress) -> Void
    ) async throws -> TranzitCachedWorld {
        progress(.init(stage: .sourceCheck, detail: "Checking BO2 source fingerprint"))
        let fingerprints = try await cache.sourceFingerprints(rootURL: rootURL, resources: resources)

        if let manifest = try await cache.loadValidManifest(for: fingerprints) {
            let world = try await loadActiveWorld()
            progress(.init(stage: .cacheReady, detail: statusLine(manifest)))
            return world
        }

        do {
            let paths = try await cache.prepareStaging()
            guard let resource = selectWorldResource(resources) else { throw ImportError.noFastFile }

            progress(.init(stage: .decodingFastFile, detail: "Decoding \(resource.fileName)"))
            let decoder = T6PS3PayloadDecoder()
            let decoded = try await decoder.decodePrefix(
                rootURL: rootURL,
                resource: resource,
                maxDecodedBytes: 160 * 1024 * 1024,
                maxChunks: 8192
            )
            let payload = decoded.payloadPrefix

            progress(.init(stage: .resolvingXAssets, detail: "Resolving typed T6 XAsset index"))
            guard let assets = T6AssetResolver.resolveIndex(in: payload) else { throw ImportError.noAssetIndex }

            progress(.init(stage: .convertingWorld, detail: "Converting GfxWorld surfaces"))
            let geometry = try T6WorldConverter.convert(payload: payload, assets: assets)

            progress(.init(stage: .convertingMaterials, detail: "Converting \(assets.all(.material).count) materials"))
            let materialResult = T6MaterialConverter.convert(payload: payload, assets: assets)
            let materials = materialResult.materials

            progress(.init(stage: .convertingTextures, detail: "Converting \(assets.all(.gfxImage).count) images"))
            let textureReport = try T6TextureConverter.convert(payload: payload, assets: assets, destination: paths.stagingTextures)

            let world = TranzitCachedWorld(
                positions: geometry.positions,
                normals: geometry.normals,
                uvs: geometry.uvs,
                indices: geometry.indices,
                submeshes: geometry.submeshes.map { submesh in
                    let validID = materials.contains(where: { $0.id == submesh.materialID }) ? submesh.materialID : (materials.first?.id ?? 0)
                    return TranzitCachedSubmesh(firstIndex: submesh.firstIndex, indexCount: submesh.indexCount, materialID: validID)
                },
                materials: materials
            )

            try TranzitMeshBinary.write(world: world, to: paths.stagingMesh)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(materials).write(to: paths.stagingMaterials, options: .atomic)

            let warnings = geometry.warnings + materialResult.warnings + textureReport.warnings
            let stagingManifest = TranzitCacheManifest(
                schemaVersion: TranzitCacheManifest.currentSchemaVersion,
                sourceFingerprints: fingerprints,
                surfaceCount: world.submeshes.count,
                vertexCount: world.positions.count,
                triangleCount: world.triangleCount,
                materialCount: materials.count,
                textureTotal: textureReport.total,
                textureSucceeded: textureReport.succeeded,
                textureFailed: textureReport.failed,
                warnings: warnings,
                validationState: .staging
            )
            try encoder.encode(stagingManifest).write(to: paths.stagingManifest, options: .atomic)

            progress(.init(stage: .validatingCache, detail: "Validating native mesh/material/texture cache"))
            let validation = TranzitCacheValidator.validate(paths: paths)
            guard validation.isValid else { throw ImportError.validationFailed(validation.errors) }

            let validManifest = TranzitCacheManifest(
                schemaVersion: stagingManifest.schemaVersion,
                sourceFingerprints: stagingManifest.sourceFingerprints,
                surfaceCount: stagingManifest.surfaceCount,
                vertexCount: stagingManifest.vertexCount,
                triangleCount: stagingManifest.triangleCount,
                materialCount: stagingManifest.materialCount,
                textureTotal: stagingManifest.textureTotal,
                textureSucceeded: stagingManifest.textureSucceeded,
                textureFailed: stagingManifest.textureFailed,
                warnings: Array(Set(stagingManifest.warnings + validation.warnings)).sorted(),
                validationState: .valid
            )
            try encoder.encode(validManifest).write(to: paths.stagingManifest, options: .atomic)
            try await cache.promoteStaging()
            progress(.init(stage: .cacheReady, detail: statusLine(validManifest)))
            return world
        } catch {
            await cache.discardStaging()
            // A failed rebuild must never destroy a previously working cache.
            if let old = try? await loadActiveWorld() {
                progress(.init(stage: .cacheReady, detail: "REBUILD FAILED / USING PREVIOUS CACHE — \(error.localizedDescription)"))
                return old
            }
            throw error
        }
    }

    private func loadActiveWorld() async throws -> TranzitCachedWorld {
        let paths = await cache.paths
        let materialData = try Data(contentsOf: paths.activeMaterials)
        let materials = try JSONDecoder().decode([TranzitCachedMaterial].self, from: materialData)
        return try TranzitMeshBinary.read(from: paths.activeMesh, materials: materials)
    }

    private func selectWorldResource(_ resources: [TranzitLoadedResource]) -> TranzitLoadedResource? {
        let fastFiles = resources.filter { $0.fileName.lowercased().hasSuffix(".ff") }
        return fastFiles.first(where: { $0.fileName.lowercased() == "zm_transit.ff" })
            ?? fastFiles.max(by: { $0.byteCount < $1.byteCount })
    }

    private func statusLine(_ manifest: TranzitCacheManifest) -> String {
        "CACHE READY — \(manifest.surfaceCount)S \(manifest.vertexCount)V \(manifest.triangleCount)T \(manifest.materialCount)M \(manifest.textureSucceeded)/\(manifest.textureTotal) TEX"
    }
}

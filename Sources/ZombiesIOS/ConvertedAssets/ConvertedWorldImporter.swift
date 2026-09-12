import Foundation

struct ConvertedWorldResult {
    let meshPath: String
    let vertexCount: Int
    let indexCount: Int
    let boundsMin: SIMD3<Float>
    let boundsMax: SIMD3<Float>
    let selectedSourceFile: String
    let decodedBytes: UInt64
    let decodedChunkCount: Int
    let vertexOffset: Int
    let indexOffset: Int
    let byteOrder: String
    let boundsFallbackUsed: Bool
}

enum ConvertedWorldImportError: LocalizedError {
    case noCandidates
    case decodeFailed(String)
    case noWorldMesh(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noCandidates:
            return "No Tranzit FastFile candidates were available for world conversion."
        case .decodeFailed(let source):
            return "T6 decode failed for every candidate; last source: \(source)."
        case .noWorldMesh(let source):
            return "No valid GfxWorld mesh could be reconstructed from \(source)."
        case .writeFailed(let reason):
            return "Converted world mesh could not be written: \(reason)"
        }
    }
}

struct ConvertedWorldImporter {
    typealias Progress = @Sendable (String) -> Void

    func convert(
        rootURL: URL,
        resources: [TranzitLoadedResource],
        stagingURL: URL,
        progress: @escaping Progress = { _ in }
    ) async throws -> ConvertedWorldResult {
        let candidates = orderedCandidates(resources)
        guard !candidates.isEmpty else { throw ConvertedWorldImportError.noCandidates }

        let decoder = T6PS3PayloadDecoder()
        var best: (resource: TranzitLoadedResource, report: T6DecodedPayloadReport, mesh: T6RuntimeMesh, fallback: Bool)?
        var lastSource = candidates[0].fileName

        for resource in candidates.prefix(8) {
            lastSource = resource.fileName
            progress("Decoding \(resource.fileName)")
            do {
                let isMain = resource.fileName.lowercased() == "zm_transit.ff"
                let report = try await decoder.decodePrefix(
                    rootURL: rootURL,
                    resource: resource,
                    maxDecodedBytes: isMain ? 128 * 1024 * 1024 : 48 * 1024 * 1024,
                    maxChunks: isMain ? 4096 : 2048
                )

                progress("Extracting GfxWorld from \(resource.fileName)")
                let payload = report.payloadPrefix
                let extracted = await Task.detached(priority: .userInitiated) { () -> (T6RuntimeMesh?, Bool) in
                    if let packed = T6GfxSurfaceMeshExtractor.extract(from: payload, scanLimit: payload.count) {
                        return (packed, false)
                    }
                    return (
                        T6GfxBoundsFallbackExtractor.extract(from: payload, scanLimit: payload.count),
                        true
                    )
                }.value

                guard let mesh = extracted.0 else { continue }
                if best == nil || score(resource: resource, mesh: mesh, fallback: extracted.1) > score(resource: best!.resource, mesh: best!.mesh, fallback: best!.fallback) {
                    best = (resource, report, mesh, extracted.1)
                }

                if isMain, !extracted.1, mesh.triangleCount >= 90 {
                    break
                }
            } catch {
                continue
            }
        }

        guard let best else {
            throw ConvertedWorldImportError.noWorldMesh(lastSource)
        }

        let positions = best.mesh.vertices
        let indices = best.mesh.indices.map(UInt32.init)
        guard let first = positions.first else {
            throw ConvertedWorldImportError.noWorldMesh(best.resource.fileName)
        }

        var boundsMin = first
        var boundsMax = first
        for value in positions.dropFirst() {
            boundsMin = SIMD3<Float>(
                min(boundsMin.x, value.x),
                min(boundsMin.y, value.y),
                min(boundsMin.z, value.z)
            )
            boundsMax = SIMD3<Float>(
                max(boundsMax.x, value.x),
                max(boundsMax.y, value.y),
                max(boundsMax.z, value.z)
            )
        }

        let converted = ConvertedMesh(
            positions: positions,
            indices: indices,
            boundsMin: boundsMin,
            boundsMax: boundsMax,
            materialGroups: [.init(materialID: 0, firstIndex: 0, indexCount: UInt32(indices.count))]
        )

        let data = try ConvertedMeshFormat.encode(converted)
        _ = try ConvertedMeshFormat.decode(data)

        let meshPath = "world/area.mesh"
        let worldDirectory = stagingURL.appendingPathComponent("world", isDirectory: true)
        let outputURL = stagingURL.appendingPathComponent(meshPath, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: worldDirectory, withIntermediateDirectories: true)
            try data.write(to: outputURL, options: .atomic)
        } catch {
            throw ConvertedWorldImportError.writeFailed(error.localizedDescription)
        }

        progress("World conversion complete")
        return ConvertedWorldResult(
            meshPath: meshPath,
            vertexCount: positions.count,
            indexCount: indices.count,
            boundsMin: boundsMin,
            boundsMax: boundsMax,
            selectedSourceFile: best.resource.fileName,
            decodedBytes: best.report.decodedBytes,
            decodedChunkCount: best.report.decodedChunkCount,
            vertexOffset: best.mesh.vertexOffset,
            indexOffset: best.mesh.indexOffset,
            byteOrder: best.mesh.byteOrder,
            boundsFallbackUsed: best.fallback
        )
    }

    private func orderedCandidates(_ resources: [TranzitLoadedResource]) -> [TranzitLoadedResource] {
        var seen = Set<String>()
        return resources
            .filter { $0.fileName.lowercased().hasSuffix(".ff") }
            .sorted { lhs, rhs in
                let lp = priority(lhs.fileName)
                let rp = priority(rhs.fileName)
                if lp != rp { return lp < rp }
                return lhs.byteCount > rhs.byteCount
            }
            .filter { seen.insert($0.relativePath.lowercased()).inserted }
    }

    private func priority(_ name: String) -> Int {
        let lower = name.lowercased()
        if lower == "zm_transit.ff" { return 0 }
        if lower.contains("zm_transit_gump_") { return 1 }
        if lower == "common_zm.ff" { return 2 }
        if lower.contains("zm_transit") { return 3 }
        if lower.contains("common") && lower.contains("zm") { return 4 }
        return 5
    }

    private func score(resource: TranzitLoadedResource, mesh: T6RuntimeMesh, fallback: Bool) -> Int {
        var value = mesh.triangleCount * 2 + mesh.vertices.count
        if resource.fileName.lowercased() == "zm_transit.ff" { value += 50_000 }
        if !fallback { value += 20_000 }
        return value
    }
}

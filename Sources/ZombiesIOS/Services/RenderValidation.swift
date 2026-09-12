import Foundation

struct RenderValidationMetrics: Codable, Equatable, Sendable {
    var submittedTriangles: Int
    var drawnSurfaces: Int
    var nonFallbackMaterials: Int
    var residentTextures: Int
    var renderedProps: Int
    var validCamera: Bool
    var blackPixelRatio: Double

    static let zero = RenderValidationMetrics(
        submittedTriangles: 0,
        drawnSurfaces: 0,
        nonFallbackMaterials: 0,
        residentTextures: 0,
        renderedProps: 0,
        validCamera: false,
        blackPixelRatio: 1.0
    )
}

enum RenderValidation {
    static let maximumBlackPixelRatio = 0.90

    static func accepts(_ metrics: RenderValidationMetrics) -> Bool {
        metrics.submittedTriangles > 0 &&
        metrics.drawnSurfaces > 0 &&
        metrics.nonFallbackMaterials > 0 &&
        metrics.residentTextures > 0 &&
        metrics.validCamera &&
        metrics.blackPixelRatio < maximumBlackPixelRatio
    }

    static func structuralMetrics(for world: T6RenderableWorld?) -> RenderValidationMetrics {
        guard let world else { return .zero }

        let boundMaterialIDs = Set(world.surfaces.compactMap(\.materialID))
        let realMaterials = boundMaterialIDs.reduce(into: 0) { count, id in
            if let material = world.materials[id], !material.isFallback {
                count += 1
            }
        }
        let residentTextures = boundMaterialIDs.reduce(into: 0) { count, id in
            if let material = world.materials[id], !material.isFallback, material.baseColorTexture != nil {
                count += 1
            }
        }

        return RenderValidationMetrics(
            submittedTriangles: world.triangleCount,
            drawnSurfaces: world.surfaces.filter { !$0.indices.isEmpty }.count,
            nonFallbackMaterials: realMaterials,
            residentTextures: residentTextures,
            renderedProps: world.props.count,
            validCamera: world.spawnPosition.x.isFinite && world.spawnPosition.y.isFinite && world.spawnPosition.z.isFinite,
            blackPixelRatio: 1.0
        )
    }
}
